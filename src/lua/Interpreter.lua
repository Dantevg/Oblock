local tc = require "terminalcolours"

local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter.new()
	local self = {}
	local stdlib = require "stdlib"
	self.environment = Interpreter.Environment(nil, stdlib.Block())
	stdlib.initEnv(self.environment)
	return setmetatable(self, Interpreter)
end

function Interpreter:interpret(program)
	-- Resolve
	local globalScope = {}
	for k in pairs(self.environment.block.env) do
		globalScope[k] = true
	end
	local success, err = pcall(program.resolve, program, globalScope)
	if not success then
		if type(err) == "table" then Interpreter.printError(err) else error(err, 0) end
		return
	end
	
	-- Run
	local results = {pcall(program.evaluate, program, self.environment)}
	if results[1] then
		return table.unpack(results, 2)
	else
		local err = results[2]
		if type(err) == "table" and err.__name == "Error" then
			Interpreter.printError(err)
		else
			print(err)
		end
		return
	end
end

function Interpreter.isCallable(fn)
	return fn and type(fn) == "table" and fn:has "()"
end

function Interpreter.error(message, loc, sourceLoc)
	error(require("stdlib").Error(message, loc, sourceLoc), 0)
end

function Interpreter.printError(err)
	if err.loc then
		print(tc(tc.fg.red)..string.format("[%s:%d:%d] %s",
			err.loc.file, err.loc.line, err.loc.column, err:get("message"))
			..tc(tc.reset))
	else
		print(tc(tc.fg.red)..tostring(err:get("message"))..tc(tc.reset))
	end
	if err.sourceLoc then
		print(tc(tc.fg.blue)..string.format("(value came from %s:%d:%d)",
			err.sourceLoc.file, err.sourceLoc.line, err.sourceLoc.column)..tc(tc.reset))
	end
	local traceback = {err:get("traceback"):spread()}
	if #traceback > 0 then
		print(tc(tc.fg.red)..table.concat(traceback, "\n")..tc(tc.reset))
	end
end

function Interpreter.context(loc, trace, fn, ...)
	local values = {pcall(fn, ...)}
	if values[1] then
		return table.unpack(values, 2)
	else
		local err = values[2]
		if type(err) == "table" and err.__name == "Error" then
			err:get("traceback"):push("\tin "..tostring(trace))
			if not err.loc then err.loc = loc end
			error(err, 0)
		else
			error(err, 0)
		end
	end
end



Interpreter.Environment = {}
Interpreter.Environment.__name = "Environment"
Interpreter.Environment.__index = Interpreter.Environment

function Interpreter.Environment.new(parent, block)
	local self = {}
	self.parent = parent
	self.block = block
	return setmetatable(self, Interpreter.Environment)
end

function Interpreter.Environment:setAtLevel(key, value, modifiers, level)
	if level == 0 then
		self:setHere(key, value, modifiers)
	elseif self.parent then
		self.parent:setAtLevel(key, value, modifiers, level - 1)
	end
end

function Interpreter.Environment:setHere(key, value, modifiers)
	self.block:set(key, value, modifiers)
end

function Interpreter.Environment:get(key, level)
	if level == 0 and self.block:has(key) then
		return self.block:get(key)
	elseif self.parent then
		return self.parent:get(key, level and level-1)
	end
end

setmetatable(Interpreter.Environment, {
	__call = function(_, ...) return Interpreter.Environment.new(...) end,
})



return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})
