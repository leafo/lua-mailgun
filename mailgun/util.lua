local url = require("socket.url")
local concat = table.concat
local escape
do
  local e = url.escape
  escape = function(str)
    return (e(str))
  end
end
local unescape
do
  local u = url.unescape
  unescape = function(str)
    return (u(str))
  end
end
local encode_base64, decode_base64
if ngx then
  local hmac_sha1
  do
    local _obj_0 = ngx
    encode_base64, decode_base64, hmac_sha1 = _obj_0.encode_base64, _obj_0.decode_base64, _obj_0.hmac_sha1
  end
else
  local mime = require("mime")
  local b64, unb64
  b64, unb64 = mime.b64, mime.unb64
  encode_base64 = function(...)
    return (b64(...))
  end
  decode_base64 = function(...)
    return (unb64(...))
  end
end
local inject_tuples
inject_tuples = function(tbl)
  for _index_0 = 1, #tbl do
    local tuple = tbl[_index_0]
    tbl[tuple[1]] = tuple[2] or true
  end
end
local parse_query_string
do
  local C, P, S, Ct
  do
    local _obj_0 = require("lpeg")
    C, P, S, Ct = _obj_0.C, _obj_0.P, _obj_0.S, _obj_0.Ct
  end
  local char = (P(1) - S("=&"))
  local chunk = C(char ^ 1)
  local chunk_0 = C(char ^ 0)
  local tuple = Ct(chunk / unescape * "=" * (chunk_0 / unescape) + chunk)
  local query = S("?#") ^ -1 * Ct(tuple * (P("&") * tuple) ^ 0)
  parse_query_string = function(str)
    do
      local out = query:match(str)
      if out then
        inject_tuples(out)
      end
      return out
    end
  end
end
local encode_query_string
encode_query_string = function(t, sep)
  if sep == nil then
    sep = "&"
  end
  local _escape = ngx and ngx.escape_uri or escape
  local i = 0
  local buf = { }
  for k, v in pairs(t) do
    if type(k) == "number" and type(v) == "table" then
      k, v = v[1], v[2]
    end
    buf[i + 1] = _escape(k)
    buf[i + 2] = "="
    buf[i + 3] = _escape(v)
    buf[i + 4] = sep
    i = i + 4
  end
  buf[i] = nil
  return concat(buf)
end
return {
  parse_query_string = parse_query_string,
  encode_query_string = encode_query_string,
  encode_base64 = encode_base64
}
