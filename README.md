# mailgun

![test](https://github.com/leafo/lua-mailgun/workflows/test/badge.svg)

A Lua library for sending emails and interacting with the
[Mailgun](https://mailgun.com/) API. Compatible with OpenResty via Lapis HTTP
API, or any other Lua script via LuaSocket.

*At the moment this library only implements a subset of the API. If there's an
missing API method feel free to open an issue.*

## Example

```lua
local Mailgun = require("mailgun").Mailgun

local m = Mailgun({
  domain = "leafo.net",
  api_key = "api:key-blah-blah-blahblah"
})

m:send_email({
  to = "you@example.com",
  subject = "Important message here",
  html = true,
  body = [[
    <h1>Hello world</h1>
    <p>Here is my email to you.</p>
    <hr />
    <p>
      <a href="%unsubscribe_url%">Unsubscribe</a>
    </p>
  ]]
})
```

## Install

```
luarocks install mailgun
```

## Reference

The `Mailgun` constructor can be used to create a new client to Mailgun. It's
found in the `mailgun` module.

```lua
local Mailgun = require("mailgun").Mailgun

local m = Mailgun({
  domain = "leafo.net",
  api_key = "api:key-blah-blah-blahblah"
})
```

The following options are valid:

* `domain` - the domain to use for API requests (**required**)
* `api_key` - the API key to authenticate requests (**required**)
* `webhook_signing_key` - key used for webhook signature verification, defaults to api key without username (*optional*)
* `default_sender` - the sender to use for `send_email` when a sender is not provided (*optional*)
* `http` - set the HTTP client (*optional*)

The value of `default_sender` has a default created from the `domain` like
this: `{domain} <postmaster@{domain}>`.

### HTTP Client

If a HTTP client is not specified, this library will pick `lapis.nginx.http`
when inside of Nginx (OpenResty), otherwise it will fall back on `ssl.https`
(LuaSocket & LuaSec)

The client can be changed by providing an `http` option to the constructor. If
a string is passed, it will be required as a module name. For example, you can
use [lua-http](https://github.com/daurnimator/lua-http) by passing in `http = "http.compat.socket"`

Alternatively, a function can be passed in. The function will be called once
and the return value will be used as the http module. (It should be a table
with a request function that works like LuaSocket)

### Methods

#### `mailgun:send_email(opts={})`

The following are required options:

* `to` - the recipient(s) of the email. Pass an array table to send to multiple recipients
* `subject` - the subject line of the email
* `body` - the body of the email

Optional fields:

* `from` - the sender of the email (default: `{domain} <postmaster@{domain}>`)
* `html` - set to `true` to send email as HTML (default `false`)
* `domain` - use a different domain than the default
* `cc` - recipients to cc to, same format as `to`
* `bcc` - recipients to bcc to, same format as `to`
* `track_opens` - track the open rate fo the email (default `false`)
* `tags` - an array table of tags to apply to message
* `vars` - table of recipient specific variables where the key is the recipient and value is a table of vars
* `headers` - a table of additional headers to provide
* `campaign` - the campaign id of the campaign the email is part of (see `get_or_create_campaign_id`)
* `v:{NAME}` - add any number of user variables with the name `{NAME}`, ie. `v:user_id`

##### Recipient variables

Using recipient variables you can bulk send many emails in a single API call.
You can parameterize your email address with different variables for each
recipient:


```lua
local vars = {
  ["leafo@example.com"] = {
    username = "L.E.A.F.",
    profile_url = "http://example.com/leafo",
  },
  ["adam@example.com"] = {
    username = "Adumb",
    profile_url = "http://example.com/adam",
  }
}

mailgun:send_email({
  to = {"leafo@example.com", "adam@example.com"},
  vars = vars,
  subject = "Hey check it out!",
  body = [[
    Hello %recipient.username%,
    We just updated your profile page. Check it out: %recipient.profile_url%
  ]]
})
```

##### Setting reply-to email

Pass the `Reply-To` header:

```lua
mailgun:send_email({
  to = "you@example.com",
  subject = "Hey check it out!",
  from = "Postmaster <postmaster@leaf.zone>",
  headers = {
    ["Reply-To"] = "leafo@leaf.zone"
  },
  body = [[
    Thanks for downloading our game, reply if you have any questions!
  ]]
})
```

#### `mailgun:create_campaign(name)`

Creates a new campaign named `name`. Returns the campaign object

#### `campaigns = mailgun:get_campaigns()`

Gets all the campaigns that are available

#### `mailgun:get_or_create_campaign_id(name)`

Gets a campaign id for a campaign by name. If it doesn't exist yet a new one is created.

#### `messages, paging = mailgun:get_messages()`

Gets the first page of stored messages (this uses the events API). The paging
object includes the urls for fetching subsequent pages.

#### `unsubscribes, paging = mailgun:get_unsubscribes(opts={})`

https://documentation.mailgun.com/api-suppressions.html#unsubscribes

Gets the first page of unsubscribes messages. `opts` is passed as query string
parameters.

#### `iter = mailgun:each_event(filter_params={})`

https://documentation.mailgun.com/en/latest/api-events.html

Iterates through each event, lazily fetching pages of events as needed. In
order to stop processing events before all of them have been traversed use
`break` to exit the loop.

```
for e in mailgun:each_unsubscribe() do
  print(e.event)
end
```

Each event is a plain Lua table with the same format provided by the API :
<https://documentation.mailgun.com/en/latest/api-events.html#event-structure>

Uses `limit` of 300 by default, which will fetch 300 events at a time for each page.

#### `result = mailgun:get_events(params={})`

https://documentation.mailgun.com/en/latest/api-events.html

Issues API call to `GET /<domain>/events` with provided parameters. If you want
to iterate over events see `each_event`.

#### `iter = mailgun:each_unsubscribe()`

Iterates through each message (fetching each page as needed)

```lua
for unsub in mailgun:each_unsubscribe() do
  print(unsub.address)
end
```

#### `bounces, paging = mailgun:get_bounces(opts={})`

https://documentation.mailgun.com/api-suppressions.html#bounces

Gets the first page of unsubscribes bounces. `opts` is passed as query string
parameters.

#### `iter = mailgun:each_bounce()`

Iterates through each bounce (fetching each page as needed). Similar to
`get_unsubscribes`.

#### `complaints, paging = mailgun:get_complaints(opts={})`

https://documentation.mailgun.com/api-suppressions.html#view-all-complaints

Gets the first page of complaints messages. `opts` is passed as query string
parameters.

#### `iter = mailgun:each_complaint()`

Iterates through each complaint (fetching each page as needed). Similar to
`get_unsubscribes`.


#### `new_mailgun = mailgun:for_domain(domain)`

Returns a new instance of the API client configured the same way, but with the
domain replaced with the provided domain. If you have multiple domains on your
account you can use this to switch to them for any of the `get_` methods.

#### `mailgun:verify_webhook_signature(timestamp, token, signature)`

Verify signature of a webhook call using the stored API key as described here: <https://documentation.mailgun.com/en/latest/user_manual.html#webhooks>

Returns `true` if the signature is validated, otherwise returns `nil` and an error message.

If any of the arguments aren't provided, an error is thrown.

#### `mailgun:validate_email(email_address)`

Look up email using the email validation service described here: <https://documentation.mailgun.com/en/latest/api-email-validation.html#email-validation>

Returns a Lua object with results of validation

# Changelog

Changelog now available on GitHub releases: https://github.com/leafo/lua-mailgun/releases

## License (MIT)

Copyright (C) 2022 by Leaf Corcoran

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

