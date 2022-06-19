local tc = require "terminalcolours"

local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter.new()
	local self = {}
	self.environment = Interpreter.Environment()
	require("stdlib").initEnv(self.environment)
	return setmetatable(self, Interpreter)
end

function Interpreter:interpret(program)
	-- Resolve
	local globalScope = {}
	for k in pairs(self.environment.env) do
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
	error(require("stdlib").Error(nil, message, loc, sourceLoc), 0)
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
Interpreter.Environment.__index = Interpreter.Environment

function Interpreter.Environment.new(parent)
	local self = {}
	self.parent = parent
	self.env = {}
	return setmetatable(self, Interpreter.Environment)
end

function Interpreter.Environment:setAtLevel(key, value, modifiers, level)
	if not level then
		self:updateAnywhere(key, value)
	elseif level == 0 then
		self:setHere(key, value, modifiers)
	elseif level > 0 then
		self.parent:setAtLevel(key, value, modifiers)
	end
end

function Interpreter.Environment:updateAnywhere(key, value)
	if type(key) == "table" then key = key.value end
	if self.env[key] or not self.parent or not self.parent:has(key) then
		self:setHere(key, value)
	else
		self.parent:updateAnywhere(key, value)
	end
end

function Interpreter.Environment:setHere(key, value, modifiers)
	if type(key) == "table" then key = key.value end
	if self.env[key] then
		if modifiers ~= nil and not modifiers.empty then
			Interpreter.error("Redefinition of variable "..tostring(key))
		end
		if self.env[key].modifiers.const then
			Interpreter.error("Attempt to mutate const variable "..tostring(key))
		end
		self.env[key].value = value
	else
		self.env[key] = {
			value = value,
			modifiers = modifiers or {}
		}
	end
end

function Interpreter.Environment:has(key)
	if type(key) == "table" then key = key.value end
	return self.env[key] or (self.parent and self.parent:has(key))
end

function Interpreter.Environment:get(key, level)
	if type(key) == "table" then key = key.value end
	if self.env[key] and (not level or level == 0) then
		return self.env[key].value
	elseif self.parent and (not level or level > 0) then
		return self.parent:get(key, level and level-1)
	end
	-- Not found, don't return anything (not a value of Nil) to allow inheritance
end

setmetatable(Interpreter.Environment, {
	__call = function(_, ...) return Interpreter.Environment.new(...) end,
})



return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})
