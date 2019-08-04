local ltn12 = require("ltn12")
local encode_base64, encode_query_string, parse_query_string
do
  local _obj_0 = require("mailgun.util")
  encode_base64, encode_query_string, parse_query_string = _obj_0.encode_base64, _obj_0.encode_query_string, _obj_0.parse_query_string
end
local concat
concat = table.concat
local json = require("cjson")
local add_recipients
add_recipients = function(data, field, emails)
  if not (emails) then
    return 
  end
  if type(emails) == "table" then
    for _index_0 = 1, #emails do
      local email = emails[_index_0]
      table.insert(data, {
        field,
        email
      })
    end
  else
    data[field] = emails
  end
end
local items_method
items_method = function(path, items_field, paging_field)
  if items_field == nil then
    items_field = "items"
  end
  if paging_field == nil then
    paging_field = "paging"
  end
  return function(self, opts)
    if opts == nil then
      opts = { }
    end
    local res, err = self:api_request(tostring(path) .. "?" .. tostring(encode_query_string(opts)))
    if res then
      return res[items_field], res[paging_field]
    else
      return nil, err
    end
  end
end
local to_hex
do
  local hex_c
  hex_c = function(c)
    return string.format("%02x", string.byte(c))
  end
  to_hex = function(str)
    return (str:gsub(".", hex_c))
  end
