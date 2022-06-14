local Interpreter = require "Interpreter"

local stdlib = {}

stdlib.Block = {}
stdlib.Block.__index = stdlib.Block
stdlib.Block.__name = "Block"

function stdlib.Block.new(parent)
	local self = {}
	self.environment = Interpreter.Environment(parent)
	self.environment:set("_Proto", stdlib.Block.proto, nil, 0)
	return setmetatable(self, stdlib.Block)
end

function stdlib.Block:has(key)
	local has = self.environment:has(key)
	if not has then
		local proto = self.environment:get("_Proto", 0)
		has = proto and proto:has(key)
	end
	return has
end

function stdlib.Block:get(key, level)
	local value = self.environment:get(key, level)
	if not value then
		local proto = self.environment:get("_Proto", 0)
		value = proto and proto:get(key)
	end
	if value and (value.__name == "Function" or value.__name == "NativeFunction") then
		value = value:bind(self)
	end
	return value or stdlib.Nil()
end

function stdlib.Block:set(key, value, modifiers, level)
	return self.environment:set(key, value, modifiers, level)
end

function stdlib.Block:eq(other)
	return stdlib.Boolean(nil, self == other)
end

function stdlib.Block:pipe(other)
	if not Interpreter.isCallable(other) then Interpreter.error("cannot pipe into "..other.__name) end
	return other:call {self}
end

function stdlib.Block:clone(other)
	other:set("_Proto", self, nil, 0)
	return other
end

function stdlib.Block:__tostring()
	local strings = {}
	
	for key in pairs(self.environment.env) do
		-- Hide "_Proto" key
		if key ~= "_Proto" then table.insert(strings, key) end
	end
	table.sort(strings)
	
	for i, key in ipairs(strings) do
		local value = self.environment.env[key].value
		strings[i] = tostring(key).." = "..tostring(value)
	end
	return "{"..table.concat(strings, "; ").."}"
end

function stdlib.Block:call(...)
	return self:get("()"):call(...)
end

stdlib.Block.proto = stdlib.Block.new()

setmetatable(stdlib.Block, {
	__call = function(_, ...) return stdlib.Block.new(...) end,
})



stdlib.NativeFunction = {}
stdlib.NativeFunction.__index = stdlib.NativeFunction
stdlib.NativeFunction.__name = "NativeFunction"

stdlib.NativeFunction.proto = stdlib.Block()

function stdlib.NativeFunction.new(parent, body, name)
	local self = stdlib.Block(parent)
	self.body = body
	self.name = name
	self:set("_Proto", stdlib.NativeFunction.proto, nil, 0)
	return setmetatable(self, stdlib.NativeFunction)
end

function stdlib.NativeFunction:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, stdlib.NativeFunction)
end

function stdlib.NativeFunction:call(args)
	table.insert(args, 1, self.this)
	return self.body(table.unpack(args))
end

function stdlib.NativeFunction:__tostring()
	return self.name and "<native function: "..self.name..">" or "<native function>"
end

setmetatable(stdlib.NativeFunction, {
	__call = function(_, ...) return stdlib.NativeFunction.new(...) end,
	__index = stdlib.Block,
})



stdlib.Function = {}
stdlib.Function.__index = stdlib.Function
stdlib.Function.__name = "Function"

stdlib.Function.proto = stdlib.Block()

function stdlib.Function.new(parent, body, name)
	local self = stdlib.Block(parent)
	self.body = body
	self.name = name
	self:set("_Proto", stdlib.Function.proto, nil, 0)
	return setmetatable(self, stdlib.Function)
end

function stdlib.Function:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, stdlib.Function)
end

function stdlib.Function:call(args)
	local environment = Interpreter.Environment(self.environment)
	if self.this then environment:set("this", self.this, nil, 0) end
	
	-- Add arguments to function body indexed by number
	for i, arg in ipairs(args or {}) do
		environment:set(i, arg, nil, 0)
	end
	
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

function stdlib.Function:__tostring()
	return self.name and "<function: "..self.name..">" or "<function>"
end

setmetatable(stdlib.Function, {
	__call = function(_, ...) return stdlib.Function.new(...) end,
	__index = stdlib.Block,
})



stdlib.Value = {}
stdlib.Value.__index = stdlib.Value
stdlib.Value.__name = "Value"

function stdlib.Value.new(parent, value)
	local self = stdlib.Block(parent)
	self.value = value
	return setmetatable(self, stdlib.Value)
end

function stdlib.Value:__eq(other)
	return self.value == other.value
end

function stdlib.Value:__tostring()
	return tostring(self.value)
end

setmetatable(stdlib.Value, {
	__call = function(_, ...) return stdlib.Value.new(...) end,
	__index = stdlib.Block,
})



