
ltn12 = require "ltn12"

import encode_base64, encode_query_string, parse_query_string from require "mailgun.util"
import concat from table

json = require "cjson"

add_recipients = (data, field, emails) ->
  return unless emails

  if type(emails) == "table"
    for email in *emails
      table.insert data, {field, email}
  else
    data[field] = emails

items_method = (path, items_field="items", paging_field="paging") ->
  (opts={}) =>
    res, err = @api_request "#{path}?#{encode_query_string opts}"

    if res
      res[items_field], res[paging_field]
    else
      nil, err

to_hex = do
  hex_c = (c) -> string.format "%02x", string.byte c
  (str) -> (str\gsub ".", hex_c)

class Mailgun
  api_path: "https://api.mailgun.net/v3/"

  new: (opts={}) =>
    assert opts.domain, "missing `domain` from opts"
    assert opts.api_key, "missing `api_key` from opts"

    @http_provider = opts.http
    @domain = opts.domain
    @api_key = opts.api_key
    @default_sender = opts.default_sender or "#{opts.domain} <postmaster@#{opts.domain}>"

  -- create a new instance on another domain
  for_domain: (domain) =>
    Mailgun {
      domain: domain
      api_key: @api_key
      http: @http_provider
    }

  http: =>
    unless @_http
      @http_provider or= if ngx
        "lapis.nginx.http"
      else
        "ssl.https"

      @_http = if type(@http_provider) == "function"
        @http_provider!
      else
        require @http_provider

    @_http

  api_request: (path, data, domain=@domain) =>
    url = if path\match "^https?:"
      path
    else
      prefix = "#{@api_path}#{domain}"
      prefix .. path

    body = data and encode_query_string data

    out = {}
    req = {
      :url
      source: body and ltn12.source.string(body) or nil
      method: data and "POST" or "GET"
      headers: {
        "Host": "api.mailgun.net"
        "Content-type": body and "application/x-www-form-urlencoded" or nil
        "Content-length": body and #body or nil
        "Authorization": "Basic " .. encode_base64 @api_key
      }
      sink: ltn12.sink.table out
      protocol: not ngx and "sslv23" or nil -- for luasec
    }

    _, status = @http!.request req
    @format_response concat(out), status

  format_response: (res, status) =>
    pcall ->
      res = json.decode res

    if res == "" or not res
      res = "invalid response"

    if status != 200
      return nil, res.message or res

    res

  send_email: (opts={}) =>
    {:to, :subject, :body, :domain} = opts

    assert to, "missing recipients"
    assert subject, "missing subject"
    assert body, "missing body"

    domain or= @domain

    data = {
      from: opts.from or @default_sender
      subject: subject
      [opts.html and "html" or "text"]: body
    }

    add_recipients data, "to", to
    add_recipients data, "cc", opts.cc
    add_recipients data, "bcc", opts.bcc

    if opts.tags
      for t in *opts.tags
        table.insert data, {"o:tag", t}

    if opts.vars
      data["recipient-variables"] = json.encode opts.vars

    if opts.headers
      for h, v in pairs opts.headers
        data["h:#{h}"] = v

    if opts.track_opens
      data["o:tracking-opens"] = "yes"

    if c = opts.campaign
      data["o:campaign"] = c

    for k, v in pairs opts
      if k\match "^[%w]+:"
        data[k] = v

    @api_request "/messages", data, domain

  create_campaign: (name) =>
    res, err = @api_request "/campaigns", { :name }

    if res
      res.campaign
    else
      res, err

  get_campaigns: =>
    res, err = @api_request "/campaigns"

    if res
      res.items, res
    else
      res, err

  get_events: items_method "/events"
  each_event: (opts={}) =>
    opts.limit or= 300
    @_each_item @get_events, opts

  get_unsubscribes: items_method "/unsubscribes"
  each_unsubscribe: => @_each_item @get_unsubscribes

  get_bounces: items_method "/bounces"
  each_bounce: => @_each_item @get_bounces

  get_complaints: items_method "/complaints"
  each_complaint: => @_each_item @get_complaints

  -- iterate through every item in basic paging api endpoint
  _each_item: (getter, params) =>
    parse_url = require("socket.url").parse

    local after_value

    coroutine.wrap ->
      page_params = { limit: 1000 }
      if params
        for k,v in pairs params
          page_params[k] = v

      page, paging = getter @, page_params

      while true
        return unless page
        return unless next page

        for item in *page
          coroutine.yield item

        return unless paging and paging.next
        res, err = @api_request paging.next
        return unless res

        page = res.items
        paging = res.paging

  get_or_create_campaign_id: (campaign_name) =>
    local campaign_id

    for c in *assert @get_campaigns!
      if c.name == campaign_name
        campaign_id = c.id
        break

    unless campaign_id
      campaign_id = assert(@create_campaign(campaign_name)).id

    campaign_id

  verify_webhook_signature: (token, timestamp, signature) =>
    assert type(token) == "string", "invalid token"
    assert type(timestamp) == "string", "invalid timestamp"
    assert type(signature) == "string", "invalid signature"

    secret = @api_key\gsub "^api:", "" -- username may be baked into api key
    to_verify = "#{timestamp}#{token}"

    openssl_hmac = require "openssl.hmac"

    hmac = openssl_hmac.new secret, "sha256"
    expected = to_hex (hmac\final to_verify)

    unless expected == signature
      return nil, "invalid signature"

    true

{ :Mailgun, VERSION: "1.1.0" }