end
local Mailgun
do
  local _class_0
  local _base_0 = {
    api_prefix = "https://api.mailgun.net",
    api_version = "v3",
    for_domain = function(self, domain)
      return Mailgun({
        domain = domain,
        api_key = self.api_key,
        http = self.http_provider
      })
    end,
    http = function(self)
      if not (self._http) then
        self.http_provider = self.http_provider or (function()
          if ngx then
            return "lapis.nginx.http"
          else
            return "ssl.https"
          end
        end)()
        if type(self.http_provider) == "function" then
          self._http = self:http_provider()
        else
          self._http = require(self.http_provider)
        end
      end
      return self._http
    end,
    api_request = function(self, path, data, domain)
      if domain == nil then
        domain = self.domain
      end
      local url
      if path:match("^https?:") then
        url = path
      else
        local prefix = tostring(self.api_prefix) .. "/" .. tostring(self.api_version) .. "/" .. tostring(domain)
        url = prefix .. path
      end
      local body = data and encode_query_string(data)
      local out = { }
      local req = {
        url = url,
        source = body and ltn12.source.string(body) or nil,
        method = data and "POST" or "GET",
        headers = {
          ["Host"] = "api.mailgun.net",
          ["Content-type"] = body and "application/x-www-form-urlencoded" or nil,
          ["Content-length"] = body and #body or nil,
          ["Authorization"] = "Basic " .. encode_base64(self.api_key)
        },
        sink = ltn12.sink.table(out),
        protocol = not ngx and "sslv23" or nil
      }
      local _, status = self:http().request(req)
      return self:format_response(concat(out), status)
    end,
    format_response = function(self, res, status)
      pcall(function()
        res = json.decode(res)
      end)
      if res == "" or not res then
        res = "invalid response"
      end
      if status ~= 200 then
        return nil, res.message or res
      end
      return res
    end,
    send_email = function(self, opts)
      if opts == nil then
        opts = { }
      end
      local to, subject, body, domain
      to, subject, body, domain = opts.to, opts.subject, opts.body, opts.domain
      assert(to, "missing recipients")
      assert(subject, "missing subject")
      assert(body, "missing body")
      domain = domain or self.domain
      local data = {
        from = opts.from or self.default_sender,
        subject = subject,
        [opts.html and "html" or "text"] = body
      }
      add_recipients(data, "to", to)
      add_recipients(data, "cc", opts.cc)
      add_recipients(data, "bcc", opts.bcc)
      if opts.tags then
        local _list_0 = opts.tags
        for _index_0 = 1, #_list_0 do
          local t = _list_0[_index_0]
          table.insert(data, {
            "o:tag",
            t
          })
        end
      end
      if opts.vars then
        data["recipient-variables"] = json.encode(opts.vars)
      end
      if opts.headers then
        for h, v in pairs(opts.headers) do
          data["h:" .. tostring(h)] = v
        end
      end
      if opts.track_opens then
        data["o:tracking-opens"] = "yes"
      end
      do
        local c = opts.campaign
        if c then
          data["o:campaign"] = c
        end
      end
      for k, v in pairs(opts) do
        if k:match("^[%w]+:") then
          data[k] = v
        end
      end
      return self:api_request("/messages", data, domain)
    end,
    create_campaign = function(self, name)
      local res, err = self:api_request("/campaigns", {
        name = name
      })
      if res then
        return res.campaign
      else
        return res, err
      end
    end,
    get_campaigns = function(self)
      local res, err = self:api_request("/campaigns")
      if res then
        return res.items, res
      else
        return res, err
      end
    end,
    get_events = items_method("/events"),
    each_event = function(self, opts)
      if opts == nil then
        opts = { }
      end
      opts.limit = opts.limit or 300
      return self:_each_item(self.get_events, opts)
    end,
    get_unsubscribes = items_method("/unsubscribes"),
    each_unsubscribe = function(self)
      return self:_each_item(self.get_unsubscribes)
    end,
    get_unsubscribe = function(self, email)
      return self:api_request("/unsubscribes/" .. tostring(email))
    end,
    get_bounces = items_method("/bounces"),
    each_bounce = function(self)
      return self:_each_item(self.get_bounces)
    end,
    get_bounce = function(self, email)
      return self:api_request("/bounces/" .. tostring(email))
    end,
    get_complaints = items_method("/complaints"),
    each_complaint = function(self)
      return self:_each_item(self.get_complaints)
    end,
    get_complaint = function(self, email)
      return self:api_request("/complaints/" .. tostring(email))
    end,
    _each_item = function(self, getter, params)
      local parse_url = require("socket.url").parse
      local after_value
      return coroutine.wrap(function()
        local page_params = {
          limit = 1000
        }
        if params then
          for k, v in pairs(params) do
            page_params[k] = v
          end
        end
        local page, paging = getter(self, page_params)
        while true do
          if not (page) then
            return 
          end
          if not (next(page)) then
            return 
          end
          for _index_0 = 1, #page do
            local item = page[_index_0]
            coroutine.yield(item)
          end
          if not (paging and paging.next) then
            return 
          end
          local res, err = self:api_request(paging.next)
          if not (res) then
            return 
          end
          page = res.items
          paging = res.paging
        end
      end)
    end,
    get_or_create_campaign_id = function(self, campaign_name)
      local campaign_id
      local _list_0 = assert(self:get_campaigns())
      for _index_0 = 1, #_list_0 do
        local c = _list_0[_index_0]
        if c.name == campaign_name then
          campaign_id = c.id
          break
        end
      end
      if not (campaign_id) then
        campaign_id = assert(self:create_campaign(campaign_name)).id
      end
      return campaign_id
    end,
    verify_webhook_signature = function(self, timestamp, token, signature)
      assert(type(timestamp) == "string", "invalid timestamp")
      assert(type(token) == "string", "invalid token")
      assert(type(signature) == "string", "invalid signature")
      local secret = self.webhook_signing_key or self.api_key:gsub("^api:", "")
      local to_verify = tostring(timestamp) .. tostring(token)
      local openssl_hmac = require("openssl.hmac")
      local hmac = openssl_hmac.new(secret, "sha256")
      local expected = to_hex((hmac:final(to_verify)))
      if not (expected == signature) then
        return nil, "signature mismatch"
      end
      return true
    end,
    validate_email = function(self, address)
      assert(type(address) == "string", "invalid address")
      return self:api_request(tostring(self.api_prefix) .. "/v4/address/validate?" .. tostring(encode_query_string({
        address = address
      })))
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      if opts == nil then
        opts = { }
      end
      assert(opts.domain, "missing `domain` from opts")
      assert(opts.api_key, "missing `api_key` from opts")
      self.http_provider = opts.http
      self.domain = opts.domain
      self.api_key = opts.api_key
      self.webhook_signing_key = opts.webhook_signing_key
      self.default_sender = opts.default_sender or tostring(opts.domain) .. " <postmaster@" .. tostring(opts.domain) .. ">"
    end,
    __base = _base_0,
    __name = "Mailgun"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Mailgun = _class_0
end
return {
  Mailgun = Mailgun,
  VERSION = "1.1.0"
}
