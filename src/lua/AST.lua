-- Inspired by https://craftinginterpreters.com/evaluating-expressions.html

local Interpreter = require "Interpreter"

local function evaluateAll(expressions, env)
	local values = {}
	for _, expr in ipairs(expressions) do
		for _, value in ipairs({expr:evaluate(env)}) do
			table.insert(values, value)
		end
	end
	return values
end

local function resolveAll(expressions, scope)
	for _, expr in ipairs(expressions) do expr:resolve(scope) end
end

local pretty, tc
local function debug(indent, name, properties, nodelists)
	if not pretty then
		local success
		success, pretty = pcall(require, "pretty")
		if not success then pretty = tostring end
	end
	if not tc then
		local success
		success, tc = pcall(require, "terminalcolours")
		if not success then tc = setmetatable({fg={},bg={},cursor={}},{__call=function()return""end}) end
	end
	
	indent = indent or ""
	local str = {}
	
	local proplist = {}
	for k, v in pairs(properties) do
		table.insert(proplist, tostring(k)..": "..pretty(v, true))
	end
	str[1] = indent..tc(tc.fg.red)..name..tc(tc.reset).." { "..table.concat(proplist, ", ").." }"
	
	for nodelistname, nodes in pairs(nodelists) do
		table.insert(str, indent.."  - "..nodelistname..":")
		for _, node in ipairs(nodes) do
			local value, isSingleLine = node:debug(indent.."    ")
			table.insert(str, value)
		end
		if #nodes == 1 then
			str[#str-1] = str[#str-1].." "..table.remove(str):match("^%s*(.+)$")
		elseif #nodes == 0 then
			table.remove(str)
		end
	end
	
	return table.concat(str, "\n"), #str == 1
end

local AST = {}



AST.Expr = {}

AST.Expr.Logical = {}
AST.Expr.Logical.__index = AST.Expr.Logical
AST.Expr.Logical.__name = "Logical"

function AST.Expr.Logical.new(left, op, right, loc)
	local self = {}
	self.left = left
	self.op = op
	self.right = right
	self.loc = loc
	return setmetatable(self, AST.Expr.Logical)
end

function AST.Expr.Logical:evaluate(env)
	local left = self.left:evaluate(env)
	if self.op.lexeme == "||" then
		return Interpreter.Boolean.toBoolean(left).value
			and left or self.right:evaluate(env)
	elseif self.op.lexeme == "&&" then
		return Interpreter.Boolean.toBoolean(left).value
			and self.right:evaluate(env) or left
	end
end

function AST.Expr.Logical:resolve(scope)
	self.left:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Logical:debug(indent)
	return debug(indent, self.__name, {op = self.op},
		{left = {self.left}, right = {self.right}})
end

function AST.Expr.Logical:__tostring()
	return string.format("(%s %s %s)", self.left, self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Logical, {
	__call = function(_, ...) return AST.Expr.Logical.new(...) end,
})



-- TODO: generalise list of expressions (lot of code duplication atm)
AST.Expr.Group = {}
AST.Expr.Group.__index = AST.Expr.Group
AST.Expr.Group.__name = "Group"

function AST.Expr.Group.new(expressions, loc)
	local self = {}
	self.expressions = expressions
	self.loc = loc
	return setmetatable(self, AST.Expr.Group)
end

function AST.Expr.Group:evaluate(env)
	return table.unpack(evaluateAll(self.expressions, env))
end

function AST.Expr.Group:resolve(scope)
	resolveAll(self.expressions, scope)
end

function AST.Expr.Group:debug(indent)
	return debug(indent, self.__name, {}, {expressions = self.expressions})
end

function AST.Expr.Group:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "("..table.concat(expressions, ", ")..")"
end

setmetatable(AST.Expr.Group, {
	__call = function(_, ...) return AST.Expr.Group.new(...) end,
})



AST.Expr.Variable = {}
AST.Expr.Variable.__index = AST.Expr.Variable
AST.Expr.Variable.__name = "Variable"

function AST.Expr.Variable.new(token, loc)
	local self = {}
	self.token = token
	self.loc = loc
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:evaluate(env)
	local value = env:get(self.token.lexeme, self.level)
	if value.__name == "Nil" and not value.loc then value.loc = self.loc end
	return value
end

function AST.Expr.Variable:set(env, value, modifiers, level)
	env:set(self.token.lexeme, value, modifiers, level or self.level)
end

function AST.Expr.Variable:resolve(scope)
	if self.level then Interpreter.error("resolving already-resolved variable", self.loc) end
	local level = 0
	while scope do
		if scope[self.token.lexeme] then self.level = level return end
		scope, level = scope.parent, level+1
	end
	if not self.level then Interpreter.error("unresolved variable "..self.token.lexeme, self.loc) end
end

function AST.Expr.Variable:debug(indent)
	return debug(indent, self.__name, self, {})
end

function AST.Expr.Variable:__tostring()
	return self.token.lexeme
end

setmetatable(AST.Expr.Variable, {
	__call = function(_, ...) return AST.Expr.Variable.new(...) end,
})



AST.Expr.Index = {}
AST.Expr.Index.__index = AST.Expr.Index
AST.Expr.Index.__name = "Index"

-- b.(c).(d)  is  (b.(c)).(d)  is  Index(Index(Variable(b), c), d)

function AST.Expr.Index.new(base, expr, loc)
	local self = {}
	self.base = base
	self.expr = expr
	self.loc = loc
	return setmetatable(self, AST.Expr.Index)
end

local function ref(value, env)
	return value.__name == "Variable" and value.token.lexeme or value:evaluate(env)
end

function AST.Expr.Index:evaluate(env)
	local value = (self.base and self.base:evaluate(env) or env):get(ref(self.expr, env), self.level)
	if value.__name == "Nil" and not value.loc then value.loc = self.loc end
	return value
end

function AST.Expr.Index:set(env, value, modifiers)
	(self.base and self.base:evaluate(env) or env):set(ref(self.expr, env), value, modifiers, self.level)
end

function AST.Expr.Index:resolve(scope)
	if self.level then Interpreter.error("resolving already-resolved variable", self.loc) end
	if self.base then self.base:resolve(scope) end
	if self.expr.__name ~= "Variable" then self.expr:resolve(scope) end
	self.level = 0
end

function AST.Expr.Index:debug(indent)
	return debug(indent, self.__name, {}, {base = {self.base}, {expr = {self.expr}}})
end

function AST.Expr.Index:__tostring()
	return tostring(self.base or "").."."..tostring(self.expr)
end

setmetatable(AST.Expr.Index, {
	__call = function(_, ...) return AST.Expr.Index.new(...) end,
})



AST.Expr.Block = {}
AST.Expr.Block.__index = AST.Expr.Block
AST.Expr.Block.__name = "Block"

function AST.Expr.Block.new(statements, loc)
	local self = {}
	self.statements = statements
	self.loc = loc
	return setmetatable(self, AST.Expr.Block)
end

function AST.Expr.Block:evaluate(env)
	local block = Interpreter.Block(env)
	for _, statement in ipairs(self.statements) do
		local success, err = pcall(statement.evaluate, statement, block.environment)
		if not success then
			if type(err) == "table" and err.__name == "Yield" then
				return table.unpack(err.values)
			else
				error(err, 0)
			end
		end
	end
	return block
end

function AST.Expr.Block:resolve(scope)
	local childScope = {parent = scope}
	for i = 1, #self.statements do
		self.statements[i]:resolve(childScope)
	end
end

function AST.Expr.Block:debug(indent)
	return debug(indent, self.__name, {}, {statements = self.statements})
end

function AST.Expr.Block:__tostring()
	local strings = {}
	for _, statement in ipairs(self.statements) do
		table.insert(strings, tostring(statement))
	end
	return "{"..table.concat(strings, "; ").."}"
end

setmetatable(AST.Expr.Block, {
	__call = function(_, ...) return AST.Expr.Block.new(...) end,
})



AST.Expr.List = {}
AST.Expr.List.__index = AST.Expr.List
AST.Expr.List.__name = "List"

function AST.Expr.List.new(expressions, loc)
	local self = {}
	self.expressions = expressions
	self.loc = loc
	return setmetatable(self, AST.Expr.List)
end

function AST.Expr.List:evaluate(parent)
	local list = Interpreter.List(parent)
	local values = evaluateAll(self.expressions, list.environment)
	for _, value in ipairs(values) do list:push(value) end
	return list
end

function AST.Expr.List:resolve(scope)
	resolveAll(self.expressions, {parent = scope})
end

function AST.Expr.List:debug(indent)
	return debug(indent, self.__name, {}, {expressions = self.expressions})
end

function AST.Expr.List:__tostring()
	local strings = {}
	for _, value in ipairs(self.expressions) do
		table.insert(strings, tostring(value))
	end
	return "["..table.concat(strings, ", ").."]"
end

setmetatable(AST.Expr.List, {
	__call = function(_, ...) return AST.Expr.List.new(...) end,
})



AST.Expr.Function = {}
AST.Expr.Function.__index = AST.Expr.Function
AST.Expr.Function.__name = "Function"

function AST.Expr.Function.new(parameters, body, loc)
	local self = {}
	self.parameters = parameters
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Expr.Function)
end

