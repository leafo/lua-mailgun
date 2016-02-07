# mailgun

A Lua library for sending emails and interacting with the
[Mailgun](https://mailgun.com/) API. Compatible with OpenResty via Lapis HTTP
API, or any other Lua script via LuaSocket.

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

The `mailgun` module returns a table with a `Mailgun` constructor function to
create your interface to the API. It takess a table of options.

```lua
local Mailgun = require("mailgun").Mailgun

local m = Mailgun({
  domain = "leafo.net",
  api_key = "api:key-blah-blah-blahblah"
})
```

The following options are valid:

* `domain` - the domain to use for API requests **required**
* `api_key` - the API key to authenticate requests **required**

The default sender of any email is constructed from the `domain` like this:
`{domain} <postmaster@{domain}>`.

### Methods

#### `mailgun:send_email(opts={})`

The following are required options:

* `to` - the recipient(s) of the email. Pass an array table to send to multiple recipients
* `subject` - the subject line of the email
* `body` - the body of the email

Optional fields:

* `from` - the sender of the email (default: `{domain} <postmaster@{domain}>`)
* `html` - set to `true` to send email as HTML (default `false`)
* `cc` - recipients to cc to, same format as `to`
* `bcc` - recipients to bcc to, same format as `to`
* `track_opens` - track the open rate fo the email (default `false`)
* `tags` - an array table of tags to apply to message
* `vars` - table of recipient specific variables where the key is the recipient and value is a table of vars
* `headers` - a table of additional headers to provide

#### `mailgun:create_campaign(name)`

#### `mailgun:get_campaigns()`

#### `mailgun:get_or_create_campaign_id(name)`

#### `mailgun:get_messages()`



