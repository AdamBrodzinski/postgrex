defmodule Postgrex.Protocol.Messages do
  defmacro __using__(_opts) do
    quote do
      defrecordp :auth, [:type, :data]
      defrecordp :startup, [:params]
      defrecordp :password, [:pass]
      defrecordp :error, [:fields]
    end
  end
end

defmodule Postgrex.Protocol do
  use Postgrex.Protocol.Messages

  @protocol_vsn_major 3
  @protocol_vsn_minor 0

  @auth_types [ ok: 0, kerberos: 2, cleartext: 3, md5: 5, scm: 6, gss: 7,
                sspi: 9, gss_cont: 8 ]

  @error_fields [ severity: ?S, code: ?C, message: ?M, detail: ?D, hint: ?H,
                  position: ?P, internal_position: ?p, internal_query: ?q,
                  where: ?W, file: ?F, line: ?L, routine: ?R ]

  Enum.each(@auth_types, fn { type, value } ->
    def decode_auth_type(unquote(value)), do: unquote(type)
  end)

  Enum.each(@error_fields, fn { field, char } ->
    def decode_field_type(unquote(char)), do: unquote(field)
  end)

  # auth
  def decode(?R, size, << type :: size(32), rest :: binary >>) do
    type = decode_auth_type(type)
    case type do
      :md5 -> << data :: [binary, size(4)] >> = rest
      :gss_cont ->
        rest_size = size - 2
        << data :: size(rest_size) >> = rest
      _ -> data = nil
    end
    auth(type: type, data: data)
  end

  # error
  def decode(?E, _size, rest) do
    fields = decode_fields(rest)
    error(fields: fields)
  end

  def encode(msg) do
    { first, iolist } = encode_msg(msg)
    binary = iolist_to_binary(iolist)
    size = byte_size(binary) + 4

    if first do
      << first :: size(8), size :: size(32), binary :: binary >>
    else
     << size :: size(32), binary :: binary >>
   end
  end

  # startup
  defp encode_msg(startup(params: params)) do
    params = Enum.flat_map(params, fn { key, value } ->
      [ to_string(key), 0, value, 0 ]
    end)
    vsn = << @protocol_vsn_major :: size(16), @protocol_vsn_minor :: size(16) >>
    { nil, [vsn, params, 0] }
  end

  # password
  defp encode_msg(password(pass: pass)) do
    { ?p, [pass, 0] }
  end

  ### decode helpers ###

  defp decode_fields(<< 0 >>), do: []

  defp decode_fields(<< field :: size(8), rest :: binary >>) do
    type = decode_field_type(field)
    { string, rest } = decode_string(rest)
    [ { type, string } | decode_fields(rest) ]
  end

  defp decode_string(bin) do
    { pos, 1 } = :binary.match(bin, << 0 >>)
    { string, << 0, rest :: binary >> } = :erlang.split_binary(bin, pos)
    { string, rest }
  end
end
