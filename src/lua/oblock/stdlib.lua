local Interpreter = require "oblock.Interpreter"

local stdlib = {}

-- Lazy initialization of stdlib modules written in Oblock itself,
-- to avoid require-loops
stdlib.lazy = setmetatable({}, {
	__index = function(t, k)
		t[k] = stdlib.import(nil, k)
		return t[k]
	end
})



stdlib.Block = {}
stdlib.Block.__index = stdlib.Block
stdlib.Block.__name = "Block"

function stdlib.Block.new()
	local self = setmetatable({}, stdlib.Block)
	self.env = {}
	self.protos = {stdlib.Block.proto}
	self.mutable = true
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
	if type(key) == "table" and key.value ~= nil then key = key.value end
	
	-- TODO: either make protos list immutable (unnatural) or somehow propagate changes
	if key == "_Protos" then return stdlib.List(self.protos) end
	
	local value = self.env[key] and self.env[key].value
	
	if not value then
		for _, proto in ipairs(self.protos) do
			if proto:has(key) then
				value = proto:get(key)
				break
			end
		end
	end
	if value and (value.__name == "Function" or value.__name == "NativeFunction") then
		value = value:bind(self)
	end
	return value or stdlib.Nil()
end

function stdlib.Block:set(key, value, modifiers)
	if type(key) == "table" and key.value ~= nil then key = key.value end
	if key == nil then Interpreter.error("Cannot set nil key") end
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
	
	if type(key) == "string" and value and not value.name then
		value.name = key
	end
end

function stdlib.Block:eq(other)
	return stdlib.Boolean(self == other)
end

function stdlib.Block:neq(other)
	local val = self:get("=="):call(nil, other)
	return val:get("!"):call()
end

function stdlib.Block:pipe(other)
	if not Interpreter.isCallable(other) then Interpreter.error("cannot pipe into "..other.__name) end
	return other:call(nil, self)
end

function stdlib.Block:clone(other)
	other = other or stdlib.Block()
	-- Prevent double protos
	for _, v in ipairs(other.protos) do
		if v == self then return other end
	end
	table.insert(other.protos, 1, self)
	return other
end

function stdlib.Block:where(other)
	local newblock = stdlib.Block()
	-- TODO: take over modifiers or always var/const?
	for k, v in pairs(self.env) do newblock.env[k] = { value = v.value, modifiers = v.modifiers } end
	for k, v in pairs(other.env) do newblock.env[k] = { value = v.value, modifiers = v.modifiers } end
	return newblock
end

function stdlib.Block:keys()
	local keys = {}
	for k in pairs(self.env) do
		local key = type(k) == "string" and stdlib.String(k)
			or type(k) == "number" and stdlib.Number(k)
			or type(k) == "boolean" and stdlib.Boolean(k)
			or k
		if not (type(self.env[k].value) == "table" and self.env[k].value.__name == "Nil") then
			table.insert(keys, key)
		end
	end
	return stdlib.List(keys)
end

function stdlib.Block:allProtos()
	local function contains(tbl, value)
		for _, v in pairs(tbl) do
			if v == value then return true end
		end
		return false
	end
	
	local protos = {}
	for _, proto in ipairs(self.protos) do
		if not contains(protos, proto) then table.insert(protos, proto) end
		for _, p in ipairs {proto:allProtos():spread()} do
			if not contains(protos, p) then table.insert(protos, p) end
		end
	end
	return stdlib.List(protos)
end

function stdlib.Block:iterate()
	local keys = self:keys()
	local i = 0
	return stdlib.NativeFunction(function()
		i = i+1
		local k = keys:get(i)
		return self:get(k), k
	end, "iterator")
end

function stdlib.Block:is(other)
	-- Check prototype chain
	for _, proto in ipairs(self.protos) do
		if other == proto then return stdlib.Boolean(true) end
	end
	
	-- Check all own values
	for k, v in pairs(other.env) do
		if not self:has(k) then return stdlib.Boolean(false) end
	end
	
	-- Check all other protos
	for _, proto in pairs(other.protos) do
		if not self:is(proto).value then return stdlib.Boolean(false) end
	end
	
	return stdlib.Boolean(true)
