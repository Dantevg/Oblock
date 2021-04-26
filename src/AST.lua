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
	if type(fn) ~= "function" then error("no operator instance for '"..self.op.lexeme.."'") end
	return fn(right, env)
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
	if type(fn) ~= "function" then error("no operator instance for '"..self.op.lexeme.."'") end
	return fn(left, env, right)
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
		if not expr.environment then error("indexing non-block value "..expr.__name) end
		return expr.environment
	else
		return env
	end
end

function AST.Expr.Variable:evaluate(env)
	return self:getBase(env):get(self.expr:evaluate(env))
end

function AST.Expr.Variable:assign(env, value, mutate)
	self:getBase(env):set(self.expr:evaluate(env), value, mutate, self.modifiers)
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
				return err.value
			else
				error(err)
			end
		end
	end
	return block
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

function AST.Expr.Function:evaluate(parent)
	self.environment = Interpreter.Environment(parent)
	return self
end

function AST.Expr.Function:call(arguments)
	for i, parameter in ipairs(self.parameters.expressions) do
		local argument = arguments[i]
		if parameter.__name == "Variable" then
			self.environment:set(parameter.expr:evaluate(), argument)
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			local list = Interpreter.List(self.environment)
			for j = i, #arguments do
				list:push(arguments[j])
			end
			self.environment:set(parameter.right.expr:evaluate(), list)
			break
		else
			error("invalid parameter type")
		end
	end
	
	local values = {pcall(self.body.evaluate, self.body, self.environment)}
	if values[1] then
		return table.unpack(values, 2)
	else
		local err = values[2]
		if type(err) == "table" and err.__name == "Return" then
			return err.value
		else
			error(err)
		end
	end
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
	if not fn or fn.__name ~= "Function" then error("Attempt to call non-function") end
	local arguments = {self.arglist:evaluate(env)}
	return fn:call(arguments)
end

function AST.Expr.Call:__tostring()
	return string.format("%s %s", self.expression, self.arglist)
end

setmetatable(AST.Expr.Call, {
	__call = function(_, ...) return AST.Expr.Call.new(...) end,
})



AST.Expr.Assignment = {}
AST.Expr.Assignment.__index = AST.Expr.Assignment
AST.Expr.Assignment.__name = "Assignment"

function AST.Expr.Assignment.new(target, expr, mutate)
	local self = {}
	self.target = target
	self.expr = expr
	self.mutate = mutate
	return setmetatable(self, AST.Expr.Assignment)
end

function AST.Expr.Assignment:evaluate(env)
	local value = self.expr:evaluate(env)
	self.target:assign(env, value, self.mutate)
	return value
end

function AST.Expr.Assignment:__tostring()
	return tostring(self.target)..(self.mutate and " := " or " = ")..tostring(self.expr)
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
	self.value = self.expression and self.expression:evaluate(env)
	error(self)
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
	self.value = self.expression and self.expression:evaluate(env)
	error(self)
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

function AST.Stat.While:__tostring()
	return string.format("while %s: %s", self.condition, self.body)
end

setmetatable(AST.Stat.While, {
	__call = function(_, ...) return AST.Stat.While.new(...) end,
	__index = AST.Expr.Literal,
})



return AST
