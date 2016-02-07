
ltn12 = require "ltn12"

import encode_query_string from require "lapis.util"
import encode_base64 from require "lapis.util.encoding"
import concat from table

json = require "cjson"

add_recipients = (data, field, emails) ->
  return unless emails

  if type(emails) == "table"
    for email in *emails
      table.insert data, {field, email}
  else
    data[field] = emails

class Mailgun
  api_path: "https://api.mailgun.net/v2/"

  new: (opts={}) =>
    assert opts.domain, "missing `domain` from opts"
    assert opts.api_key, "missing `api_key` from opts"

    @domain = opts.domain
    @api_key = opts.api_key
    @default_sender = "#{opts.domain} <postmaster@#{opts.domain}>"

  http: =>
    unless @_http
      @_http = if ngx
        require "lapis.nginx.http"
      else
        require "ssl.https"

    @_http

  api_request: (path, data, domain=@domain) =>
    prefix = "#{@api_path}#{domain}"

    body = data and encode_query_string data

    out = {}

    req = {
      url: prefix .. path
      source: body and ltn12.source.string(body) or nil
      method: data and "POST" or "GET"
      headers: {
        "Host": "api.mailgun.net"
        "Content-type": body and "application/x-www-form-urlencoded" or nil
        "Content-length": body and #body or nil
        "Authorization": "Basic " .. encode_base64 @api_key
      }
      sink: ltn12.sink.table out
    }

    res = @http!.request req
    concat(out), res

  send_email: (opts={}) =>
    {:to, :subject, :body, :domain} = opts

    assert to, "missing recipients"
    assert subject, "missing subject"
    assert body, "missing body"

    domain or= @domain

    data = {
      from: opts.sender or sender
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

    @api_request "/messages", data, domain

  create_campaign: (name) ->
    res = @api_request "/campaigns", { :name }
    res = json.decode res
    res.campaign

  get_campaigns: ->
    res = @api_request "/campaigns"
    res = json.decode res
    res.items

  get_messages: ->
    params = encode_query_string { event: "stored" }
    json.decode (@api_request "/events?#{params}")

  get_or_create_campaign_id: (campaign_name) ->
    local campaign_id

    for c in *@get_campaigns!
      if c.name == campaign_name
        campaign_id = c.id
        break

    unless campaign_id
      campaign_id = @create_campaign(campaign_name).id

    campaign_id

{ :Mailgun, VERSION: "0.0.1" }
