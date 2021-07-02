local tc = require "terminalcolours"

local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter.new(program)
	local self = {}
	self.program = program
	self.environment = Interpreter.Environment()
	require("stdlib")(self.environment)
	return setmetatable(self, Interpreter)
end

function Interpreter:interpret()
	-- Resolve
	local globalScope = {}
	for k in pairs(self.environment.env) do
		globalScope[k] = true
	end
	local success, err = pcall(self.program.resolve, self.program, globalScope)
	if not success then
		if type(err) == "table" then Interpreter.printError(err) else error(err, 0) end
		return
	end
	
	-- Run
	local results = {pcall(self.program.evaluate, self.program, self.environment)}
	if results[1] then
		return table.unpack(results, 2)
	else
		local err = results[2]
		if type(err) == "table" and err.__name == "Error" then
			Interpreter.printError(err)
		else
			print(err)
		end
		error()
	end
end

function Interpreter.isCallable(fn)
	return fn and type(fn) == "table" and fn.call
end

function Interpreter.error(message, loc, sourceLoc)
	error(Interpreter.Error(nil, message, loc, sourceLoc), 0)
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

function Interpreter.Environment:define(key, value, modifiers)
	if type(key) == "table" then key = key.value end
	if self.env[key] then Interpreter.error("Redefinition of variable "..tostring(key)) end
	self.env[key] = {
		value = value,
		modifiers = modifiers or {}
	}
end

function Interpreter.Environment:assign(key, value, level)
	if type(key) == "table" then key = key.value end
	if self.env[key] and (not level or level == 0) then
		if self.env[key].modifiers.const then
			Interpreter.error("Attempt to mutate const variable "..tostring(key))
		end
		self.env[key].value = value
	elseif self.parent and self.parent:has(key) and (not level or level > 0) then
		self.parent:assign(key, value, level and level-1)
	else
		Interpreter.error("attempt to mutate non-existent variable "..tostring(key))
	end
end

function Interpreter.Environment:set(key, value, modifiers, level)
	if type(key) == "table" then key = key.value end
	if self.env[key] and (not level or level == 0) then
		-- if modifiers ~= nil then Interpreter.error("Redefinition of variable "..tostring(key)) end
		if self.env[key].modifiers.const then
			Interpreter.error("Attempt to mutate const variable "..tostring(key))
		end
		self.env[key].value = value
	elseif self.parent and self.parent:has(key) and (not level or level > 0) then
		self.parent:set(key, value, modifiers, level and level-1)
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



Interpreter.Block = {}
Interpreter.Block.__index = Interpreter.Block
Interpreter.Block.__name = "Block"

function Interpreter.Block.new(parent)
	local self = {}
	self.environment = Interpreter.Environment(parent)
	self.environment:set("_Proto", Interpreter.Block.proto, nil, 0)
	return setmetatable(self, Interpreter.Block)
end

function Interpreter.Block:has(key)
	return self.environment:has(key)
end

function Interpreter.Block:get(key, level)
	local value = self.environment:get(key, level)
	if not value then
		local proto = self.environment:get("_Proto", 0)
		value = proto and proto:get(key)
	end
	if value and (value.__name == "Function" or value.__name == "NativeFunction") then
		value = value:bind(self)
	end
	return value or Interpreter.Nil()
end

function Interpreter.Block:set(key, value, modifiers, level)
	return self.environment:set(key, value, modifiers, level)
end

function Interpreter.Block:pipe(other)
	if not Interpreter.isCallable(other) then error("cannot pipe into "..other.__name, 0) end
	return other:call {self}
end

function Interpreter.Block:__tostring()
	local strings = {}
	for key, value in pairs(self.environment.env) do
		-- Hide "_Proto" key
		if key ~= "_Proto" then
			table.insert(strings, tostring(key).." = "..tostring(value.value))
		end
	end
	return "{"..table.concat(strings, "; ").."}"
end

Interpreter.Block.proto = Interpreter.Block.new()

setmetatable(Interpreter.Block, {
	__call = function(_, ...) return Interpreter.Block.new(...) end,
})



Interpreter.NativeFunction = {}
Interpreter.NativeFunction.__index = Interpreter.NativeFunction
Interpreter.NativeFunction.__name = "NativeFunction"

Interpreter.NativeFunction.proto = Interpreter.Block()

function Interpreter.NativeFunction.new(parent, body, name)
	local self = Interpreter.Block(parent)
	self.body = body
	self.name = name
	self:set("_Proto", Interpreter.NativeFunction.proto, nil, 0)
	return setmetatable(self, Interpreter.NativeFunction)
end

function Interpreter.NativeFunction:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, Interpreter.NativeFunction)
end

function Interpreter.NativeFunction:call(args)
	table.insert(args, 1, self.this)
	return self.body(table.unpack(args))
end

function Interpreter.NativeFunction:__tostring()
	return self.name and "<native function: "..self.name..">" or "<native function>"
end

