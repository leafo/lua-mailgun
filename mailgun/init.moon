
ltn12 = require "ltn12"

import encode_base64, encode_query_string, parse_query_string, escape from require "mailgun.util"
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

REGION_PREFIXES = {
  us: "https://api.mailgun.net"
  eu: "https://api.eu.mailgun.net"
}

class Mailgun
  api_prefix: REGION_PREFIXES.us
  api_version: "v3"

  new: (opts={}) =>
    assert opts.domain, "missing `domain` from opts"
    assert opts.api_key, "missing `api_key` from opts"

    if opts.api_prefix
      @api_prefix = opts.api_prefix
    elseif opts.region
      @api_prefix = assert REGION_PREFIXES[opts.region], "unknown `region`: #{opts.region}"

    @http_provider = opts.http
    @domain = opts.domain
    @api_key = opts.api_key
    @webhook_signing_key = opts.webhook_signing_key
    @default_sender = opts.default_sender or "#{opts.domain} <postmaster@#{opts.domain}>"

  -- create a new instance on another domain
  for_domain: (domain) =>
    Mailgun {
      domain: domain
      api_key: @api_key
      api_prefix: @api_prefix
      webhook_signing_key: @webhook_signing_key
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
      prefix = "#{@api_prefix}/#{@api_version}/#{domain}"
      prefix .. path

    body = data and encode_query_string data
    @_http_request url, body, "application/x-www-form-urlencoded"

  -- for endpoints outside of the domain scoped v3 API that take JSON bodies
  api_json_request: (path, data) =>
    @_http_request "#{@api_prefix}#{path}", json.encode(data), "application/json"

  _http_request: (url, body, content_type) =>
    out = {}
    req = {
      :url
      source: body and ltn12.source.string(body) or nil
      method: body and "POST" or "GET"
      headers: {
        "Host": url\match "^https?://([^/]+)"
        "Content-type": body and content_type or nil
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
      return nil, res.message or res, status

    res

  send_email: (opts={}) =>
    {:to, :subject, :body, :domain} = opts

    assert to, "missing recipients"

    -- stored templates can provide the subject and body
    unless opts.template
      assert subject, "missing subject"
      assert body, "missing body"

    domain or= @domain

    data = {
      from: opts.from or @default_sender
      subject: subject
      template: opts.template
    }

    if body
      data[opts.html and "html" or "text"] = body

    if opts.template_vars
      data["t:variables"] = json.encode opts.template_vars

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

    -- deprecated, Mailgun dropped campaigns in favor of tags
    if c = opts.campaign
      data["o:campaign"] = c

    for k, v in pairs opts
      if k\match "^[%w]+:"
        data[k] = v

    @api_request "/messages", data, domain

  -- deprecated, Mailgun dropped campaigns in favor of tags
  create_campaign: (name) =>
    res, err = @api_request "/campaigns", { :name }

    if res
      res.campaign
    else
      res, err

  -- deprecated
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

  -- Logs are account wide, so results are limited to this client's domain
  -- unless a filter is provided
  get_logs: (params={}) =>
    body = {k,v for k,v in pairs params}
    body.filter or= {
      AND: {
        {
          attribute: "domain"
          comparator: "="
          values: { {label: @domain, value: @domain} }
        }
      }
    }

    res, err, status = @api_json_request "/v1/analytics/logs", body

    if res
      res.items, res.pagination
    else
      nil, err, status

  each_log: (params={}) =>
    params = {k,v for k,v in pairs params}
    params.pagination = {k,v for k,v in pairs params.pagination or {}}

    coroutine.wrap ->
      while true
        items, pagination = @get_logs params
        return unless items and next items

        for item in *items
          coroutine.yield item

        return unless pagination and pagination.next
        params.pagination.token = pagination.next

  get_unsubscribes: items_method "/unsubscribes"
  each_unsubscribe: => @_each_item @get_unsubscribes
  get_unsubscribe: (email) => @api_request "/unsubscribes/#{escape email}"

  get_bounces: items_method "/bounces"
  each_bounce: => @_each_item @get_bounces
  get_bounce: (email) => @api_request "/bounces/#{escape email}"

  get_complaints: items_method "/complaints"
  each_complaint: => @_each_item @get_complaints
  get_complaint: (email) => @api_request "/complaints/#{escape email}"

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

  -- deprecated
  get_or_create_campaign_id: (campaign_name) =>
    local campaign_id

    for c in *assert @get_campaigns!
      if c.name == campaign_name
        campaign_id = c.id
        break

    unless campaign_id
      campaign_id = assert(@create_campaign(campaign_name)).id

    campaign_id

  verify_webhook_signature: (timestamp, token, signature) =>
    assert type(timestamp) == "string", "invalid timestamp"
    assert type(token) == "string", "invalid token"
    assert type(signature) == "string", "invalid signature"

    secret = @webhook_signing_key or @api_key\gsub "^api:", "" -- username baked into api key
    to_verify = "#{timestamp}#{token}"

    openssl_hmac = require "openssl.hmac"

    hmac = openssl_hmac.new secret, "sha256"
    expected = to_hex (hmac\final to_verify)

    unless expected == signature
      return nil, "signature mismatch"

    true

  validate_email: (address) =>
    assert type(address) == "string", "invalid address"
    @api_request "#{@api_prefix}/v4/address/validate?#{encode_query_string(:address)}"

{ :Mailgun, VERSION: "1.2.0" }