function AST.Expr.Function:evaluate(env)
	local fn = Interpreter.Function(env, function(environment, args)
		return self:call(environment, args)
	end)
	function fn.__tostring() return self:__tostring() end
	return fn
end

function AST.Expr.Function:call(env, arguments)
	for i, parameter in ipairs(self.parameters.expressions) do
		local argument = arguments[i]
		if parameter.__name == "Variable" then
			env:set(parameter.token.lexeme, argument or Interpreter.Nil(nil, self.loc))
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			local list = Interpreter.List(env)
			for j = i, #arguments do
				list:push(arguments[j])
			end
			env:set(parameter.right.token.lexeme, list)
			break
		else
			Interpreter.error("invalid parameter type", self.loc)
		end
	end
	
	return self.body:evaluate(env)
end

function AST.Expr.Function:resolve(scope)
	local childScope = {this = true, parent = {parent = scope}}
	for _, parameter in ipairs(self.parameters.expressions) do
		if parameter.__name == "Variable" then
			childScope[parameter.token.lexeme] = true
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			childScope[parameter.right.token.lexeme] = true
			break
		else
			Interpreter.error("invalid parameter type", self.loc)
		end
	end
	self.body:resolve(childScope)
end

function AST.Expr.Function:debug(indent)
	return debug(indent, self.__name, {},
		{parameters = self.parameters.expressions, body = {self.body}})
