#!/usr/bin/env lua

local function usage()
	print([[
usage:
    luaflare listen [OPTIONS]...
    luaflare mount PATH NAME
    luaflare unmount NAME

--port=number                     Port to bind to (default 8080).
--threads=number                  Number of threads to create (default 2).
--threads-model=string            Threading mode to use (default coroutine).
--host=string                     The address to bind to (default *).
-l, --local                       Equivalent to: --host=localhost
-t, --unit-test                   Perform unit tests and quit.
-h, --help                        Show this help.
-v, --version                     Print out version information and quit.
--no-reload                       Don't automatically reload ar_*.lua scripts
                                  when they've changed.
--max-etag-size=size              Max size to generate etag hashes for. (default
                                  64MiB).
--reverse-proxy                   Require X-Real-IP and X-Forward-For.
--trusted-reverse-proxies=string  Comma delimitered list of trusted reverse
                                  proxies.
--x-accel-redirect=path           Use Nginx's X-Accel-Redirect to send static
                                  content; path is the internal location (the 
                                  example site uses /./)
--x-sendfile                      Use mod_xsendfile to send static content.
--chunk-size                      Number of bytes to send per chunk (default
                                  128KiB (1024*128).  Lower values means less
                                  susceptible to fuzzing attacks, but lower
                                  transfer speeds.
--display-all-vars                On a Lua error, show all variables, not just
                                  related.
--scheduler-tick-rate=number      The fallback tickrate (Hz) for a schedule that
                                  yields nil. (default 60).
--max-post-length=number          The maximum length of the post data.
--systemd                         Notify systemd upon startup, and try to heartbeat
--out-pid                         Write our PID to this file post load.
]])
end

-- so we can exit ASAP, for bash completion speedy-ness
if arg[1] == "--help" then return usage() end

local luaflare
do -- for require() to check modules path
	local tp, tcp = package.path, package.cpath
	
	local path = arg[0]:match("(.+)/") or "."
	if path:sub(-4, -1) == "/bin" then
		path = path:sub(1, -5) .. "/lib/luaflare"
	end
	
	package.path = path .. "/libs/?.lua;" .. tp
	package.cpath = path .. "/libs/?.so;" .. tcp
	
	luaflare = require("luaflare")
	package.path = luaflare.lib_path .. "/libs/?.lua;" .. tp
	package.cpath = luaflare.lib_path .. "/libs/?.so;" .. tcp
end

expects = function() end
dofile(luaflare.lib_path .. "/inc/compatibility-5.1.lua")
dofile(luaflare.lib_path .. "/inc/compatibility-5.2.lua")
dofile(luaflare.lib_path .. "/inc/util.lua")
dofile(luaflare.lib_path .. "/inc/syntax_extensions.lua")

local socket = require("socket")
local ssl = require("ssl")
local posix = require("posix")
local configor = require("configor")
local lfs = require("lfs")

local hook = require("luaflare.hook")
local util = require("luaflare.util")
local script = require("luaflare.util.script")
local escape = require("luaflare.util.escape")

local shorthands = {
	v = "version",
	l = "local",
	t = "unit-test",
	h = "help"
}
script.parse_arguments(arg, shorthands)

dofile(luaflare.lib_path .. "/inc/request.lua")
dofile(luaflare.lib_path .. "/inc/response.lua")
dofile(luaflare.lib_path .. "/inc/savetotable.lua")

	
local port = tonumber(script.options.port) or 8080
local threads = tonumber(script.options.threads) or 2 -- how many threads to create
local host = script.options["local"] and "localhost" or "*"
host = script.options["host"] or host

function handle_client(client)
	local time = util.time()
	while (util.time() - time) < 2 do -- give them 2 seconds
		local request, err = Request(client)
		if not request and err then print(err) return end
		if not request then return end -- probably a keep-alive connection timing out
		
		print(request:peer()  .. " " .. request:method()  .. " " .. request:url())
		
		local response = Response(request)
			hook.safe_call("Request", request, response) -- okay, lets invoke whatever is hooked
		
		if request:is_upgraded() then return true end -- don't close the connection!!!
		response:send()
		
		if not request:headers().Connection 
		or not request:headers().Connection:lower():match("keep%-alive") 
		then -- break if the connection is not being kept alive
			break
		end
	end
end

local https = false
local params = {
	mode = "server",
--	protocol = "tlsv1",
	protocol = "sslv3",
	key = "keys/key.pem",
	certificate = "keys/certificate.pem",
--	cafile = "keys/request.pem", -- uncomment these lines if you want to verify the client
--	verify = {"peer", "fail_if_no_peer_cert"},
	options = {"all", "no_sslv2"},
	ciphers = "ALL:!ADH:@STRENGTH",
}

function main()
	if script.options["unit-test"] then
		include(luaflare.lib_path .. "/inc/unittests.lua")
		return unit_test()
	elseif script.options.version then
		return print(string.format("%s (%s)", luaflare._VERSION, _VERSION))
	elseif script.options.help then
		return usage()
	end
	
	if script.arguments[1] == "listen" then
		local thread_mdl = script.options["threads-model"] or "coroutine"
		dofile(string.format("inc/threads_%s.lua", thread_mdl))
	
		dofile(luaflare.lib_path .. "/inc/autorun.lua")
		assert(main_loop, "`main_loop()` is not defined!")
	
		main_loop()
	elseif script.arguments[1] == "mount" then
		local dir = script.arguments[2]
		local name = script.arguments[3]
		if not dir then print("error: expected PATH") return usage() end
		if not name then print("error: expected NAME") return usage() end
		
		name = luaflare.config_path .. "/sites/" .. name
		os.execute(string.format("ln -s \"`pwd`/%s\" \"%s\"", escape.argument(dir), escape.argument(name)))
		return
	elseif script.arguments[1] == "unmount" then
		local name = script.arguments[2]
		if not name then print("error: expected NAME") return usage() end
		
		name = luaflare.config_path .. "/sites/" .. name
		os.execute(string.format("rm -r \"%s\"", escape.argument(name)))
		return
	elseif script.arguments[1] then
		print("unknown action " .. script.arguments[1])
	end
end

-- update task name:
do
	local f = io.open("/proc/self/comm", "r")
	if f then
		f:close()
		f = io.open("/proc/self/comm", "w")
		f:write("luaflare")
		f:close()
	end
end

main()