end

function stdlib.Block:__tostring()
	local strings = {}
	
	for key in pairs(self.env) do
		table.insert(strings, key)
	end
	table.sort(strings, function(a, b) return tostring(a) < tostring(b) end)
	
	for i, key in ipairs(strings) do
		local value = self.env[key].value
		if value ~= nil then
			strings[i] = tostring(key).." = "..tostring(value:get("toString"):call())
		else
			strings[i] = tostring(key)
		end
	end
	return "{"..table.concat(strings, "; ").."}"
end

function stdlib.Block:call(...)
	return self:get("()"):call(...)
end

function stdlib.Block:not_()
	return stdlib.Boolean(false)
end

stdlib.Block.proto = stdlib.Block.new()

setmetatable(stdlib.Block, {
	__call = function(_, ...) return stdlib.Block.new(...) end,
})



stdlib.Function = {}
stdlib.Function.__index = stdlib.Function
stdlib.Function.__name = "Function"

stdlib.Function.proto = stdlib.Block()

function stdlib.Function.new(env, body, name, parameters, loc)
	local self = stdlib.Block()
	self.parentEnv = env
	self.body = body
	self.name = name
	self.parameters = parameters
	self.loc = loc
	self.protos = {stdlib.Function.proto}
	return setmetatable(self, stdlib.Function)
end

function stdlib.Function:bind(block)
	local new = {}
	for k, v in pairs(self) do new[k] = v end
	new.this = block
	return setmetatable(new, getmetatable(self))
end

function stdlib.Function:call(loc, ...)
	local args = {...}
	local environment = Interpreter.Environment(self.parentEnv, stdlib.Block())
	if self.this then environment:setHere("this", self.this) end
	
	-- Add arguments to function body indexed by number
	for i, arg in ipairs(args) do
		environment:setHere(i, arg)
	end
	
	local values = {pcall(Interpreter.context, loc, tostring(self),
		self.body, environment, table.unpack(args))}
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
		return self:call(nil, other:call(nil, ...))
	end)
end

function stdlib.Function:curry(...)
	local args = {...}
	return stdlib.NativeFunction(function(_, ...)
		for _, arg in ipairs {...} do table.insert(args, arg) end
		return self:call(nil, table.unpack(args))
	end)
end

function stdlib.Function:__tostring()
	return (self.name and "<function "..self.name or "<function")
		.." @ "..Interpreter.formatLoc(self.loc)..">"
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

function stdlib.NativeFunction:call(loc, ...)
	local values = {pcall(Interpreter.context, loc, tostring(self),
		self.body, self.this, ...)}
	if values[1] then
		return table.unpack(values, 2)
	else
		error(values[2], 0)
	end
end

function stdlib.NativeFunction:__tostring()
	return self.name and "<native function "..self.name..">" or "<native function>"
end

setmetatable(stdlib.NativeFunction, {
	__call = function(_, ...) return stdlib.NativeFunction.new(...) end,
	__index = stdlib.Function,
})


--[[
	Sequence requires of its implementors:
	- get(index: Number)
	- length: Number
]]
stdlib.Sequence = {}
stdlib.Sequence.__index = stdlib.Sequence
stdlib.Sequence.__name = "Sequence"

stdlib.Sequence.proto = stdlib.Block()

function stdlib.Sequence.new()
	return setmetatable(stdlib.Block(), stdlib.Sequence)
end

function stdlib.Sequence:stream()
	return stdlib.lazy.Stream:get("of"):call(nil, self)
end

function stdlib.Sequence:concat(other)
	if not other:is(stdlib.Sequence.proto).value then
		Interpreter.error("cannot perform Sequence.concat on "..other.__name)
	end
	
	local values = {}
	for i = 1, self:get("length").value do
		table.insert(values, self:get(i))
	end
	for i = 1, other:get("length").value do
		table.insert(values, other:get(i))
	end
	return self.new(values)