setmetatable(Interpreter.NativeFunction, {
	__call = function(_, ...) return Interpreter.NativeFunction.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Function = {}
Interpreter.Function.__index = Interpreter.Function
Interpreter.Function.__name = "Function"

Interpreter.Function.proto = Interpreter.Block()

function Interpreter.Function.new(parent, body, name)
	local self = Interpreter.Block(parent)
	self.body = body
	self.name = name
	self:set("_Proto", Interpreter.Function.proto, nil, 0)
	return setmetatable(self, Interpreter.Function)
end

function Interpreter.Function:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, Interpreter.Function)
end

function Interpreter.Function:call(args)
	local environment = Interpreter.Environment(self.environment)
	if self.this then environment:set("this", self.this, nil, 0) end
	local values = {pcall(Interpreter.context, self.loc, tostring(self),
		self.body, environment, args)}
	if values[1] then
		return table.unpack(values, 2)
	elseif type(values[2]) == "table" and values[2].__name == "Return" then
		return table.unpack(values[2].values)
	else
		error(values[2], 0)
	end
end

function Interpreter.Function:__tostring()
	return self.name and "<function: "..self.name..">" or "<function>"
end

setmetatable(Interpreter.Function, {
	__call = function(_, ...) return Interpreter.Function.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Value = {}
Interpreter.Value.__index = Interpreter.Value
Interpreter.Value.__name = "Value"

function Interpreter.Value.new(parent, value)
	local self = Interpreter.Block(parent)
	self.value = value
	return setmetatable(self, Interpreter.Value)
end

function Interpreter.Value:__eq(other)
	return self.value == other.value
end

function Interpreter.Value:__tostring()
	return tostring(self.value)
end

setmetatable(Interpreter.Value, {
	__call = function(_, ...) return Interpreter.Value.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Number = {}
Interpreter.Number.__index = Interpreter.Number
Interpreter.Number.__name = "Number"

Interpreter.Number.proto = Interpreter.Block()

function Interpreter.Number.new(parent, value)
	local self = Interpreter.Value(parent, tonumber(value))
	self:set("_Proto", Interpreter.Number.proto, nil, 0)
	return setmetatable(self, Interpreter.Number)
end

function Interpreter.Number:eq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return Interpreter.Boolean(nil, a == b)
end

function Interpreter.Number:neq(other)
	local val = self:get("=="):call {self, other}
	return val:get("!"):call {val}
end

function Interpreter.Number:lt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return Interpreter.Boolean(nil, a < b)
end

function Interpreter.Number:gt(other)
	local val = self:get("<"):call {self, other}
	return val:get("!"):call {val}
end

function Interpreter.Number:add(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(nil, a + b)
end

function Interpreter.Number:mul(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '*' on "..other.__name) end
	return self.new(nil, a * b)
end

function Interpreter.Number:sub(other)
	local a = tonumber(self.value)
	if other then
		local b = tonumber(other.value)
		if type(b) ~= "number" then Interpreter.error("cannot perform '-' on "..other.__name) end
		return self.new(nil, a - b)
	else
		return self.new(nil, -a)
	end
end

function Interpreter.Number:not_(env)
	return Interpreter.Boolean(env, false)
end

Interpreter.Number.__eq = Interpreter.Value.__eq
Interpreter.Number.__tostring = Interpreter.Value.__tostring

setmetatable(Interpreter.Number, {
	__call = function(_, ...) return Interpreter.Number.new(...) end,
	__index = Interpreter.Value,
})



Interpreter.String = {}
Interpreter.String.__index = Interpreter.String
Interpreter.String.__name = "String"

Interpreter.String.proto = Interpreter.Block()

function Interpreter.String.new(parent, value)
	local self = Interpreter.Value(parent, tostring(value))
	self:set("_Proto", Interpreter.String.proto, nil, 0)
	return setmetatable(self, Interpreter.String)
end

function Interpreter.String:add(other)
	local a, b = tostring(self.value), tostring(other.value)
	if type(b) ~= "string" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(nil, a..b)
end

function Interpreter.String:not_()
	return Interpreter.Boolean(nil, false)
end

Interpreter.String.__eq = Interpreter.Value.__eq
Interpreter.String.__tostring = Interpreter.Value.__tostring

setmetatable(Interpreter.String, {
	__call = function(_, ...) return Interpreter.String.new(...) end,
	__index = Interpreter.Value,
})



Interpreter.Boolean = {}
Interpreter.Boolean.__index = Interpreter.Boolean
Interpreter.Boolean.__name = "Boolean"

Interpreter.Boolean.proto = Interpreter.Block()

function Interpreter.Boolean.new(parent, value)
	local self = Interpreter.Value(parent, not not value)
	self:set("_Proto", Interpreter.Boolean.proto, nil, 0)
	return setmetatable(self, Interpreter.Boolean)
end

function Interpreter.Boolean.toBoolean(value)
	return Interpreter.Boolean(nil, value.value)
end

function Interpreter.Boolean:not_()
	return Interpreter.Boolean(nil, not self.value)
end

Interpreter.Boolean.__eq = Interpreter.Value.__eq
Interpreter.Boolean.__tostring = Interpreter.Value.__tostring

setmetatable(Interpreter.Boolean, {
	__call = function(_, ...) return Interpreter.Boolean.new(...) end,
	__index = Interpreter.Value,
})



Interpreter.Nil = {}
Interpreter.Nil.__index = Interpreter.Nil
Interpreter.Nil.__name = "Nil"

Interpreter.Nil.proto = Interpreter.Block()

function Interpreter.Nil.new(parent, loc)
	local self = Interpreter.Value(parent, nil)
	self.loc = loc
	self:set("_Proto", Interpreter.Nil.proto, nil, 0)
	return setmetatable(self, Interpreter.Nil)
end

function Interpreter.Nil:eq(other)
	return Interpreter.Boolean(nil, other.__name == "Nil")
end

function Interpreter.Nil:neq(other)
	return Interpreter.Boolean(nil, other.__name ~= "Nil")
end

function Interpreter.Nil:not_()
	return Interpreter.Boolean(nil, true)
end

Interpreter.Nil.__eq = Interpreter.Value.__eq

function Interpreter.Nil:__tostring()
	return "nil"
end

setmetatable(Interpreter.Nil, {
	__call = function(_, ...) return Interpreter.Nil.new(...) end,
	__index = Interpreter.Value,
})



Interpreter.List = {}
Interpreter.List.__index = Interpreter.List
Interpreter.List.__name = "List"

Interpreter.List.proto = Interpreter.Block()

function Interpreter.List.new(parent, elements)
	local self = Interpreter.Block(parent)
	elements = elements or {}
	for i = 1, #elements do
		self:set(i, elements[i])
	end
	self:set("length", Interpreter.Number(nil, #elements))
	self:set("_Proto", Interpreter.List.proto, nil, 0)
	return setmetatable(self, Interpreter.List)
end

function Interpreter.List:push(value)
	self:set(#self+1, value)
	self:set("length", Interpreter.Number(nil, #self))
end

function Interpreter.List:add(other)
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	for i = 1, #other do
		table.insert(values, other:get(i))
	end
	self:set("length", Interpreter.Number(nil, #self), nil, 0)
	return self.new(nil, values)
end

function Interpreter.List:spread()
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	return table.unpack(values)
end

function Interpreter.List:iterate()
	local i = 0
	return Interpreter.Function(self, function()
		i = i+1
		return self:get("this"):get(i)
	end, "iterator")
end

function Interpreter.List:__len()
	return #self.environment.env
end

function Interpreter.List:__tostring()
	local strings = {}
	for i = 1, #self do
		table.insert(strings, tostring(self:get(i)))
	end
	return "["..table.concat(strings, ", ").."]"
end

setmetatable(Interpreter.List, {
	__call = function(_, ...) return Interpreter.List.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Error = {}
Interpreter.Error.__index = Interpreter.Error
Interpreter.Error.__name = "Error"

Interpreter.Error.proto = Interpreter.Block()

function Interpreter.Error.new(parent, message, loc, sourceLoc)
	local self = Interpreter.Block(parent)
	self.loc, self.sourceLoc = loc, sourceLoc
	self:set("_Proto", Interpreter.Error.proto, nil, 0)
	self:set("message", Interpreter.String(nil, message), nil, 0)
	self:set("traceback", Interpreter.List(), nil, 0)
	return setmetatable(self, Interpreter.Error)
end

function Interpreter.Error:__tostring()
	return tostring(self:get("message")).."\n"..tostring(self:get("traceback"))
end

setmetatable(Interpreter.Error, {
	__call = function(_, ...) return Interpreter.Error.new(...) end,
	__index = Interpreter.Block,
})



local function defineProtoNativeFn(base, name, key)
	Interpreter[base].proto:set(
		key,
		Interpreter.NativeFunction(nil, Interpreter[base][name], name),
		nil, 0
	)
end

defineProtoNativeFn("Block", "pipe", "|>")

defineProtoNativeFn("Function", "call", "()")

defineProtoNativeFn("Number", "eq", "==")
defineProtoNativeFn("Number", "neq", "!=")
defineProtoNativeFn("Number", "lt", "<")
defineProtoNativeFn("Number", "gt", ">")
defineProtoNativeFn("Number", "add", "+")
defineProtoNativeFn("Number", "sub", "-")
defineProtoNativeFn("Number", "mul", "*")
defineProtoNativeFn("Number", "not_", "!")

defineProtoNativeFn("String", "add", "+")
defineProtoNativeFn("String", "not_", "!")

defineProtoNativeFn("Boolean", "not_", "!")
Interpreter.Boolean.proto:set("true", Interpreter.Boolean(nil, true), nil, 0)
Interpreter.Boolean.proto:set("false", Interpreter.Boolean(nil, false), nil, 0)

defineProtoNativeFn("Nil", "eq", "==")
defineProtoNativeFn("Nil", "neq", "!=")
defineProtoNativeFn("Nil", "not_", "!")
Interpreter.Nil.proto:set("nil", Interpreter.Nil(), nil, 0)

defineProtoNativeFn("List", "add", "+")
defineProtoNativeFn("List", "spread", "...")
Interpreter.List.proto:set("iterate",
	Interpreter.Function(nil, Interpreter.List.iterate, "iterate"),
	nil, 0
)



return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})
