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

