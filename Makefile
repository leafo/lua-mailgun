.PHONY: local lint build

local: build
	luarocks --lua-version=5.1 make --local mailgun-dev-1.rockspec

build: 
	moonc mailgun
 
lint:
	moonc -l mailgun

