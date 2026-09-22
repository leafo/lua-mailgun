
ltn12 = require "ltn12"

unpack = table.unpack or unpack

describe "mailgun", ->
  local http, http_requests, http_responses

  send_success = ->
    200, [[{"id": "123", "message": "Queued. Thank you." }]]

  send_fail = ->
    400, [[{"message": "'from' parameter is missing" }]]

  stub_http = (...) ->
    table.insert http_responses, {...}

  before_each ->
    http_requests = {}
    http_responses = {}
    http = -> {
      request: (opts) ->
        table.insert http_requests, opts
        for {pattern, response} in *http_responses
          if (opts.url or "")\match pattern
            status, body = response!

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
    import parse_query_string from require "mailgun.util"

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
    import Mailgun from require "mailgun"
    Mailgun {
      domain: "leafo.net"
      api_key: "hello-world"
    }

  describe "verify_webhook_signature", ->
    local client

    before_each ->
      import Mailgun from require "mailgun"
      client = Mailgun {
        domain: "leafo.net"
        api_key: "api:hello-world"
      }

    it "valid signature", ->
      assert client\verify_webhook_signature "1564705897", "mytoken",
        "18ced557f769caaab4676366036594dc2dae9d0dca9871290e872b24c6dc6aff"

    it "signature mismatch", ->
      assert.same {
        nil, "signature mismatch"
      }, {
        client\verify_webhook_signature "1564705897", "mytoken",
          "18ced557f769caaab4676366036594dc2dae9d0dca9871290e872b24c6dc6afg"
      }


  describe "region", ->
    it "uses EU endpoint", ->
      import Mailgun from require "mailgun"
      mailgun = Mailgun {
        domain: "leafo.net"
        api_key: "hello-world"
        region: "eu"
        http: http
      }

      mailgun\api_request "/hello"
      req = unpack http_requests
      assert.same "https://api.eu.mailgun.net/v3/leafo.net/hello", req.url
      assert.same "api.eu.mailgun.net", req.headers.Host

    it "uses custom api_prefix", ->
      import Mailgun from require "mailgun"
      mailgun = Mailgun {
        domain: "leafo.net"
        api_key: "hello-world"
        api_prefix: "http://localhost:8080"
        http: http
      }

      mailgun\api_request "/hello"
      req = unpack http_requests
      assert.same "http://localhost:8080/v3/leafo.net/hello", req.url
      assert.same "localhost:8080", req.headers.Host

    it "fails on unknown region", ->
      import Mailgun from require "mailgun"
      assert.has_error ->
        Mailgun {
          domain: "leafo.net"
          api_key: "hello-world"
          region: "mars"
        }

  describe "with mailgun", ->
    local mailgun
    before_each ->
      import Mailgun from require "mailgun"
      mailgun = Mailgun {
        domain: "leafo.net"
        api_key: "hello-world"
        http: http
      }

    it "performs GET api request", ->
      mailgun\api_request "/hello"
      assert.same 1, #http_requests
      req = unpack http_requests
      assert.same "GET", req.method
      assert.same "https://api.mailgun.net/v3/leafo.net/hello", req.url
      assert.same req.headers, {
        Host: "api.mailgun.net"
        Authorization: "Basic aGVsbG8td29ybGQ="
      }

    it "performs POST api request", ->
      mailgun\api_request "/world", some: "data"
      assert.same 1, #http_requests
      req = unpack http_requests

      assert.same "POST", req.method
      assert.same "https://api.mailgun.net/v3/leafo.net/world", req.url
      assert.same req.headers, {
        Host: "api.mailgun.net"
        Authorization: "Basic aGVsbG8td29ybGQ="
        "Content-length": 9
        "Content-type": "application/x-www-form-urlencoded"
      }


    describe "send_email", ->
      it "sends an email", ->
        stub_http ".", send_success

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
        assert.same "https://api.mailgun.net/v3/leafo.net/messages", req.url
        assert.same req.headers, {
          "Authorization": "Basic aGVsbG8td29ybGQ="
          "Content-length": 522
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
        stub_http ".", send_success

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

      it "sends an email with recipient vars and other options", ->
        stub_http ".", send_success

        assert mailgun\send_email {
          to: { "you2@example.com", "you3@example.com" }
          bcc: "cool@example.com"
          cc: { "a@itch.zone", "b@itch.zone" }
          from: "dad@itch.zone"
          subject: "Howdy"
          body: "okay sure %recipient.name%"
          track_opens: true
          tags: {"hello", "world"}
          campaign: 123
          headers: {
            "Reply-To": "leaf@leafo.zone"
          }

          "v:test": "world"
        }

        req = unpack http_requests

        assert.same {
          to: { "you2@example.com", "you3@example.com" }
          bcc: "cool@example.com"
          cc: { "a@itch.zone", "b@itch.zone" }
          from: "dad@itch.zone"
          subject: "Howdy"
          text: "okay sure %recipient.name%"
          "h:Reply-To": "leaf@leafo.zone"
          "o:campaign": "123"
          "o:tracking-opens": "yes"
          "o:tag": {
            "hello", "world"
          }
          "v:test": "world"
        }, parse_body req


      it "sends an email with a template", ->
        stub_http ".", send_success

        assert mailgun\send_email {
          to: "you@example.com"
          template: "welcome"
          template_vars: { name: "leafo" }
          "t:version": "v2"
        }

        req = unpack http_requests

        assert.same {
          from: "leafo.net <postmaster@leafo.net>"
          to: "you@example.com"
          template: "welcome"
          "t:variables": '{"name":"leafo"}'
          "t:version": "v2"
        }, parse_body req

      it "requires body without template", ->
        assert.has_error ->
          mailgun\send_email {
            to: "you@example.com"
            subject: "Howdy"
          }

      it "handles server error", ->
        stub_http ".", send_fail

        res, err, status = mailgun\send_email {
          to: { "you2@example.com", "you3@example.com" }
          subject: "Howdy"
          body: "this email will fail"
        }

        assert.same {nil, "'from' parameter is missing", 400}, {res, err, status}

      it "handles network error", ->
        import Mailgun from require "mailgun"
        mailgun = Mailgun {
          domain: "leafo.net"
          api_key: "hello-world"
          http: -> {
            request: -> nil, "timeout"
          }
        }

        res, err, status = mailgun\send_email {
          to: "you@example.com"
          subject: "Howdy"
          body: "this email will time out"
        }

        assert.same {nil, "invalid response", "timeout"}, {res, err, status}

    it "creates campaign", ->
      stub_http ".", ->
        200, [[{"campaign": {"id": 123}}]]

      assert mailgun\create_campaign "hello"

    it "gets campaigns", ->
      stub_http ".", ->
        200, [[ { "items": [{"id": 123}] } ]]

      res = assert mailgun\get_campaigns!
      assert.same {
        { id: 123 }
      }, res

    it "gets messages", ->
      stub_http ".", ->
        200, [[ { "items": [{"id": 123}] } ]]

      assert mailgun\get_events!

    it "gets or creates campaign", ->
      stub_http ".", ->
        200, [[ {
          "items": [{"name": "cool", "id": 123}]
        } ]]

      res = assert mailgun\get_or_create_campaign_id "cool"
      assert.same 123, res

    describe "logs", ->
      json = require "cjson"

      read_json = (req) ->
        out = {}
        while true
          part = req.source!
          break unless part
          table.insert out, part
        json.decode table.concat out

      it "gets logs for domain", ->
        stub_http "/v1/analytics/logs", ->
          200, [[ { "items": [{"id": 1}], "pagination": {"next": "abc"} } ]]

        items, pagination = mailgun\get_logs events: {"failed"}
        assert.same { {id: 1} }, items
        assert.same { next: "abc" }, pagination

        req = unpack http_requests
        assert.same "POST", req.method
        assert.same "https://api.mailgun.net/v1/analytics/logs", req.url
        assert.same "application/json", req.headers["Content-type"]

        assert.same {
          events: {"failed"}
          filter: {
            AND: {
              {
                attribute: "domain"
                comparator: "="
                values: { {label: "leafo.net", value: "leafo.net"} }
              }
            }
          }
        }, read_json req

      it "uses provided filter", ->
        stub_http ".", -> 200, [[ { "items": [] } ]]

        mailgun\get_logs filter: { AND: {} }
        assert.same { filter: { AND: {} } }, read_json unpack http_requests

      it "handles error", ->
        stub_http ".", -> 401, [[ { "message": "Forbidden" } ]]
        assert.same {nil, "Forbidden", 401}, { mailgun\get_logs! }

      it "iterates logs across pages", ->
        pages = {
          [[ { "items": [{"id": 1}, {"id": 2}], "pagination": {"next": "page2"} } ]]
          [[ { "items": [{"id": 3}], "pagination": {"next": "page3"} } ]]
          [[ { "items": [], "pagination": {"next": "page4"} } ]]
        }

        stub_http ".", -> 200, pages[#http_requests]

        params = { pagination: { limit: 2 } }

        assert.same {
          {id: 1}
          {id: 2}
          {id: 3}
        }, [l for l in mailgun\each_log params]

        assert.same {
          { limit: 2 }
          { limit: 2, token: "page2" }
          { limit: 2, token: "page3" }
        }, [read_json(req).pagination for req in *http_requests]

        assert.same { pagination: { limit: 2 } }, params

    it "get unsubscribes", ->
      stub_http "/unsubscribes", ->
        200, [[ { "items": [{"id": 123}] } ]]

      assert.same { {id: 123} }, mailgun\get_unsubscribes!

    it "get bounces", ->
      stub_http "/bounces", ->
        200, [[ { "items": [{"id": 123}] } ]]

      assert.same { {id: 123} }, mailgun\get_bounces!

    it "get complaints", ->
      stub_http "/complaints", ->
        200, [[ { "items": [{"id": 123}] } ]]

      assert.same { {id: 123} }, mailgun\get_complaints!

    it "iterates unsubscribes with one page", ->
      stub_http "/unsubscribes", ->
        200, [[ { "items": [{"id": 123}, {"id": 999}] } ]]

      assert.same {
        {id: 123}
        {id: 999}
      },[u for u in mailgun\each_unsubscribe!]

    it "iterates unsubscribes with two pages", ->
      -- second page
      stub_http "/unsubscribes.-page=next", ->
        200, [[ {
          "items": [{"id": 22}, {"id": 23}]
        } ]]

      -- first page
      stub_http "/unsubscribes", ->
        200, [[ {
          "items": [{"id": 12}, {"id": 13}],
          "paging": {"next": "/unsubscribes?page=next&address=next@email.com"}
        } ]]

      assert.same {
        {id: 12}
        {id: 13}
        {id: 22}
        {id: 23}
      },[u for u in mailgun\each_unsubscribe!]

    it "escapes address when getting unsubscribe", ->
      stub_http ".", -> 200, [[{}]]
      mailgun\get_unsubscribe "leafo+test@example.com"
      req = unpack http_requests
      assert.same "https://api.mailgun.net/v3/leafo.net/unsubscribes/leafo%2btest%40example%2ecom", req.url

    it "for_domain keeps client settings", ->
      import Mailgun from require "mailgun"
      client = Mailgun {
        domain: "leafo.net"
        api_key: "hello-world"
        region: "eu"
        webhook_signing_key: "signing-key"
        http: http
      }

      other = client\for_domain "itch.zone"
      assert.same "itch.zone", other.domain
      assert.same "https://api.eu.mailgun.net", other.api_prefix
      assert.same "signing-key", other.webhook_signing_key
      assert.same "itch.zone <postmaster@itch.zone>", other.default_sender

    it "validates email", ->
      stub_http ".", -> 200, [[{}]]
      mailgun\validate_email "leafo@example.com"

      assert.same 1, #http_requests
      req = unpack http_requests
      assert.same "GET", req.method
      assert.same "https://api.mailgun.net/v4/address/validate?address=leafo%40example%2ecom", req.url