end

function AST.Expr.Function:__tostring()
	return string.format("%s => %s", self.parameters, self.body)
end

setmetatable(AST.Expr.Function, {
	__call = function(_, ...) return AST.Expr.Function.new(...) end,
})



AST.Expr.Call = {}
AST.Expr.Call.__index = AST.Expr.Call
AST.Expr.Call.__name = "Call"

function AST.Expr.Call.new(expression, arglist, loc)
	local self = {}
	self.expression = expression
	self.arglist = arglist
	self.loc = loc
	return setmetatable(self, AST.Expr.Call)
end

function AST.Expr.Call:evaluate(env)
	local fn = self.expression:evaluate(env)
	if not Interpreter.isCallable(fn) then
		Interpreter.error("Attempt to call non-callable type "
			..(fn and fn.__name or "Nil"), self.loc, fn.loc)
	end
	local arguments = {self.arglist:evaluate(env)}
	return fn:call(arguments)
end

function AST.Expr.Call:resolve(scope)
	self.expression:resolve(scope)
	self.arglist:resolve(scope)
end

function AST.Expr.Call:debug(indent)
	return debug(indent, self.__name, {},
		{expression = {self.expression}, args = {self.arglist}})
end

function AST.Expr.Call:__tostring()
	return string.format("%s %s", self.expression, self.arglist)
end

