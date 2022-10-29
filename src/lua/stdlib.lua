local Interpreter = require "Interpreter"

local stdlib = {}

stdlib.Block = {}
stdlib.Block.__index = stdlib.Block
stdlib.Block.__name = "Block"

function stdlib.Block.new()
	local self = setmetatable({}, stdlib.Block)
	self.env = {}
	self.protos = {stdlib.Block.proto}
	self.mutable = true
	
	-- TODO: remove _Proto key (replaced by _Protos)
	self:set("_Proto", stdlib.Block.proto)
	return self
end

-- TODO: check how 'has' should work with parent envs and protos
function stdlib.Block:has(key)
	if type(key) == "table" then key = key.value end
	if self.env[key] or key == "_Protos" then return true end
	
	for _, proto in ipairs(self.protos) do
		if proto:has(key) then return true end
	end
	return false
end

function stdlib.Block:get(key)
	if type(key) == "table" then key = key.value end
	
	-- TODO: either make protos list immutable (unnatural) or somehow propagate changes
	if key == "_Protos" then return stdlib.List(self.protos) end
	
	local value = self.env[key] and self.env[key].value
	
	if not value then
		for _, proto in ipairs(self.protos) do
			value = proto:get(key)
			if value ~= nil then break end
		end
	end
	if value and (value.__name == "Function" or value.__name == "NativeFunction") then
		value = value:bind(self)
	end
	return value or stdlib.Nil()
end

function stdlib.Block:set(key, value, modifiers)
	if type(key) == "table" then key = key.value end
	if not self.mutable then
		Interpreter.error("Attempt to mutate immutable value "..tostring(self))
	end
	
	-- TODO: somehow allow setting / adding protos
	if key == "_Protos" then Interpreter.error("cannot set _Protos field yet") end
	
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

function stdlib.Block:eq(other)
	return stdlib.Boolean(self == other)
end

function stdlib.Block:neq(other)
	local val = self:get("=="):call {other}
	return val:get("!"):call()
end

function stdlib.Block:pipe(other)
	if not Interpreter.isCallable(other) then Interpreter.error("cannot pipe into "..other.__name) end
	return other:call {self}
end

function stdlib.Block:clone(other)
	other = other or stdlib.Block()
	other.protos = {self}
	other:set("_Proto", self)
	return other
end

function stdlib.Block:keys()
	local keys = {}
	for k in pairs(self.env) do table.insert(keys, stdlib.String(k)) end
	return stdlib.List(keys)
end

function stdlib.Block:protos()
	local protos = {}
	local proto = self:get("_Proto")
	while proto do
		table.insert(protos, proto)
		proto = proto:get("_Proto")
	end
	return stdlib.List(protos)
end

function stdlib.Block:is(other)
	-- Check prototype chain
	local proto = self:get("_Proto")
	while proto and proto ~= other:get("_Proto") do
		proto = proto:get("_Proto")
		if proto == other:get("_Proto") then return stdlib.Boolean(true) end
	end
	
	for k, v in pairs(other.env) do
		if not self:has(k) then return stdlib.Boolean(false) end
	end
	return stdlib.Boolean(true)
end

function stdlib.Block:__tostring()
	local strings = {}
	
	for key in pairs(self.env) do
		-- Hide "_Proto" key
		if key ~= "_Proto" then table.insert(strings, key) end
	end
	table.sort(strings, function(a, b) return tostring(a) < tostring(b) end)
	
	for i, key in ipairs(strings) do
		local value = self.env[key].value
		if value ~= nil then
			strings[i] = tostring(key).." = "..tostring(value)
		else
			strings[i] = tostring(key)
		end
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



stdlib.Function = {}
stdlib.Function.__index = stdlib.Function
stdlib.Function.__name = "Function"

stdlib.Function.proto = stdlib.Block()

function stdlib.Function.new(env, body, name, parameters)
	local self = stdlib.Block()
	self.parentEnv = env
	self.body = body
	self.name = name
	self.parameters = parameters
	self.protos = {stdlib.Function.proto}
	self:set("_Proto", stdlib.Function.proto)
	return setmetatable(self, stdlib.Function)
end

function stdlib.Function:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, getmetatable(self))
end

function stdlib.Function:call(...)
	local args = {...}
	local environment = Interpreter.Environment(self.parentEnv, stdlib.Block())
	if self.this then environment:setHere("this", self.this) end
	
	-- Add arguments to function body indexed by number
	for i, arg in ipairs(args) do
		environment:setHere(i, arg)
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

function stdlib.Function:compose(other)
	return stdlib.NativeFunction(function(_, ...)
		return self:call {other:call {...}}
	end)
end

