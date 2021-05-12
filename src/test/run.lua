local lfs = require "lfs"
local has_tc, tc = pcall(require, "terminalcolours")

local status = {}
local checkmark = "\xE2\x9C\x93"
local cross = "\xE2\x9C\x98"
status.succeed = checkmark.." "
status.fail = cross.." "
status.create = "* "
if has_tc then
	status.succeed = tc(tc.fg.green)..status.succeed..tc(tc.reset)
	status.fail = tc(tc.fg.red)..status.fail..tc(tc.reset)
	status.create = tc(tc.fg.blue)..status.create..tc(tc.reset)
end

local basePath = (...)
local oldPrint = print

local function tostringAll(tbl)
	for i, arg in ipairs(tbl) do
		tbl[i] = tostring(arg)
	end
	return table.concat(tbl, "\t").."\n"
end

local function create(file)
	return function(...)
		-- oldPrint(...)
		file:write(tostringAll {...})
	end
end

local function check(file)
	local correct = file:read("a")
	file:close()
	local output = {}
	return correct, output, function(...)
		table.insert(output, tostringAll {...})
	end
end

local run = loadfile(basePath.."/lua/language.lua", "bt", setmetatable({}, {
	__index = function(_, k)
		return k == "print" and function() end or _G[k]
	end
}))

for test in lfs.dir(basePath.."/test/") do
	if test:sub(-5) == ".lang" then
		local path = basePath.."/test/"..test
		local file = io.open(path..".out", "r")
		local correct, output
		if not file then
			file = io.open(path..".out", "w")
			print = create(file)
		else
			correct, output, print = check(file)
		end
		
		run(path)
		
		if output then
			output = table.concat(output)
			if output ~= correct then
				oldPrint(status.fail..test)
				oldPrint("output:\n"..output)
				oldPrint("correct:\n"..correct)
			else
				oldPrint(status.succeed..test)
			end
		else
			oldPrint(status.create..test)
		end
		
		if io.type(file) == "file" then file:close() end
	end
end
