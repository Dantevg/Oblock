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

local function toNativeKey(key)
	if type(key) == "table" and key.value ~= nil then
		if key.__name == "String" then return '"'..key.value..'"'
		else return key.value end
	else return key end
end

local function fromNativeKey(key)
	if type(key) == "string" and key:sub(1,1) == '"' and key:sub(-1) == '"' then return stdlib.String(key:sub(2,-2))
	elseif type(key) == "string" then return stdlib.Symbol(key)
	elseif type(key) == "number" then return stdlib.Number(key)
	elseif type(key) == "boolean" then return stdlib.Boolean(key)
	else return key end
end

-- TODO: check how 'has' should work with parent envs and protos
function stdlib.Block:has(key)
	key = toNativeKey(key)
	if self.env[key] or key == "_Protos" then return true end
	
	for _, proto in ipairs(self.protos) do
		if proto:has(key) then return true end
	end
	return false
end

function stdlib.Block:get(key, isLocal)
	key = toNativeKey(key)
	
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
	if not isLocal and value and (value.__name == "Function" or value.__name == "NativeFunction") then
		value = value:bind(self)
	end
	return value or stdlib.Nil()
end

function stdlib.Block:set(key, value, isVariable)
	key = toNativeKey(key)
	if key == nil then Interpreter.error("Cannot set nil key") end
	if not self.mutable then
		Interpreter.error("Attempt to mutate immutable value "..tostring(self))
	end
	
	-- TODO: somehow allow setting / adding protos
	if key == "_Protos" then Interpreter.error("cannot set _Protos field yet") end
	
	if self.env[key] then
		if isVariable ~= nil then
			Interpreter.error("Redefinition of variable "..tostring(key))
		end
		if not self.env[key].var then
			Interpreter.error("Attempt to mutate const variable "..tostring(key))
		end
		self.env[key].value = value
	else
		self.env[key] = {
			value = value,
			var = isVariable == nil and true or isVariable
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
	for k, v in pairs(self.env) do newblock.env[k] = { value = v.value, var = v.var } end
	for k, v in pairs(other.env) do newblock.env[k] = { value = v.value, var = v.var } end
	return newblock
end

function stdlib.Block:keys()
	local keys = {}
	for k in pairs(self.env) do
		local key = fromNativeKey(k)
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
		if value ~= nil then -- TODO: prevent infinite loops
			strings[i] = tostring(key).." = "..tostring(value:get("toString"):call())
		else
			strings[i] = tostring(key)
		end
	end
	
	if #strings > 0 then
		return "{\n  "..table.concat(strings, "\n"):gsub("\n", "\n  ").."\n}"
	else
		return "{}"
	end
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

function stdlib.Function:iterate()
	return self
end

function stdlib.Function:compose(other)
	return stdlib.NativeFunction(function(_, ...)
		return self:call(nil, other:call(nil, ...))
	end)
end

-- Check whether `tbl` contains no values or only `nil`s
local function isEmpty(tbl)
	for _, v in ipairs(tbl) do
		if v ~= nil and v.__name ~= "Nil" then return false end
	end
	return true
end

function stdlib.Function:map(fn)
	return stdlib.NativeFunction(function(_, ...)
		local values = {self:call(nil, ...)}
		if not isEmpty(values) then return fn:call(nil, table.unpack(values)) end
	end)
end

function stdlib.Function:filter(fn)
	return stdlib.NativeFunction(function(_, ...)
		local values = {self:call(nil, ...)}
		if not isEmpty(values) and fn:call(nil, table.unpack(values)).value ~= nil then
			return table.unpack(values)
		end
	end)
end

function stdlib.Function:curry(...)
	local args = {...}
	return stdlib.NativeFunction(function(_, ...)
		for _, arg in ipairs {...} do table.insert(args, arg) end
		return self:call(nil, table.unpack(args))
	end)
end

stdlib.Function["and"] = function(self, other)
	return stdlib.NativeFunction(function(_, ...)
		local l, r = self:call(nil, ...), other:call(nil, ...)
		return stdlib.Boolean((l ~= nil and l.value) and (r ~= nil and r.value))
	end)
end

stdlib.Function["or"] = function(self, other)
	return stdlib.NativeFunction(function(_, ...)
		local l, r = self:call(nil, ...), other:call(nil, ...)
		return stdlib.Boolean((l ~= nil and l.value) or (r ~= nil and r.value))
	end)
end

stdlib.Function["not"] = function(self)
	return stdlib.NativeFunction(function(_, ...)
		local value = self:call(nil, ...)
		return stdlib.Boolean(value == nil or not value.value)
	end)
end

function stdlib.Function:matches(...)
	local args = {...}
	if not self.parameters then return stdlib.Boolean(true) end
	if not self.parameters:match(nil, args) then return stdlib.Boolean(false) end
	return stdlib.Boolean(#args == 0)
end

function stdlib.Function:co()
	return stdlib.Coroutine(self)
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



stdlib.Coroutine = {}
stdlib.Coroutine.__index = stdlib.Coroutine
stdlib.Coroutine.__name = "Coroutine"

stdlib.Coroutine.proto = stdlib.Function.proto:clone()

stdlib.Coroutine.FLAG = setmetatable({}, { __tostring = function() return "(COROUTINE FLAG)" end })

function stdlib.Coroutine.new(fn)
	local self = stdlib.Block()
	self.protos = {stdlib.Coroutine.proto}
	self.co = coroutine.create(function(...) return fn:call(nil, ...) end)
	return setmetatable(self, stdlib.Coroutine)
end

function stdlib.Coroutine.current()
	local self = stdlib.Block()
	self.protos = {stdlib.Coroutine.proto}
	self.co = coroutine.running()
	return setmetatable(self, stdlib.Coroutine)
end

function stdlib.Coroutine:call(loc, ...)
	local args = {...}
	while true do
		if coroutine.status(self.co) == "dead" then return end
		-- print("", coroutine.running(), self.co)
		local values = {coroutine.resume(self.co, table.unpack(args))}
		local success = table.remove(values, 1)
		if not success then error(values[1]) end
		-- Need to use rawequal because otherwise Oblock == takes over and returns an Oblock Boolean
		if not rawequal(values[1], stdlib.Coroutine.FLAG) then
			-- Not a Coroutine yield
			return table.unpack(values)
		end
		if values[2] == self.co then
			-- Should yield self
			return table.unpack(values, 3)
		else
			-- Should yield coroutine up the stack
			args = {coroutine.yield(table.unpack(values))}
		end
	end
end

function stdlib.Coroutine:yield(...)
	return coroutine.yield(stdlib.Coroutine.FLAG, self.co or coroutine.running(), ...)
end

function stdlib.Coroutine:__tostring()
	return self.name and "<coroutine "..self.name..">" or "<coroutine>"
end

setmetatable(stdlib.Coroutine, {
	__call = function(_, ...) return stdlib.Coroutine.new(...) end,
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
		Interpreter.binOpError("++", self.__name, other.__name)
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
	if type(b) ~= "number" then Interpreter.binOpError("<", self.__name, other.__name) end
	return stdlib.Boolean(a < b)
end

function stdlib.Number:leq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("<=", self.__name, other.__name) end
	return stdlib.Boolean(a <= b)
end

function stdlib.Number:gt(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError(">", self.__name, other.__name) end
	return stdlib.Boolean(a > b)
end

function stdlib.Number:geq(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError(">=", self.__name, other.__name) end
	return stdlib.Boolean(a >= b)
end

function stdlib.Number:add(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("+", self.__name, other.__name) end
	return self.new(a + b)
end

function stdlib.Number:mul(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("*", self.__name, other.__name) end
	return self.new(a * b)
end

function stdlib.Number:div(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("/", self.__name, other.__name) end
	return self.new(a / b)
end

function stdlib.Number:idiv(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("//", self.__name, other.__name) end
	return self.new(a // b)
end

function stdlib.Number:mod(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("%", self.__name, other.__name) end
	return self.new(a % b)
end

function stdlib.Number:sub(other)
	local a = tonumber(self.value)
	if other then
		local b = tonumber(other.value)
		if type(b) ~= "number" then Interpreter.binOpError("-", self.__name, other.__name) end
		return self.new(a - b)
	else
		return self.new(-a)
	end
end

function stdlib.Number:range(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(b) ~= "number" then Interpreter.binOpError("..", self.__name, other.__name) end
	return stdlib.lazy.Range:call(nil, self, other)
end

function stdlib.Number:abs()
	return self.new(math.abs(tonumber(self.value)))
end

function stdlib.Number:clamp(range)
	local from, to = tonumber(range:get("from").value), tonumber(range:get("to").value)
	return self.new(math.max(from, math.min(tonumber(self.value), to)))
end

function stdlib.Number:lerp(range)
	local from, to = tonumber(range:get("from").value), tonumber(range:get("to").value)
	return self.new(tonumber(self.value) * (to - from) + from)
end

function stdlib.Number:normalize(range)
	local from, to = tonumber(range:get("from").value), tonumber(range:get("to").value)
	return self.new((tonumber(self.value) - from) / (to - from))
end

function stdlib.Number:map(from, to)
	return self:normalize(from):lerp(to)
end

function stdlib.Number:max(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(a) ~= "number" or type(b) ~= "number" then
		Interpreter.argError("max", self.__name, other.__name)
	end
	return stdlib.Number.new(math.max(a, b))
end

function stdlib.Number:min(other)
	local a, b = tonumber(self.value), tonumber(other.value)
	if type(a) ~= "number" or type(b) ~= "number" then
		Interpreter.argError("min", self.__name, other.__name)
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



stdlib.Symbol = {}
stdlib.Symbol.__index = stdlib.Symbol
stdlib.Symbol.__name = "Symbol"

stdlib.Symbol.proto = stdlib.Block()

function stdlib.Symbol.new(value)
	local self = stdlib.Value(value)
	self.protos = {stdlib.Symbol.proto}
	self.mutable = false
	return setmetatable(self, stdlib.Symbol)
end

function stdlib.Symbol:__tostring()
	if self.value:match("^%w+$") then
		return "."..self.value
	else
		return "<symbol '"..self.value.."'>"
	end
end

stdlib.Symbol.__eq = stdlib.Value.__eq

setmetatable(stdlib.Symbol, {
	__call = function(_, ...) return stdlib.Symbol.new(...) end,
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

function stdlib.List:set(index, value, isVariable)
	stdlib.Block.set(self, index, value, isVariable)
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
	-- FIXME: TODO: fix printing tracebacks. At the moment, error printing is
	-- handled by Interpreter.printError and the traceback Oblock-list contains Lua-strings!
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
defineProtoNativeFn("Function", "iterate")
defineProtoNativeFn("Function", "compose", "o")
defineProtoNativeFn("Function", "map")
defineProtoNativeFn("Function", "filter")
defineProtoNativeFn("Function", "curry")
defineProtoNativeFn("Function", "and")
defineProtoNativeFn("Function", "or")
defineProtoNativeFn("Function", "matches")
defineProtoNativeFn("Function", "co")

defineProtoNativeFn("Coroutine", "call", "()")
defineProtoNativeFn("Coroutine", "current")
defineProtoNativeFn("Coroutine", "yield")

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
defineProtoNativeFn("Number", "clamp")
defineProtoNativeFn("Number", "lerp")
defineProtoNativeFn("Number", "normalize")
defineProtoNativeFn("Number", "map")
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
	local items = table.pack(...)
	for i = 1, items.n do
		items[i] = items[i]:get("toString"):call()
	end
	print(table.unpack(items))
end

stdlib.trace = function(_, ...)
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

stdlib.case = function(_, functions)
	return stdlib.NativeFunction(function(_, ...)
		for _, fn in ipairs {functions:spread()} do
			if fn:matches(...).value then return fn:call(nil, ...) end
		end
	end)
end

stdlib.match = function(_, ...)
	local args = {...}
	return stdlib.NativeFunction(function(_, functions)
		return stdlib.case(nil, functions):call(nil, table.unpack(args))
	end)
end

function stdlib.initEnv(env)
	env:setHere("clock", stdlib.NativeFunction(stdlib.clock))
	env:setHere("print", stdlib.NativeFunction(stdlib.print))
	env:setHere("trace", stdlib.NativeFunction(stdlib.trace))
	env:setHere("type", stdlib.NativeFunction(stdlib.type))
	env:setHere("id", stdlib.NativeFunction(stdlib.id))
	env:setHere("import", stdlib.NativeFunction(stdlib.import))
	env:setHere("clone", stdlib.NativeFunction(stdlib.clone))
	env:setHere("match", stdlib.NativeFunction(stdlib.match))
	env:setHere("case", stdlib.NativeFunction(stdlib.case))
	
	env:setHere("Block", stdlib.Block.proto)
	env:setHere("Function", stdlib.Function.proto)
	env:setHere("Coroutine", stdlib.Coroutine.proto)
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