end

function stdlib.Sequence:append(value)
	self:set(self:get("length").value + 1, value)
end

function stdlib.Sequence:pop()
	local length = self:get("length").value
	local value = self:get(length)
	self.env[length] = nil
	self:set("length", stdlib.Number(length-1)) -- TODO: check correctness
	return value
end

function stdlib.Sequence:spread()
	local values = {}
	for i = 1, self:get("length").value do
		table.insert(values, self:get(i))
	end
	return table.unpack(values)
end

function stdlib.Sequence:length()
	return self:get "length"
end

function stdlib.Sequence:iterate()
	local i = 0
	return stdlib.NativeFunction(function()
		i = i+1
		return self:get(i), stdlib.Number(i)
	end, "iterator")
end

function stdlib.Sequence:sorted(fn)
	local values = {self:spread()}
	table.sort(values, function(a, b)
		return stdlib.Boolean.toBoolean(fn
				and fn:call(nil, a, b)
				or a:get("<"):call(nil, b)
			).value
	end)
	return self.new(values)
end

function stdlib.Sequence:sub(from, to)
	local values = {}
	for i = from and from.value or 1, to and to.value or self:get("length").value do
		table.insert(values, self:get(i))
	end
	return self.new(values)
end

function stdlib.Sequence:transpose()
	local values = self.new()
	for row_idx = 1, self:get("length").value do
		local row = self:get(row_idx)
		for col_idx = 1, row:get("length").value do
			if values:get(col_idx).__name == "Nil" then
				values:set(col_idx, self.new())
			end
			values:get(col_idx):set(row_idx, row:get(col_idx))
		end
	end
	return values
end

function stdlib.Sequence:reverse()
	local values = {}
	local length = self:get("length").value
	for i = 1, length do
		values[i] = self:get(length - i + 1)
	end
	return self.new(values)
end

function stdlib.Sequence:contains(value)
	for _, x in ipairs {self:spread()} do
		if x:get("=="):call(nil, value).value then return stdlib.Boolean(true) end
	end
	return stdlib.Boolean(false)
end

