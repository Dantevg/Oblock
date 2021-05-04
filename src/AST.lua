-- Inspired by https://craftinginterpreters.com/evaluating-expressions.html

local Interpreter = require "Interpreter"

local AST = {}



AST.Expr = {}

AST.Expr.Unary = {}
AST.Expr.Unary.__index = AST.Expr.Unary
AST.Expr.Unary.__name = "Unary"

function AST.Expr.Unary.new(op, right)
	local self = {}
	self.op = op
	self.right = right
	return setmetatable(self, AST.Expr.Unary)
end

function AST.Expr.Unary:evaluate(env)
	local right = self.right:evaluate(env)
	local fn = right:get(self.op.lexeme)
	if type(fn) ~= "function" then
		error(string.format("no operator instance '%s' on %s value '%s'",
			self.op.lexeme, right.__name, self.right), 0)
	end
	return fn(right, env)
end

function AST.Expr.Unary:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Unary:__tostring()
	return string.format("(%s%s)", self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Unary, {
	__call = function(_, ...) return AST.Expr.Unary.new(...) end,
})



AST.Expr.Binary = {}
AST.Expr.Binary.__index = AST.Expr.Binary
AST.Expr.Binary.__name = "Binary"

function AST.Expr.Binary.new(left, op, right)
	local self = {}
	self.left = left
	self.op = op
	self.right = right
	return setmetatable(self, AST.Expr.Binary)
end

function AST.Expr.Binary:evaluate(env)
	local left = self.left:evaluate(env)
	local right = self.right:evaluate(env)
	local fn = left:get(self.op.lexeme)
	if type(fn) ~= "function" then
		error(string.format("no operator instance '%s' on %s value '%s'",
			self.op.lexeme, left.__name, self.left), 0)
	end
	return fn(left, env, right)
end

function AST.Expr.Binary:resolve(scope)
	self.left:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Binary:__tostring()
	return string.format("(%s %s %s)", self.left, self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Binary, {
	__call = function(_, ...) return AST.Expr.Binary.new(...) end,
})



AST.Expr.Group = {}
AST.Expr.Group.__index = AST.Expr.Group
AST.Expr.Group.__name = "Group"

function AST.Expr.Group.new(expressions)
	local self = {}
	self.expressions = expressions
	return setmetatable(self, AST.Expr.Group)
end

function AST.Expr.Group:evaluate(env)
	local results = {}
	for _, expr in ipairs(self.expressions) do
		local values = {expr:evaluate(env)}
		for _, result in ipairs(values) do
			table.insert(results, result)
		end
	end
	return table.unpack(results)
end

function AST.Expr.Group:resolve(scope)
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
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

-- a  is  Variable(nil, a)
-- b.(c).(d)  is  (b.(c)).(d)  is  Variable(Variable(Variable(nil, b), c), d)

function AST.Expr.Variable.new(base, expr)
	local self = {}
	self.base = base
	self.expr = expr
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:getBase(env)
	if self.base then
		local expr = self.base:evaluate(env)
		if not expr.environment then error("indexing non-block value "..expr.__name, 0) end
		return expr.environment
	else
		return env
	end
end

function AST.Expr.Variable:evaluate(env)
	return self:getBase(env):get(self.expr:evaluate(env), self.level)
end

function AST.Expr.Variable:define(env, value, modifiers)
	self:getBase(env):define(self.expr:evaluate(env), value, modifiers)
end

function AST.Expr.Variable:assign(env, value)
	self:getBase(env):assign(self.expr:evaluate(env), value, self.level)
end

function AST.Expr.Variable:resolve(scope)
	if self.base then
		self.base:resolve(scope)
	else
		local level = 0
		while scope do
			if scope[self.expr.lexeme] ~= nil then self.level = level return end
			scope, level = scope.parent, level+1
		end
		if not self.level then error("unresolved variable "..self.expr.lexeme, 0) end
	end
end

function AST.Expr.Variable:__tostring()
	local base = self.base and tostring(self.base).."." or ""
	return self.expr.__name == "Literal" and base..self.expr.literal or base..tostring(self.expr)
end

setmetatable(AST.Expr.Variable, {
	__call = function(_, ...) return AST.Expr.Variable.new(...) end,
})



