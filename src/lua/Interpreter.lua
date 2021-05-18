local Interpreter = {}
Interpreter.__index = Interpreter



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
	if self.env[key] then error("Redefinition of variable "..tostring(key), 0) end
	self.env[key] = {
		value = value,
		modifiers = modifiers or {}
	}
end

function Interpreter.Environment:assign(key, value, level)
	if type(key) == "table" then key = key.value end
	if self.env[key] and (not level or level == 0) then
		if self.env[key].modifiers.const then
			error("Attempt to mutate const variable "..tostring(key), 0)
		end
		self.env[key].value = value
	elseif self.parent and self.parent:has(key) and (not level or level > 0) then
		self.parent:assign(key, value, level and level-1)
	else
		error("attempt to mutate non-existent variable "..tostring(key), 0)
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
	return setmetatable(self, Interpreter.Block)
end

function Interpreter.Block:has(key)
	return self.environment:has(key)
end

function Interpreter.Block:get(key)
	-- TODO: should accept `level` argument?
	local value = self.environment:get(key)
	if not value then
		local proto = self.environment:get("_Proto", 0)
		value = proto and proto:get(key)
	end
	return value or Interpreter.Nil()
end

function Interpreter.Block:define(key, value, modifiers)
	return self.environment:define(key, value, modifiers)
end

function Interpreter.Block:assign(key, value)
	return self.environment:assign(key, value)
end

function Interpreter.Block:__tostring()
	local strings = {}
	for key, value in pairs(self.environment.env) do
		table.insert(strings, tostring(key).." = "..tostring(value.value))
	end
	return "{"..table.concat(strings, "; ").."}"
end

setmetatable(Interpreter.Block, {
	__call = function(_, ...) return Interpreter.Block.new(...) end,
})



Interpreter.NativeFunction = {}
Interpreter.NativeFunction.__index = Interpreter.NativeFunction
Interpreter.NativeFunction.__name = "NativeFunction"

function Interpreter.NativeFunction.new(parent, body)
	local self = Interpreter.Block(parent)
	self.body = body
	self:define("()", Interpreter.NativeFunction.call)
	return setmetatable(self, Interpreter.NativeFunction)
end

function Interpreter.NativeFunction:call(args)
	return self.body(table.unpack(args))
end

function Interpreter.NativeFunction:__tostring()
	return "<native function>"
end