setmetatable(stdlib.Sequence, {
	__call = function(_, ...) return stdlib.Sequence.new(...) end,
	__index = stdlib.Block,
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
	self.mutable = false
	return setmetatable(self, stdlib.Number)
end

function stdlib.Number:parse(str)
	local num = tonumber(tostring(str))
	if not num then return stdlib.Nil() end
	return stdlib.Number.new(num)
end

function stdlib.Number:eq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	return stdlib.Boolean(a == b)
end

function stdlib.Number:lt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '<' on "..other.__name) end
	return stdlib.Boolean(a < b)
end

function stdlib.Number:leq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '<=' on "..other.__name) end
	return stdlib.Boolean(a <= b)
end

function stdlib.Number:gt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '>' on "..other.__name) end
	return stdlib.Boolean(a > b)
end

function stdlib.Number:geq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '>=' on "..other.__name) end
	return stdlib.Boolean(a >= b)
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

function stdlib.Number:div(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '/' on "..other.__name) end
	return self.new(a / b)
end

function stdlib.Number:idiv(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '//' on "..other.__name) end
	return self.new(a // b)
end

function stdlib.Number:mod(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '%' on "..other.__name) end
	return self.new(a % b)
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

function stdlib.Number:range(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.error("cannot perform '..' on "..other.__name) end
	return stdlib.lazy.Range:call(nil, self, other)
end

function stdlib.Number:abs()
	return self.new(math.abs(tonumber(self.value)))
end

function stdlib.Number:max(this, other)
	local a, b = tonumber(this.value), tonumber(other.value)
	if type(a) ~= "number" or type(b) ~= "number" then
		Interpreter.error("cannot perform 'max' on "..this.__name.." and "..other.__name)
	end
	return stdlib.Number.new(math.max(a, b))
end

function stdlib.Number:min(this, other)
	local a, b = tonumber(this.value), tonumber(other.value)
	if type(a) ~= "number" or type(b) ~= "number" then
		Interpreter.error("cannot perform 'min' on "..this.__name.." and "..other.__name)
	end
	return stdlib.Number.new(math.min(a, b))
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

stdlib.String.proto = stdlib.Sequence.proto:clone()

function stdlib.String.new(value)
	local self = stdlib.Value(tostring(value))
	self.protos = {stdlib.String.proto}
	self:set("length", stdlib.Number(#tostring(value)))
	self.mutable = false
	return setmetatable(self, stdlib.String)
end

function stdlib.String:get(index)
	if type(index) == "table" then index = index.value end
	if type(index) ~= "number" then return stdlib.Block.get(self, index) end
	return index <= #self.value and self.new(self.value:sub(index, index)) or stdlib.Nil()
end

-- Override from Sequence
function stdlib.String:concat(other)
	return self.new(self:toString().value..other:toString().value)
end

-- Override from Sequence
function stdlib.String:sub(from, to)
	return self.new(string.sub(self.value, from and from.value, to and to.value))
end

function stdlib.String:charCode()
	return stdlib.Number.new(string.byte(self.value))
end

stdlib.String.append = stdlib.Sequence.append
stdlib.String.spread = stdlib.Sequence.spread
stdlib.String.iterate = stdlib.Sequence.iterate

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
	self.mutable = false
	return setmetatable(self, stdlib.Boolean)
end

function stdlib.Boolean.toBoolean(value)
	return stdlib.Boolean(value ~= nil and value.__name ~= "Nil" and value.value ~= false)
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
	self.mutable = false
	return setmetatable(self, stdlib.Nil)
end

function stdlib.Nil:eq(other)
	return stdlib.Boolean(other.__name == "Nil")
end

function stdlib.Nil:not_()
	return stdlib.Boolean(true)
end

function stdlib.Nil:__eq(other)
	return self.proto == stdlib.Nil.proto and other.proto == stdlib.Nil.proto
end

stdlib.Nil.__tostring = stdlib.Value.__tostring

setmetatable(stdlib.Nil, {
	__call = function(_, ...) return stdlib.Nil.new(...) end,
	__index = stdlib.Value,
})



stdlib.List = {}
stdlib.List.__index = stdlib.List
stdlib.List.__name = "List"

stdlib.List.proto = stdlib.Sequence.proto:clone()

function stdlib.List.new(elements)
	local self = setmetatable(stdlib.Block(), stdlib.List)
	self:set("length", stdlib.Number(0))
	elements = elements or {}
	for i = 1, #elements do
		self:set(i, elements[i])
	end
	self.protos = {stdlib.List.proto}
	return self
end

function stdlib.List:set(index, value, modifiers)
	stdlib.Block.set(self, index, value, modifiers)
	if type(index) == "table" then index = index.value end
	if type(index) == "number" then
		self:set("length", stdlib.Number(math.max(self:get("length").value, index)))
	end
end

stdlib.List.append = stdlib.Sequence.append
stdlib.List.spread = stdlib.Sequence.spread
stdlib.List.iterate = stdlib.Sequence.iterate
stdlib.List.concat = stdlib.Sequence.concat

function stdlib.List:__len()
	return self:get("length").value
end

function stdlib.List:__tostring()
	local strings = {}
	for i = 1, #self do
		table.insert(strings, tostring(self:get(i):get("toString"):call()))
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
	self:set("message", stdlib.String(message))
	local traceback = stdlib.List()
	if loc then
		traceback:append("\tat "..Interpreter.formatLoc(loc))
	end
	self:set("traceback", traceback)
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
		if fn then return fn:call(nil, r) end
	end
end

stdlib.Block.toString = stdlib.String.new

defineProtoNativeFn("Block", "eq", "==")
defineProtoNativeFn("Block", "neq", "!=")
defineProtoNativeFn("Block", "pipe", "|>")
defineProtoNativeFn("Block", "clone")
defineProtoNativeFn("Block", "where")
defineProtoNativeFn("Block", "keys")
defineProtoNativeFn("Block", "allProtos", "protos")
defineProtoNativeFn("Block", "iterate")
defineProtoNativeFn("Block", "is")
defineProtoNativeFn("Block", "not_", "!")
defineProtoNativeFn("Block", "toString")

defineProtoNativeFn("Function", "call", "()")
defineProtoNativeFn("Function", "compose", "o")
defineProtoNativeFn("Function", "curry")

defineOperator("Sequence", "concat", "++")
defineOperator("Sequence", "length", "#")
defineProtoNativeFn("Sequence", "stream")
defineProtoNativeFn("Sequence", "append")
defineProtoNativeFn("Sequence", "pop")
defineProtoNativeFn("Sequence", "spread", "...")
defineProtoNativeFn("Sequence", "iterate")
defineProtoNativeFn("Sequence", "sorted")
defineProtoNativeFn("Sequence", "sub")
defineProtoNativeFn("Sequence", "transpose")
defineProtoNativeFn("Sequence", "reverse")
defineProtoNativeFn("Sequence", "contains")

defineProtoNativeFn("Number", "parse")
defineProtoNativeFn("Number", "abs")
defineProtoNativeFn("Number", "max")
defineProtoNativeFn("Number", "min")
defineOperator("Number", "eq", "==")
defineOperator("Number", "lt", "<")
defineOperator("Number", "leq", "<=")
defineOperator("Number", "gt", ">")
defineOperator("Number", "geq", ">=")
defineOperator("Number", "add", "+")
defineOperator("Number", "sub", "-")
defineOperator("Number", "mul", "*")
defineOperator("Number", "div", "/")
defineOperator("Number", "idiv", "//")
defineOperator("Number", "mod", "%")
defineProtoNativeFn("Number", "range", "..")
stdlib.Number.proto:set("INF", stdlib.Number(math.huge), {const = true})

defineOperator("String", "concat", "++")
defineProtoNativeFn("String", "sub")
defineProtoNativeFn("String", "charCode")

defineProtoNativeFn("Boolean", "not_", "!")
stdlib.Boolean.proto:set("true", stdlib.Boolean(true))
stdlib.Boolean.proto:set("false", stdlib.Boolean(false))

defineProtoNativeFn("Nil", "eq", "==")
defineProtoNativeFn("Nil", "not_", "!")
stdlib.Nil.proto:set("nil", stdlib.Nil())



stdlib.clock = function() return stdlib.Number(os.clock()) end
stdlib.print = function(_, ...)
	-- Pass-through variables
	local items = table.pack(...)
	for i = 1, items.n do
		items[i] = items[i]:get("toString"):call()
	end
	print(table.unpack(items))
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
	if rawget(stdlib.lazy, tostring(modname)) then return stdlib.lazy[tostring(modname)] end
	-- TODO: generalise to all paths, not just specifically the test directory
	package.path = package.path..";oblock/lib/?.lua;../test/?.lua"
	local langModule = require("oblock.run")(Interpreter(), "../test/"..tostring(modname)..".ob")
		or require("oblock.run")(Interpreter(), "oblock/lib/"..tostring(modname)..".ob")
	local hasLuaModule, luaModule = pcall(require, tostring(modname))
	local mod = hasLuaModule and luaModule(langModule or stdlib.Block()) or langModule or stdlib.Nil()
	stdlib.lazy[tostring(modname)] = mod
	return mod
end

stdlib.clone = function(_, ...)
	local prototypes = {...}
	return stdlib.NativeFunction(function(_, block)
		for _, proto in ipairs(prototypes) do
			for _, p in ipairs(block.protos) do
				if p == proto then goto continue end
			end
			table.insert(block.protos, 1, proto)
			::continue::
		end
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
	env:setHere("Sequence", stdlib.Sequence.proto)
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
