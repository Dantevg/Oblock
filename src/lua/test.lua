local lfs = require "lfs"
local has_tc, tc = pcall(require, "terminalcolours")

local TIMEOUT = 0.5
local MAX_LINES = 10

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

local basePath = (...) or "../test"
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

local function truncate(output, lines)
	if #output > lines then
		return true, table.concat(output, nil, 1, lines//2)
				.."[..."..(#output-lines).." lines skipped...]\n"
				..table.concat(output, nil, #output - lines//2 + 1)
	else
		return false, table.concat(output)
	end
end

local function makeWatchdogFunction(timeout)
	return function()
		if os.clock() > timeout then error "timeout" end
	end
end

local run = loadfile("oblock.lua", "bt", setmetatable({}, {
	__index = function(_, k)
		return k == "print" and function() end or _G[k]
	end
}))

for test in lfs.dir(basePath) do
	if test:sub(-3) == ".ob" then
		local path = basePath.."/"..test
		local file = io.open(path..".out", "r")
		local correct, output
		if not file then
			file = io.open(path..".out", "w")
			print = create(file)
		else
			correct, output, print = check(file)
		end
		
		local runCoro = coroutine.create(run)
		debug.sethook(runCoro, makeWatchdogFunction(os.clock() + TIMEOUT), "", 1e6)
		local success, err = coroutine.resume(runCoro, path)
		if not success then print(err) end
		
		if output then
			if table.concat(output) ~= correct then
				local truncated, output = truncate(output, MAX_LINES)
				oldPrint(status.fail..test)
				oldPrint("output:"..(truncated and " (truncated)\n" or "\n")..output)
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