setmetatable(Interpreter.NativeFunction, {
	__call = function(_, ...) return Interpreter.NativeFunction.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Function = {}
Interpreter.Function.__index = Interpreter.Function
Interpreter.Function.__name = "Function"

function Interpreter.Function.new(parent, body)
	local self = Interpreter.Block(parent)
	self.body = body
	self:define("()", Interpreter.Function.call)
	return setmetatable(self, Interpreter.Function)
end

function Interpreter.Function:call(args)
	local environment = Interpreter.Environment(self.environment)
	local values = {pcall(self.body, environment, args)}
	if values[1] then
		return table.unpack(values, 2)
	else
		local err = values[2]
		if type(err) == "table" and err.__name == "Return" then
			return table.unpack(err.values)
		else
			error(tostring(err).."\n\tin "..tostring(self), 0)
		end
	end
end

function Interpreter.Function:__tostring()
	return self.__tostring and self.__tostring() or "<function>"
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

function Interpreter.Number.new(parent, value)
	local self = Interpreter.Value(parent, tonumber(value))
	self:define("==", Interpreter.Number.eq)
	self:define("!=", Interpreter.Number.neq)
	self:define("<", Interpreter.Number.lt)
	self:define("+", Interpreter.Number.add)
	self:define("-", Interpreter.Number.sub)
	self:define("*", Interpreter.Number.mul)
	self:define("!", Interpreter.Number.not_)
	return setmetatable(self, Interpreter.Number)
end

function Interpreter.Number:eq(env, other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return Interpreter.Boolean(env, a == b)
end

function Interpreter.Number:neq(env, other)
	return Interpreter.Boolean(env, not self:eq(env, other).value)
end

function Interpreter.Number:lt(env, other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return Interpreter.Boolean(env, a < b)
end

function Interpreter.Number:add(env, other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then error("cannot perform '+' on "..other.__name, 0) end
	return self.new(env, a + b)
end

function Interpreter.Number:mul(env, other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then error("cannot perform '*' on "..other.__name, 0) end
	return self.new(env, a * b)
end

function Interpreter.Number:sub(env, other)
	local a = tonumber(self.value)
	if other then
		local b = tonumber(other.value)
		if type(b) ~= "number" then error("cannot perform '+' on "..other.__name, 0) end
		return self.new(env, a - b)
	else
		return self.new(env, -a)
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

function Interpreter.String.new(parent, value)
	local self = Interpreter.Value(parent, tostring(value))
	self:define("+", Interpreter.String.add)
	self:define("!", Interpreter.String.not_)
	return setmetatable(self, Interpreter.String)
end

function Interpreter.String:add(env, other)
	local a, b = tostring(self.value), tostring(other.value)
	if type(b) ~= "string" then error("cannot perform '+' on "..other.__name, 0) end
	return self.new(env, a..b)
end

function Interpreter.String:not_(env)
	return Interpreter.Boolean(env, false)
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

function Interpreter.Boolean.new(parent, value)
	local self = Interpreter.Value(parent, not not value)
	self:define("!", Interpreter.Boolean.not_)
	return setmetatable(self, Interpreter.Boolean)
end

function Interpreter.Boolean.toBoolean(env, value)
	return Interpreter.Boolean(env, value.value)
end

function Interpreter.Boolean:not_(env)
	return Interpreter.Boolean(env, not self.value)
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

function Interpreter.Nil.new(parent)
	local self = Interpreter.Value(parent, nil)
	self:define("==", Interpreter.Nil.eq)
	self:define("!=", Interpreter.Nil.neq)
	self:define("!", Interpreter.Nil.not_)
	return setmetatable(self, Interpreter.Nil)
end

function Interpreter.Nil:eq(env, other)
	return Interpreter.Boolean(env, other.__name == "Nil")
end

function Interpreter.Nil:neq(env, other)
	return Interpreter.Boolean(env, other.__name ~= "Nil")
end

function Interpreter.Nil:not_(env)
	return Interpreter.Boolean(env, true)
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

function Interpreter.List.new(parent, elements)
	local self = Interpreter.Block(parent)
	self:define("+", Interpreter.List.add)
	self:define("...", Interpreter.List.spread)
	self:define("iterate", Interpreter.NativeFunction(parent, function(env)
		return self:iterate(env)
	end))
	elements = elements or {}
	for i = 1, #elements do
		self:define(i, elements[i])
	end
	self:define("length", Interpreter.Number(nil, #elements))
	return setmetatable(self, Interpreter.List)
end

function Interpreter.List:push(value)
	self:define(#self+1, value)
	self:assign("length", Interpreter.Number(nil, #self))
end

function Interpreter.List:add(env, other)
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	for i = 1, #other do
		table.insert(values, other:get(i))
	end
	self:assign("length", Interpreter.Number(nil, #self))
	return self.new(nil, values)
end

function Interpreter.List:spread()
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	return table.unpack(values)
end

function Interpreter.List:iterate(env)
	local i = 0
	return Interpreter.NativeFunction(env, function()
		i = i+1
		return self:get(i)
	end)
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
	if not success then print(err) return end
	
	-- Run
	local results = {pcall(self.program.evaluate, self.program, self.environment)}
	if results[1] then
		return table.unpack(results, 2)
	else
		print(tostring(results[2]).."\n\tin main chunk")
		error()
	end
end

function Interpreter.isCallable(fn)
	return fn and type(fn) == "table" and fn.call
end

return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})
