-- TODO: this is ripped from lapis, turn this into library?

url = require "socket.url"
concat = table.concat

escape = do
  e = url.escape
  (str) -> (e str)

unescape = do
  u = url.unescape
  (str) -> (u str)


local encode_base64, decode_base64

if ngx
  {:encode_base64, :decode_base64, :hmac_sha1} = ngx
else
  mime = require "mime"
  { :b64, :unb64 } = mime
  encode_base64 = (...) -> (b64 ...)
  decode_base64 = (...) -> (unb64 ...)

inject_tuples = (tbl) ->
  for tuple in *tbl
    tbl[tuple[1]] = tuple[2] or true

parse_query_string = do
  import C, P, S, Ct from require "lpeg"

  char = (P(1) - S("=&"))

  chunk = C char^1
  chunk_0 = C char^0

  tuple = Ct(chunk / unescape * "=" * (chunk_0 / unescape) + chunk)
  query = S"?#"^-1 * Ct tuple * (P"&" * tuple)^0

  (str) ->
    with out = query\match str
      inject_tuples out if out


-- todo: handle nested tables
-- takes either { hello: "world"} or { {"hello", "world"} }
encode_query_string = (t, sep="&") ->
  _escape = ngx and ngx.escape_uri or escape

  i = 0
  buf = {}
  for k,v in pairs t
    if type(k) == "number" and type(v) == "table"
      {k,v} = v

    buf[i + 1] = _escape k
    buf[i + 2] = "="
    buf[i + 3] = _escape v
    buf[i + 4] = sep
    i += 4

  buf[i] = nil
  concat buf

{:parse_query_string, :encode_query_string, :encode_base64}