stdlib.Number = {}
stdlib.Number.__index = stdlib.Number
stdlib.Number.__name = "Number"

stdlib.Number.proto = stdlib.Block()

function stdlib.Number.new(parent, value)
	local self = stdlib.Value(parent, tonumber(value))
	self:set("_Proto", stdlib.Number.proto, nil, 0)
	return setmetatable(self, stdlib.Number)
end

function stdlib.Number:eq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return stdlib.Boolean(nil, a == b)
end

function stdlib.Number:neq(other)
	local val = self:get("=="):call {self, other}
	return val:get("!"):call {val}
end

function stdlib.Number:lt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return stdlib.Boolean(nil, a < b)
end

function stdlib.Number:gt(other)
	local val = self:get("<"):call {self, other}
	return val:get("!"):call {val}
end

function stdlib.Number:add(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(nil, a + b)
end

function stdlib.Number:mul(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '*' on "..other.__name) end
	return self.new(nil, a * b)
end

function stdlib.Number:sub(other)
	local a = tonumber(self.value)
	if other then
		local b = tonumber(other.value)
		if type(b) ~= "number" then Interpreter.error("cannot perform '-' on "..other.__name) end
		return self.new(nil, a - b)
	else
		return self.new(nil, -a)
	end
end

function stdlib.Number:not_(env)
	return stdlib.Boolean(env, false)
end

stdlib.Number.__eq = stdlib.Value.__eq
stdlib.Number.__tostring = stdlib.Value.__tostring

setmetatable(stdlib.Number, {
	__call = function(_, ...) return stdlib.Number.new(...) end,
	__index = stdlib.Value,
})



stdlib.String = {}
stdlib.String.__index = stdlib.String
stdlib.String.__name = "String"

stdlib.String.proto = stdlib.Block()

function stdlib.String.new(parent, value)
	local self = stdlib.Value(parent, tostring(value))
	self:set("_Proto", stdlib.String.proto, nil, 0)
	return setmetatable(self, stdlib.String)
end

function stdlib.String:add(other)
	local a, b = tostring(self.value), tostring(other.value)
	if type(b) ~= "string" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(nil, a..b)
end

function stdlib.String:not_()
	return stdlib.Boolean(nil, false)
end

stdlib.String.__eq = stdlib.Value.__eq
stdlib.String.__tostring = stdlib.Value.__tostring

setmetatable(stdlib.String, {
	__call = function(_, ...) return stdlib.String.new(...) end,
	__index = stdlib.Value,
})



stdlib.Boolean = {}
stdlib.Boolean.__index = stdlib.Boolean
stdlib.Boolean.__name = "Boolean"

stdlib.Boolean.proto = stdlib.Block()

function stdlib.Boolean.new(parent, value)
	local self = stdlib.Value(parent, not not value)
	self:set("_Proto", stdlib.Boolean.proto, nil, 0)
	return setmetatable(self, stdlib.Boolean)
end

function stdlib.Boolean.toBoolean(value)
	return stdlib.Boolean(nil, value.value)
end

function stdlib.Boolean:not_()
	return stdlib.Boolean(nil, not self.value)
end

stdlib.Boolean.__eq = stdlib.Value.__eq
stdlib.Boolean.__tostring = stdlib.Value.__tostring

setmetatable(stdlib.Boolean, {
	__call = function(_, ...) return stdlib.Boolean.new(...) end,
	__index = stdlib.Value,
})



stdlib.Nil = {}
stdlib.Nil.__index = stdlib.Nil
stdlib.Nil.__name = "Nil"

stdlib.Nil.proto = stdlib.Block()

function stdlib.Nil.new(parent, loc)
	local self = stdlib.Value(parent, nil)
	self.loc = loc
	self:set("_Proto", stdlib.Nil.proto, nil, 0)
	return setmetatable(self, stdlib.Nil)
end

function stdlib.Nil:eq(other)
	return stdlib.Boolean(nil, other.__name == "Nil")
end

function stdlib.Nil:neq(other)
	return stdlib.Boolean(nil, other.__name ~= "Nil")
end

function stdlib.Nil:not_()
	return stdlib.Boolean(nil, true)
end

stdlib.Nil.__eq = stdlib.Value.__eq

function stdlib.Nil:__tostring()
	return "nil"
end

setmetatable(stdlib.Nil, {
	__call = function(_, ...) return stdlib.Nil.new(...) end,
	__index = stdlib.Value,
})



stdlib.List = {}
stdlib.List.__index = stdlib.List
stdlib.List.__name = "List"

stdlib.List.proto = stdlib.Block()

function stdlib.List.new(parent, elements)
	local self = stdlib.Block(parent)
	elements = elements or {}
	for i = 1, #elements do
		self:set(i, elements[i], nil, 0)
	end
	self:set("length", stdlib.Number(nil, #elements), nil, 0)
	self:set("_Proto", stdlib.List.proto, nil, 0)
	return setmetatable(self, stdlib.List)
end

function stdlib.List:push(value)
	self:set(#self+1, value, nil, 0)
	self:set("length", stdlib.Number(nil, #self), nil, 0)
end

function stdlib.List:add(other)
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	for i = 1, #other do
		table.insert(values, other:get(i))
	end
	self:set("length", stdlib.Number(nil, #self), nil, 0)
	return self.new(nil, values)
end

function stdlib.List:spread()
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	return table.unpack(values)
end

function stdlib.List:iterate()
	local i = 0
	return stdlib.Function(self, function()
		i = i+1
		return self:get("this"):get(i), stdlib.Number(nil, i)
	end, "iterator")
end

function stdlib.List:__len()
	return #self.environment.env
end

function stdlib.List:__tostring()
	local strings = {}
	for i = 1, #self do
		table.insert(strings, tostring(self:get(i)))
	end
	return "["..table.concat(strings, ", ").."]"
end

setmetatable(stdlib.List, {
	__call = function(_, ...) return stdlib.List.new(...) end,
	__index = stdlib.Block,
})



stdlib.Error = {}
stdlib.Error.__index = stdlib.Error
stdlib.Error.__name = "Error"

stdlib.Error.proto = stdlib.Block()

function stdlib.Error.new(parent, message, loc, sourceLoc)
	local self = stdlib.Block(parent)
	self.loc, self.sourceLoc = loc, sourceLoc
	self:set("_Proto", stdlib.Error.proto, nil, 0)
	self:set("message", stdlib.String(nil, message), nil, 0)
	self:set("traceback", stdlib.List(), nil, 0)
	return setmetatable(self, stdlib.Error)
end

function stdlib.Error:__tostring()
	return tostring(self:get("message")).."\n"..tostring(self:get("traceback"))
end

setmetatable(stdlib.Error, {
	__call = function(_, ...) return stdlib.Error.new(...) end,
	__index = stdlib.Block,
})


-- Need to define this below here because NativeFunction needs to be defined

local function defineProtoNativeFn(base, name, key)
	stdlib[base].proto:set(
		key,
		stdlib.NativeFunction(nil, stdlib[base][name], name),
		nil, 0
	)
end

defineProtoNativeFn("Block", "eq", "==")
defineProtoNativeFn("Block", "pipe", "|>")
stdlib.Block.proto:set("clone",
	stdlib.NativeFunction(nil, stdlib.Block.clone, "clone"),
	nil, 0
)

stdlib.NativeFunction.proto:set("()", stdlib.NativeFunction, nil, 0)

stdlib.Function.proto:set("()", stdlib.Function, nil, 0)

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
stdlib.Boolean.proto:set("true", stdlib.Boolean(nil, true), nil, 0)
stdlib.Boolean.proto:set("false", stdlib.Boolean(nil, false), nil, 0)

defineProtoNativeFn("Nil", "eq", "==")
defineProtoNativeFn("Nil", "neq", "!=")
defineProtoNativeFn("Nil", "not_", "!")
stdlib.Nil.proto:set("nil", stdlib.Nil(), nil, 0)

defineProtoNativeFn("List", "add", "+")
defineProtoNativeFn("List", "spread", "...")
stdlib.List.proto:set("iterate",
	stdlib.Function(nil, stdlib.List.iterate, "iterate"),
	nil, 0
)



local fn = {}

fn.clock = function() return stdlib.Number(nil, os.clock()) end
fn.print = function(_, ...)
	-- Pass-through variables
	print(...)
	return ...
end

fn.type = function(_, x)
	if not x then return "Nil" end
	return stdlib.String(nil, x.__name)
end

-- To turn multiple values into one, like Lua does with `()`
fn.id = function(_, x) return x end

function stdlib.initEnv(env)
	for name, f in pairs(fn) do
		env:set(name, stdlib.NativeFunction(env, f), nil, 0)
	end
	env:set("Block", stdlib.Block.proto, nil, 0)
	env:set("Function", stdlib.Function.proto, nil, 0)
	env:set("Number", stdlib.Number.proto, nil, 0)
	env:set("String", stdlib.String.proto, nil, 0)
	env:set("Boolean", stdlib.Boolean.proto, nil, 0)
	env:set("Nil", stdlib.Nil.proto, nil, 0)
	env:set("List", stdlib.List.proto, nil, 0)
	
	env:set("nil", stdlib.Nil.proto:get("nil"), nil, 0)
	env:set("true", stdlib.Boolean.proto:get("true"), nil, 0)
	env:set("false", stdlib.Boolean.proto:get("false"), nil, 0)
end

return stdlib
