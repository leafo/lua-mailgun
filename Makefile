.PHONY: local lint build

local: build
	luarocks make --local mailgun-dev-1.rockspec

build: 
	moonc mailgun
 
lint:
	moonc -l mailgun