AST.Expr.Block = {}
AST.Expr.Block.__index = AST.Expr.Block
AST.Expr.Block.__name = "Block"

function AST.Expr.Block.new(statements)
	local self = {}
	self.statements = statements
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

function AST.Expr.List.new(expressions)
	local self = {}
	self.expressions = expressions
	return setmetatable(self, AST.Expr.List)
end

function AST.Expr.List:evaluate(parent)
	local list = Interpreter.List(parent)
	for _, expr in ipairs(self.expressions) do
		local results = {expr:evaluate(list.environment)}
		for _, result in ipairs(results) do
			list:push(result)
		end
	end
	return list
end

function AST.Expr.List:resolve(scope)
	local childScope = {parent = scope}
	for i = 1, #self.expressions do
		self.expressions[i]:resolve(childScope)
	end
end

function AST.Expr.List:__tostring()
	local strings = {}
	for _, value in ipairs(self.environment.environment) do
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

function AST.Expr.Function.new(parameters, body)
	local self = {}
	self.parameters = parameters
	self.body = body
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
			env:define(parameter.expr:evaluate(), argument)
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			local list = Interpreter.List(env)
			for j = i, #arguments do
				list:push(arguments[j])
			end
			env:define(parameter.right.expr:evaluate(), list)
			break
		else
			error("invalid parameter type", 0)
		end
	end
	
	return self.body:evaluate(env)
end

function AST.Expr.Function:resolve(scope)
	local childScope = {parent = {parent = scope}}
	for _, parameter in ipairs(self.parameters.expressions) do
		if parameter.__name == "Variable" then
			childScope[parameter.expr.lexeme] = true
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			childScope[parameter.right.expr.lexeme] = true
			break
		else
			error("invalid parameter type", 0)
		end
	end
	self.body:resolve(childScope)
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

function AST.Expr.Call.new(expression, arglist)
	local self = {}
	self.expression = expression
	self.arglist = arglist
	return setmetatable(self, AST.Expr.Call)
end

function AST.Expr.Call:evaluate(env)
	local fn = self.expression:evaluate(env)
	if not fn or not fn.call then error("Attempt to call non-function", 0) end
	local arguments = {self.arglist:evaluate(env)}
	return fn:call(arguments)
end

function AST.Expr.Call:resolve(scope)
	self.expression:resolve(scope)
	self.arglist:resolve(scope)
end

function AST.Expr.Call:__tostring()
	return string.format("%s %s", self.expression, self.arglist)
end

setmetatable(AST.Expr.Call, {
	__call = function(_, ...) return AST.Expr.Call.new(...) end,
})



AST.Expr.Definition = {}
AST.Expr.Definition.__index = AST.Expr.Definition
AST.Expr.Definition.__name = "Definition"

function AST.Expr.Definition.new(target, expr, modifiers)
	local self = {}
	self.target = target
	self.expr = expr
	self.modifiers = modifiers
	return setmetatable(self, AST.Expr.Definition)
end

function AST.Expr.Definition:evaluate(env)
	local value = self.expr and self.expr:evaluate(env) or AST.Expr.Literal.Nil()
	self.target:define(env, value, self.modifiers)
	return value
end

function AST.Expr.Definition:resolve(scope)
	if scope[self.target.expr.lexeme] ~= nil then
		error("redefinition of "..self.target.expr.lexeme, 0)
	end
	if self.expr then
		self.expr:resolve(scope)
		scope[self.target.expr.lexeme] = true
	else
		scope[self.target.expr.lexeme] = false -- not defined yet
	end
	self.target:resolve(scope)
end

function AST.Expr.Definition:__tostring()
	return "var "..tostring(self.target).." = "..tostring(self.expr)
end

setmetatable(AST.Expr.Definition, {
	__call = function(_, ...) return AST.Expr.Definition.new(...) end,
})



AST.Expr.Assignment = {}
AST.Expr.Assignment.__index = AST.Expr.Assignment
AST.Expr.Assignment.__name = "Assignment"

function AST.Expr.Assignment.new(target, expr)
	local self = {}
	self.target = target
	self.expr = expr
	return setmetatable(self, AST.Expr.Assignment)