function stdlib.Function:curry(...)
	local args = {...}
	return stdlib.NativeFunction(function(_, ...)
		for _, arg in ipairs {...} do table.insert(args, arg) end
		return self:call(table.unpack(args))
	end)
end

function stdlib.Function:__tostring()
	return self.name and "<function: "..self.name..">" or "<function>"
end

setmetatable(stdlib.Function, {
	__call = function(_, ...) return stdlib.Function.new(...) end,
	__index = stdlib.Block,
})



stdlib.NativeFunction = {}
stdlib.NativeFunction.__index = stdlib.NativeFunction
stdlib.NativeFunction.__name = "NativeFunction"

stdlib.NativeFunction.proto = stdlib.Function.proto:clone()

function stdlib.NativeFunction.new(body, name, parameters)
	local self = stdlib.Function(nil, body, name, parameters)
	return setmetatable(self, stdlib.NativeFunction)
end

function stdlib.NativeFunction:call(...)
	return self.body(self.this, ...)
end

function stdlib.NativeFunction:__tostring()
	return self.name and "<native function: "..self.name..">" or "<native function>"
end

setmetatable(stdlib.NativeFunction, {
	__call = function(_, ...) return stdlib.NativeFunction.new(...) end,
	__index = stdlib.Function,
})



stdlib.Value = {}
stdlib.Value.__index = stdlib.Value
stdlib.Value.__name = "Value"

function stdlib.Value.new(value)
	local self = stdlib.Block()
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

function stdlib.Number.new(value)
	local self = stdlib.Value(tonumber(value))
	self.protos = {stdlib.Number.proto}
	self:set("_Proto", stdlib.Number.proto)
	self.mutable = false
	return setmetatable(self, stdlib.Number)
end

function stdlib.Number:eq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return stdlib.Boolean(a == b)
end

function stdlib.Number:lt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return stdlib.Boolean(a < b)
end

function stdlib.Number:gt(other)
	local val = self:get("<"):call {self, other}
	return val:get("!"):call {val}
end

