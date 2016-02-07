
ltn12 = require "ltn12"

describe "mailgun", ->
  local Mailgun
  local http_requests, http_responses

  send_success = ->
    200, [[{"id": "123", "message": "Queued. Thank you." }]]

  send_fail = ->
    400, [[{"message": "'from' parameter is missing" }]]

  before_each ->
    http_requests = {}
    http_responses = {}

    Mailgun = class extends require("mailgun").Mailgun
      http: =>
        {
          request: (opts) ->
            table.insert http_requests, opts
            for k,v in pairs http_responses
              if (opts.url or "")\match k
                status, body = v!

                if sink = body and opts.sink
                  sink body

                return 1, status
        }

  parse_body = (req) ->
    return unless req.source

    out = {}
    while true
      part = req.source!
      break unless part
      table.insert out, part

    body = table.concat out
    import parse_query_string from require "lapis.util"

    out = {}
    for {key, val} in *parse_query_string body
      if out[key]
        if type(out[key]) == "table"
          table.insert out[key], val
        else
          out[key] = {out[key], val}
      else
        out[key] = val
    out

  it "creates a mailgun object", ->
    Mailgun {
      domain: "leafo.net"
      api_key: "hello-world"
    }

  describe "with mailgun", ->
    local mailgun
    before_each ->
      mailgun = Mailgun {
        domain: "leafo.net"
        api_key: "hello-world"
      }

    it "performs GET api request", ->
      mailgun\api_request "/hello"
      assert.same 1, #http_requests
      req = unpack http_requests
      assert.same "GET", req.method
      assert.same "https://api.mailgun.net/v2/leafo.net/hello", req.url
      assert.same req.headers, {
        Host: "api.mailgun.net"
        Authorization: "Basic aGVsbG8td29ybGQ="
      }

    it "performs POST api request", ->
      mailgun\api_request "/world", some: "data"
      assert.same 1, #http_requests
      req = unpack http_requests

      assert.same "POST", req.method
      assert.same "https://api.mailgun.net/v2/leafo.net/world", req.url
      assert.same req.headers, {
        Host: "api.mailgun.net"
        Authorization: "Basic aGVsbG8td29ybGQ="
        "Content-length": 9
        "Content-type": "application/x-www-form-urlencoded"
      }

    it "sends an email", ->
      http_responses["."] = send_success

      email_html = [[
        <h1>Hello world</h1>
        <p>Here is my email to you.</p>
        <hr />
        <p>
          <a href="%unsubscribe_url%">Unsubscribe</a>
        </p>
      ]]

      assert mailgun\send_email {
        to: "you@example.com"
        subject: "Important message here"
        html: true
        body: email_html
      }

      assert.same 1, #http_requests
      req = unpack http_requests

      assert.same "POST", req.method
      assert.same "https://api.mailgun.net/v2/leafo.net/messages", req.url
      assert.same req.headers, {
        "Authorization": "Basic aGVsbG8td29ybGQ="
        "Content-length": 480
        "Content-type": "application/x-www-form-urlencoded"
        "Host": "api.mailgun.net"
      }

      assert.same {
        from: "leafo.net <postmaster@leafo.net>"
        to: "you@example.com"
        subject: "Important message here"
        html: email_html
      }, parse_body req

    it "sends an email to many people", ->
      http_responses["."] = send_success

      assert mailgun\send_email {
        to: { "you2@example.com", "you3@example.com" }
        subject: "Howdy"
        body: "okay sure"
      }

      req = unpack http_requests

      assert.same {
        from: "leafo.net <postmaster@leafo.net>"
        to: { "you2@example.com", "you3@example.com" }
        subject: "Howdy"
        text: "okay sure"
      }, parse_body req


    it "handles server error", ->
      http_responses["."] = send_fail

      res, err = mailgun\send_email {
        to: { "you2@example.com", "you3@example.com" }
        subject: "Howdy"
        body: "this email will fail"
      }

      assert.same {nil, "'from' parameter is missing"}, {res, err}
