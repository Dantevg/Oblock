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

function Interpreter.Environment:set(key, value, mutate, modifiers)
	if type(key) == "table" and key:get("value") then key = key:get("value") end
	if mutate then
		if self.env[key] then
			if self.env[key].modifiers.const then
				error("Attempt to mutate const variable")
			end
			self.env[key].value = value
		elseif self.parent and self.parent:get(key) then
			self.parent:set(key, value, mutate, modifiers)
		else
			error("attempt to mutate non-existent variable")
		end
	else
		self.env[key] = {
			value = value,
			modifiers = modifiers
		}
	end
end

function Interpreter.Environment:get(key)
	if type(key) == "table" and key:get("value") then key = key:get("value") end
	if self.env[key] then
		return self.env[key].value
	elseif self.parent then
		return self.parent:get(key)
	else
		return Interpreter.Nil()
	end
end

setmetatable(Interpreter.Environment, {
	__call = function(_, ...) return Interpreter.Environment.new(...) end,
})



Interpreter.Block = {}
Interpreter.Block.__index = Interpreter.Block

function Interpreter.Block.new(parent)
	local self = {}
	self.environment = Interpreter.Environment(parent)
	return setmetatable(self, Interpreter.Block)
end

function Interpreter.Block:get(key)
	return self.environment:get(key)
end

function Interpreter.Block:set(key, value, mutate, modifiers)
	return self.environment:set(key, value, mutate, modifiers)
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



Interpreter.Value = {}
Interpreter.Value.__index = Interpreter.Value

function Interpreter.Value.new(parent, value)
	local self = Interpreter.Block(parent)
	self:set("value", value, false, {const = true})
	return setmetatable(self, Interpreter.Value)
end

function Interpreter.Value:__eq(other)
	return self:get("value") == other:get("value")
end

function Interpreter.Value:__tostring()
	return tostring(self:get("value"))
end

setmetatable(Interpreter.Value, {
	__call = function(_, ...) return Interpreter.Value.new(...) end,
	__index = Interpreter.Block,
})



Interpreter.Number = {}
Interpreter.Number.__index = Interpreter.Number

function Interpreter.Number.new(parent, value)
	local self = Interpreter.Value(parent, tonumber(value))
	self:set("==", Interpreter.Number.add)
	self:set("<", Interpreter.Number.lt)
	self:set("+", Interpreter.Number.add)
	self:set("-", Interpreter.Number.sub)
	self:set("!", Interpreter.Number.not_)
	return setmetatable(self, Interpreter.Number)
end

function Interpreter.Number:eq(env, other)
	return self.new(env, tonumber(self:get("value")) == tonumber(other:get("value")))
end

function Interpreter.Number:lt(env, other)
	return Interpreter.Boolean(env, tonumber(self:get("value")) < tonumber(other:get("value")))
end

function Interpreter.Number:add(env, other)
	return self.new(env, tonumber(self:get("value")) + tonumber(other:get("value")))
end

function Interpreter.Number:sub(env, other)
	if other then
		return self.new(env, tonumber(self:get("value")) - tonumber(other:get("value")))
	else
		return self.new(env, -tonumber(self:get("value")))
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

function Interpreter.String.new(parent, value)
	local self = Interpreter.Value(parent, tostring(value))
	self:set("+", Interpreter.String.add)
	self:set("!", Interpreter.String.not_)
	return setmetatable(self, Interpreter.String)
end

function Interpreter.String:add(env, other)
	return self.new(env, tostring(self:get("value")) .. tostring(other:get("value")))
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

function Interpreter.Boolean.new(parent, value)
	local self = Interpreter.Value(parent, not not value)
	self:set("!", Interpreter.Boolean.not_)
	return setmetatable(self, Interpreter.Boolean)
end

function Interpreter.Boolean.toBoolean(env, value)
	return Interpreter.Boolean(env, value:get("value"))
end

function Interpreter.Boolean:not_(env)
	return Interpreter.Boolean(env, not self:get("value"))
end

Interpreter.Boolean.__eq = Interpreter.Value.__eq
Interpreter.Boolean.__tostring = Interpreter.Value.__tostring

setmetatable(Interpreter.Boolean, {
	__call = function(_, ...) return Interpreter.Boolean.new(...) end,
	__index = Interpreter.Value,
})



Interpreter.Nil = {}
Interpreter.Nil.__index = Interpreter.Nil

function Interpreter.Nil.new(parent)
	local self = Interpreter.Value(parent, nil)
	self:set("!", Interpreter.Nil.not_)
	return setmetatable(self, Interpreter.Nil)
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

function Interpreter.List.new(parent, elements)
	local self = Interpreter.Block(parent)
	self:set("+", Interpreter.List.add)
	self:set("...", Interpreter.List.spread)
	elements = elements or {}
	for i = 1, #elements do
		self:set(i, elements[i])
	end
	return setmetatable(self, Interpreter.List)
end

function Interpreter.List:push(value)
	self:set(#self+1, value)
end

function Interpreter.List:add(env, other)
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	for i = 1, #other do
		table.insert(values, other:get(i))
	end
	return self.new(nil, values)
end

function Interpreter.List:spread()
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	return table.unpack(values)
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
	return self.program:evaluate(self.environment)
end

return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})