end

function AST.Expr.Assignment:evaluate(env)
	local value = self.expr:evaluate(env)
	self.target:assign(env, value)
	return value
end

function AST.Expr.Assignment:resolve(scope)
	self.expr:resolve(scope)
	self.target:resolve(scope)
end

function AST.Expr.Assignment:__tostring()
	return tostring(self.target).." = "..tostring(self.expr)
end

setmetatable(AST.Expr.Assignment, {
	__call = function(_, ...) return AST.Expr.Assignment.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal
AST.Expr.Literal.__name = "Literal"

function AST.Expr.Literal.new(literal, lexeme)
	local self = {}
	if lexeme then
		self.literal = literal
		self.lexeme = lexeme
	else
		self.literal = literal.literal
		self.lexeme = literal.lexeme
	end
	return setmetatable(self, AST.Expr.Literal)
end

function AST.Expr.Literal:evaluate(env)
	if type(self.literal) == "number" then
		return Interpreter.Number(env, self.literal)
	elseif type(self.literal) == "string" then
		return Interpreter.String(env, self.literal)
	elseif type(self.literal) == "nil" then
		return Interpreter.Nil(env)
	end
end

function AST.Expr.Literal.resolve() end

function AST.Expr.Literal:__tostring()
	return self.lexeme
end

setmetatable(AST.Expr.Literal, {
	__call = function(_, ...) return AST.Expr.Literal.new(...) end,
})

function AST.Expr.Literal.Nil()
	return AST.Expr.Literal(nil, "nil")
end



AST.Stat = {}

AST.Stat.Return = {}
AST.Stat.Return.__index = AST.Stat.Return
AST.Stat.Return.__name = "Return"

function AST.Stat.Return.new(expression)
	local self = {}
	self.expression = expression
	return setmetatable(self, AST.Stat.Return)
end

function AST.Stat.Return:evaluate(env)
	self.values = self.expression and {self.expression:evaluate(env)} or {}
	error(self, 0)
end

function AST.Stat.Return:resolve(scope)
	if self.expression then self.expression:resolve(scope) end
end

function AST.Stat.Return:__tostring()
	return "return "..tostring(self.expression)
end

setmetatable(AST.Stat.Return, {
	__call = function(_, ...) return AST.Stat.Return.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.Yield = {}
AST.Stat.Yield.__index = AST.Stat.Yield
AST.Stat.Yield.__name = "Yield"

function AST.Stat.Yield.new(expression)
	local self = {}
	self.expression = expression
	return setmetatable(self, AST.Stat.Yield)
end

function AST.Stat.Yield:evaluate(env)
	self.values = self.expression and {self.expression:evaluate(env)} or {}
	error(self, 0)
end

function AST.Stat.Yield:resolve(scope)
	if self.expression then self.expression:resolve(scope) end
end

function AST.Stat.Yield:__tostring()
	return "yield "..tostring(self.expression)
end

setmetatable(AST.Stat.Yield, {
	__call = function(_, ...) return AST.Stat.Yield.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.If = {}
AST.Stat.If.__index = AST.Stat.If
AST.Stat.If.__name = "If"

function AST.Stat.If.new(condition, ifTrue, ifFalse)
	local self = {}
	self.condition = condition
	self.ifTrue = ifTrue
	self.ifFalse = ifFalse
	return setmetatable(self, AST.Stat.If)
end

function AST.Stat.If:evaluate(env)
	if self.condition:evaluate(env):get("value") then
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

function AST.Stat.While.new(condition, body)
	local self = {}
	self.condition = condition
	self.body = body
	return setmetatable(self, AST.Stat.While)
end

function AST.Stat.While:evaluate(env)
	while self.condition:evaluate(env):get("value") do
		self.body:evaluate(env)
	end
end

function AST.Stat.While:resolve(scope)
	self.condition:resolve(scope)
	self.body:resolve(scope)
end

function AST.Stat.While:__tostring()
	return string.format("while %s: %s", self.condition, self.body)
end

setmetatable(AST.Stat.While, {
	__call = function(_, ...) return AST.Stat.While.new(...) end,
	__index = AST.Expr.Literal,
})



return AST
