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
* `campaign` - the campaign id of the campaign the email is part of (see `get_or_create_campaign_id`)

##### Recipient varaibles

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

Creates a new campaign named `name`. Retruns the campaign object

#### `mailgun:get_campaigns()`

Gets all the campaigns that are available

#### `mailgun:get_or_create_campaign_id(name)`

Gets a campaign id for a campaign by name. If it doesn't exist yet a new one is created.

#### `mailgun:get_messages()`

Gets the first page of stored messages