function stdlib.Number:add(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(a + b)
end

function stdlib.Number:mul(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '*' on "..other.__name) end
	return self.new(a * b)
end

function stdlib.Number:sub(other)
	local a = tonumber(self.value)
	if other then
		local b = tonumber(other.value)
		if type(b) ~= "number" then Interpreter.error("cannot perform '-' on "..other.__name) end
		return self.new(a - b)
	else
		return self.new(-a)
	end
end

function stdlib.Number:not_()
	return stdlib.Boolean(false)
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

function stdlib.String.new(value)
	local self = stdlib.Value(tostring(value))
	self.protos = {stdlib.String.proto}
	self:set("_Proto", stdlib.String.proto)
	self.mutable = false
	return setmetatable(self, stdlib.String)
end

function stdlib.String:add(other)
	local a, b = tostring(self.value), tostring(other.value)
	if type(b) ~= "string" then Interpreter.error("cannot perform '+' on "..other.__name) end
	return self.new(a..b)
end

function stdlib.String:not_()
	return stdlib.Boolean(false)
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

function stdlib.Boolean.new(value)
	local self = stdlib.Value(not not value)
	self.protos = {stdlib.Boolean.proto}
	self:set("_Proto", stdlib.Boolean.proto)
	self.mutable = false
	return setmetatable(self, stdlib.Boolean)
end

function stdlib.Boolean.toBoolean(value)
	return stdlib.Boolean(value.value)
end

function stdlib.Boolean:not_()
	return stdlib.Boolean(not self.value)
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

function stdlib.Nil.new(loc)
	local self = stdlib.Value(nil)
	self.loc = loc
	self.protos = {stdlib.Nil.proto}
	self:set("_Proto", stdlib.Nil.proto)
	self.mutable = false
	return setmetatable(self, stdlib.Nil)
end

function stdlib.Nil:eq(other)
	return stdlib.Boolean(other.__name == "Nil")
end

function stdlib.Nil:not_()
	return stdlib.Boolean(true)
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

function stdlib.List.new(elements)
	local self = stdlib.Block()
	elements = elements or {}
	for i = 1, #elements do
		self:set(i, elements[i])
	end
	self:set("length", stdlib.Number(#elements))
	self.protos = {stdlib.List.proto}
	self:set("_Proto", stdlib.List.proto)
	return setmetatable(self, stdlib.List)
end

function stdlib.List:push(value)
	self:set(#self+1, value)
	self:set("length", stdlib.Number(#self))
end

function stdlib.List:add(other)
	local values = {}
	for i = 1, #self do
		table.insert(values, self:get(i))
	end
	for i = 1, #other do
		table.insert(values, other:get(i))
	end
	self:set("length", stdlib.Number(#self))
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
	return stdlib.NativeFunction(function()
		i = i+1
		return self:get(i), stdlib.Number(i)
	end, "iterator")
end

function stdlib.List:__len()
	return #self.env
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

function stdlib.Error.new(message, loc, sourceLoc)
	local self = stdlib.Block()
	self.loc, self.sourceLoc = loc, sourceLoc
	self.protos = {stdlib.Error.proto}
	self:set("_Proto", stdlib.Error.proto)
	self:set("message", stdlib.String(message))
	self:set("traceback", stdlib.List())
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
		key or name,
		stdlib.NativeFunction(stdlib[base][name], name)
	)
end

local function defineOperator(base, name, key)
	defineProtoNativeFn(base, name, key)
	stdlib[base]["__"..name] = function(l, r)
		local fn = l:get(key)
		if fn then return fn:call(r) end
	end
end

defineProtoNativeFn("Block", "eq", "==")
defineProtoNativeFn("Block", "neq", "!=")
defineProtoNativeFn("Block", "pipe", "|>")
defineProtoNativeFn("Block", "clone")
defineProtoNativeFn("Block", "keys")
defineProtoNativeFn("Block", "protos")
defineProtoNativeFn("Block", "is")

defineProtoNativeFn("Function", "call", "()")
defineProtoNativeFn("Function", "compose", "o")
defineProtoNativeFn("Function", "curry")

defineOperator("Number", "eq", "==")
defineOperator("Number", "lt", "<")
defineOperator("Number", "gt", ">")
defineOperator("Number", "add", "+")
defineOperator("Number", "sub", "-")
defineOperator("Number", "mul", "*")
defineProtoNativeFn("Number", "not_", "!")

defineOperator("String", "add", "+")
defineProtoNativeFn("String", "not_", "!")

defineProtoNativeFn("Boolean", "not_", "!")
stdlib.Boolean.proto:set("true", stdlib.Boolean(true))
stdlib.Boolean.proto:set("false", stdlib.Boolean(false))

defineProtoNativeFn("Nil", "eq", "==")
defineProtoNativeFn("Nil", "not_", "!")
stdlib.Nil.proto:set("nil", stdlib.Nil())

defineOperator("List", "add", "+")
defineProtoNativeFn("List", "spread", "...")
defineProtoNativeFn("List", "push")
defineProtoNativeFn("List", "iterate")



stdlib.clock = function() return stdlib.Number(os.clock()) end
stdlib.print = function(_, ...)
	-- Pass-through variables
	print(...)
	return ...
end

stdlib.type = function(_, x)
	if not x then return "Nil" end
	return stdlib.String(x.__name)
end

-- To turn multiple values into one, like Lua does with `()`
-- TODO: decide on whether no-value / nothing (not even nil) should be allowed
stdlib.id = function(_, x) return x or stdlib.Nil() end

stdlib.import = function(_, modname)
	package.path = package.path..";src/lua/lib/?.lua;src/test/?.lua"
	local langModule = require("lang")(Interpreter(), "src/test/"..tostring(modname)..".lang")
		or require("lang")(Interpreter(), "src/lua/lib/"..tostring(modname)..".lang")
	local hasLuaModule, luaModule = pcall(require, tostring(modname))
	return hasLuaModule and luaModule(langModule or stdlib.Block()) or langModule or stdlib.Nil()
end

stdlib.clone = function(_, ...)
	local prototypes = {...}
	return stdlib.NativeFunction(function(_, block)
		block.protos = prototypes
		return block
	end)
end

function stdlib.initEnv(env)
	env:setHere("clock", stdlib.NativeFunction(stdlib.clock))
	env:setHere("print", stdlib.NativeFunction(stdlib.print))
	env:setHere("type", stdlib.NativeFunction(stdlib.type))
	env:setHere("id", stdlib.NativeFunction(stdlib.id))
	env:setHere("import", stdlib.NativeFunction(stdlib.import))
	env:setHere("clone", stdlib.NativeFunction(stdlib.clone))
	
	env:setHere("Block", stdlib.Block.proto)
	env:setHere("Function", stdlib.Function.proto)
	env:setHere("Number", stdlib.Number.proto)
	env:setHere("String", stdlib.String.proto)
	env:setHere("Boolean", stdlib.Boolean.proto)
	env:setHere("Nil", stdlib.Nil.proto)
	env:setHere("List", stdlib.List.proto)
	
	env:setHere("nil", stdlib.Nil.proto:get("nil"))
	env:setHere("true", stdlib.Boolean.proto:get("true"))
	env:setHere("false", stdlib.Boolean.proto:get("false"))
end

return stdlib