setmetatable(AST.Expr.Call, {
	__call = function(_, ...) return AST.Expr.Call.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal
AST.Expr.Literal.__name = "Literal"

function AST.Expr.Literal.new(literal, lexeme, loc)
	local self = {}
	if lexeme then
		self.literal = literal
		self.lexeme = lexeme
	else
		self.literal = literal.literal
		self.lexeme = literal.lexeme
	end
	self.loc = loc
	return setmetatable(self, AST.Expr.Literal)
end

function AST.Expr.Literal:evaluate(env)
	if type(self.literal) == "number" then
		return Interpreter.Number(env, self.literal)
	elseif type(self.literal) == "string" then
		return Interpreter.String(env, self.literal)
	elseif type(self.literal) == "nil" then
		return Interpreter.Nil(env, self.loc)
	end
end

function AST.Expr.Literal.resolve() end

function AST.Expr.Literal:debug(indent)
	return debug(indent, self.__name, self, {})
end

function AST.Expr.Literal:__tostring()
	return self.lexeme
end

setmetatable(AST.Expr.Literal, {
	__call = function(_, ...) return AST.Expr.Literal.new(...) end,
})



AST.Stat = {}

AST.Stat.Return = {}
AST.Stat.Return.__index = AST.Stat.Return
AST.Stat.Return.__name = "Return"

function AST.Stat.Return.new(expressions, loc)
	local self = {}
	self.expressions = expressions or {}
	self.loc = loc
	return setmetatable(self, AST.Stat.Return)
end

function AST.Stat.Return:evaluate(env)
	self.values = evaluateAll(self.expressions, env)
	error(self, 0)
end

function AST.Stat.Return:resolve(scope)
	resolveAll(self.expressions, scope)
end

function AST.Stat.Return:debug(indent)
	return debug(indent, self.__name, {}, {expressions = self.expressions})
end

function AST.Stat.Return:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "return "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Return, {
	__call = function(_, ...) return AST.Stat.Return.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.Yield = {}
AST.Stat.Yield.__index = AST.Stat.Yield
AST.Stat.Yield.__name = "Yield"

function AST.Stat.Yield.new(expressions, loc)
	local self = {}
	self.expressions = expressions or {}
	self.loc = loc
	return setmetatable(self, AST.Stat.Yield)
end

function AST.Stat.Yield:evaluate(env)
	self.values = evaluateAll(self.expressions, env)
	error(self, 0)
end

function AST.Stat.Yield:resolve(scope)
	resolveAll(self.expressions, scope)
end

function AST.Stat.Yield:debug(indent)
	return debug(indent, self.__name, {}, {expressions = self.expressions})
end

function AST.Stat.Yield:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "yield "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Yield, {
	__call = function(_, ...) return AST.Stat.Yield.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.If = {}
AST.Stat.If.__index = AST.Stat.If
AST.Stat.If.__name = "If"

function AST.Stat.If.new(condition, ifTrue, ifFalse, loc)
	local self = {}
	self.condition = condition
	self.ifTrue = ifTrue
	self.ifFalse = ifFalse
	self.loc = loc
	return setmetatable(self, AST.Stat.If)
end

function AST.Stat.If:evaluate(env)
	if self.condition:evaluate(env).value then
		self.ifTrue:evaluate(env)
	elseif self.ifFalse then
		self.ifFalse:evaluate(env)
	end
end

function AST.Stat.If:resolve(scope)
	self.condition:resolve(scope)
	self.ifTrue:resolve(scope)
	if self.ifFalse then self.ifFalse:resolve(scope) end
end

function AST.Stat.If:debug(indent)
	return debug(indent, self.__name, {},
		{condition = {self.condition}, ["then"] = {self.ifTrue}, ["else"] = {self.ifFalse}})
end

function AST.Stat.If:__tostring()
	if self.ifFalse then
		return string.format("if %s: %s else %s", self.condition, self.ifTrue, self.ifFalse)
	else
		return string.format("if %s: %s", self.condition, self.ifTrue)
	end
end

setmetatable(AST.Stat.If, {
	__call = function(_, ...) return AST.Stat.If.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.While = {}
AST.Stat.While.__index = AST.Stat.While
AST.Stat.While.__name = "While"

function AST.Stat.While.new(condition, body, loc)
	local self = {}
	self.condition = condition
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Stat.While)
end

function AST.Stat.While:evaluate(env)
	while self.condition:evaluate(env).value do
		self.body:evaluate(env)
	end
end

function AST.Stat.While:resolve(scope)
	self.condition:resolve(scope)
	self.body:resolve(scope)
end

function AST.Stat.While:debug(indent)
	return debug(indent, self.__name, {},
		{condition = {self.condition}, body = {self.body}})
end

function AST.Stat.While:__tostring()
	return string.format("while %s: %s", self.condition, self.body)
end

setmetatable(AST.Stat.While, {
	__call = function(_, ...) return AST.Stat.While.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.For = {}
AST.Stat.For.__index = AST.Stat.For
AST.Stat.For.__name = "For"

function AST.Stat.For.new(variable, expr, body, loc)
	local self = {}
	self.variable = variable
	self.expr = expr
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Stat.For)
end

function AST.Stat.For:evaluate(env)
	-- Get iterator from expr
	local container = self.expr:evaluate(env)
	local iteratorSource = container:get("iterate")
	if not Interpreter.isCallable(iteratorSource) then
		Interpreter.error(string.format("no callable instance 'iterate' on %s value '%s'",
			container.__name, self.expr), self.loc, container.loc)
	end
	local iterator = iteratorSource:call()
	if not Interpreter.isCallable(iterator) then
		Interpreter.error("'iterate' returns non-callable type "..iterator.__name,
			self.loc, iterator.loc)
	end
	
	-- Loop: set variable to iterator result, run body if result was non-nil
	local block = Interpreter.Block(env)
	local value = iterator:call()
	self.variable:set(block)
	while value and value.__name ~= "Nil" do
		self.variable:set(block, value)
		self.body:evaluate(block)
		value = iterator:call()
	end
end

function AST.Stat.For:resolve(scope)
	self.expr:resolve(scope)
	local childScope = {parent = scope}
	childScope[self.variable.token.lexeme] = true
	self.body:resolve(childScope)
end

function AST.Stat.For:debug(indent)
	return debug(indent, self.__name, {variable = self.variable},
		{expression = {self.expr}, body = {self.body}})
end

function AST.Stat.For:__tostring()
	return string.format("for %s in %s: %s", self.variable, self.expr, self.body)
end

setmetatable(AST.Stat.For, {
	__call = function(_, ...) return AST.Stat.For.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.Assignment = {}
AST.Stat.Assignment.__index = AST.Stat.Assignment
AST.Stat.Assignment.__name = "Assignment"

function AST.Stat.Assignment.new(targets, expressions, modifiers, predef, loc)
	local self = {}
	self.targets = targets
	self.expressions = expressions
	self.modifiers = modifiers
	self.predef = predef
	self.loc = loc
	return setmetatable(self, AST.Stat.Assignment)
end

function AST.Stat.Assignment:evaluate(env)
	local values = evaluateAll(self.expressions, env)
	
	for i, target in ipairs(self.targets) do
		local value = values[i] or Interpreter.Nil(nil, self.loc)
		local level = not self.modifiers.empty and 0 or nil
		if target.set then
			target:set(env, value, self.modifiers, level)
		else
			env:set(target:evaluate(env), value, self.modifiers, level)
		end
	end
end

function AST.Stat.Assignment:resolve(scope)
	if self.predef then
		for _, target in ipairs(self.targets) do
			scope[target.lexeme or target.token.lexeme] = true
		end
	end
	
	resolveAll(self.expressions, scope)
	
	for _, target in ipairs(self.targets) do
		local resolved
		if self.modifiers.empty then
			resolved = pcall(target.resolve, target, scope)
		end
		if not resolved then
			scope[target.lexeme or target.token.lexeme] = true
		end
	end
end

function AST.Stat.Assignment:debug(indent)
	return debug(indent, self.__name,
		{modifiers = self.modifiers, predef = self.predef},
		{targets = self.targets, expressions = self.expressions})
end

function AST.Stat.Assignment:__tostring()
	local targets, expressions = {}, {}
	for _, target in ipairs(self.targets) do
		table.insert(targets, tostring(target))
	end
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return table.concat(targets, ", ").." = "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Assignment, {
	__call = function(_, ...) return AST.Stat.Assignment.new(...) end,
})



return AST
