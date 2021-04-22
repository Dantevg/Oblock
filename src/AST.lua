-- Inspired by https://craftinginterpreters.com/evaluating-expressions.html

local AST = {}

AST.Environment = {}
AST.Environment.__index = AST.Environment

function AST.Environment.new(parent)
	local self = {}
	self.parent = parent
	self.environment = {}
	return setmetatable(self, AST.Environment)
end

function AST.Environment:set(name, value)
	if self.parent and self.parent:get(name).__name ~= "Nil" then
		self.parent:set(name, value)
	else
		self.environment[name] = value
	end
end

function AST.Environment:get(name)
	if self.environment[name] then
		return self.environment[name]
	elseif self.parent then
		return self.parent:get(name)
	else
		return AST.Expr.Literal.Nil()
	end
end

setmetatable(AST.Environment, {
	__call = function(_, ...) return AST.Environment.new(...) end,
})



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
	-- TODO: generalise
	local right = self.right:evaluate(env)
	if self.op.type == "minus" then
		return -right
	elseif self.op.type == "exclamation" then
		return not right
	end
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
	-- TODO: generalise
	local left = self.left:evaluate(env)
	local right = self.right:evaluate(env)
	if self.op.type == "equal equal" then
		return left == right
	elseif self.op.type == "exclamation equal" then
		return left ~= right
	elseif self.op.type == "less" then
		return left < right
	elseif self.op.type == "greater" then
		return left > right
	elseif self.op.type == "less equal" then
		return left <= right
	elseif self.op.type == "greater equal" then
		return left >= right
	elseif self.op.type == "plus" then
		return left + right
	elseif self.op.type == "minus" then
		return left - right
	elseif self.op.type == "star" then
		return left * right
	elseif self.op.type == "slash" then
		return left / right
	elseif self.op.type == "less less" then
		return left << right
	elseif self.op.type == "greater greater" then
		return left >> right
	end
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
-- b[c][d]  is  (b[c])[d]  is  Variable(Variable(Variable(nil, b), c), d)

function AST.Expr.Variable.new(base, expr)
	local self = {}
	self.base = base
	self.expr = expr
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:getBase(env)
	if self.base then
		local expr = self.base:evaluate(env)
		if not expr.environment then error("indexing nil value") end
		return expr.environment
	else
		return env
	end
end

function AST.Expr.Variable:evaluate(env)
	return self:getBase(env):get(self.expr:evaluate(env))
end

function AST.Expr.Variable:evaluateReference()
	return self.expr:evaluate()
end

function AST.Expr.Variable:__tostring()
	if self.base then
		if self.expr.__name == "Literal" and type(self.expr.literal) == "string" then
			return tostring(self.base).."."..self.expr.literal
		else
			return tostring(self.base).."["..tostring(self.expr).."]"
		end
	else
		return self.expr.__name == "Literal" and self.expr.literal or tostring(self.expr)
	end
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

function AST.Expr.Block:evaluate(parent)
	self.environment = AST.Environment(parent)
	for _, statement in ipairs(self.statements) do
		local success, err = pcall(statement.evaluate, statement, self.environment)
		if not success then
			if type(err) == "table" and err.__name == "Yield" then
				return err.value
			else
				error(err)
			end
		end
	end
	return self
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
	self.environment = AST.Environment(parent)
	return self
end

function AST.Expr.Function:call(arguments)
	for i, parameter in ipairs(self.parameters.expressions) do
		self.environment:set(parameter:evaluateReference(), arguments[i])
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

function AST.Expr.Assignment.new(target, expr)
	local self = {}
	self.target = target
	self.expr = expr
	return setmetatable(self, AST.Expr.Assignment)
end

function AST.Expr.Assignment:evaluate(env)
	local value = self.expr:evaluate(env)
	self.target:getBase(env):set(self.target.expr:evaluate(env), value)
	return value
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

function AST.Expr.Literal:evaluate()
	return self.literal
end

function AST.Expr.Literal:__tostring()
	return self.lexeme
end

setmetatable(AST.Expr.Literal, {
	__call = function(_, ...) return AST.Expr.Literal.new(...) end,
})



AST.Expr.Literal.Nil = {}
AST.Expr.Literal.Nil.__index = AST.Expr.Literal.Nil
AST.Expr.Literal.Nil.__name = "Nil"

function AST.Expr.Literal.Nil.new()
	return setmetatable({}, AST.Expr.Literal.Nil)
end

function AST.Expr.Literal.Nil:evaluate()
	return nil
end

function AST.Expr.Literal.Nil:__tostring()
	return "nil"
end

setmetatable(AST.Expr.Literal.Nil, {
	__call = function(_, ...) return AST.Expr.Literal.Nil.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Expr.Literal.True = {}
AST.Expr.Literal.True.__index = AST.Expr.Literal.True
AST.Expr.Literal.True.__name = "True"

function AST.Expr.Literal.True.new()
	return setmetatable({}, AST.Expr.Literal.True)
end

function AST.Expr.Literal.True:evaluate()
	return true
end

function AST.Expr.Literal.True:__tostring()
	return "true"
end

setmetatable(AST.Expr.Literal.True, {
	__call = function(_, ...) return AST.Expr.Literal.True.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Expr.Literal.False = {}
AST.Expr.Literal.False.__index = AST.Expr.Literal.False
AST.Expr.Literal.False.__name = "False"

function AST.Expr.Literal.False.new()
	return setmetatable({}, AST.Expr.Literal.False)
end

function AST.Expr.Literal.False:evaluate()
	return false
end

function AST.Expr.Literal.False:__tostring()
	return "false"
end

setmetatable(AST.Expr.Literal.False, {
	__call = function(_, ...) return AST.Expr.Literal.False.new(...) end,
	__index = AST.Expr.Literal,
})



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
	local value = self.condition:evaluate(env)
	if value then -- TODO: is truthy
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
	while self.condition:evaluate(env) do -- TODO: is truthy
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
