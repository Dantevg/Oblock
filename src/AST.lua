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
	if self.parent and self.parent:get(name) then
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
	if self.op.__name == "minus" then
		return -right
	elseif self.op.__name == "exclamation" then
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
	if self.op.__name == "equal equal" then
		return left == right
	elseif self.op.__name == "exclamation equal" then
		return left ~= right
	elseif self.op.__name == "less" then
		return left < right
	elseif self.op.__name == "greater" then
		return left > right
	elseif self.op.__name == "less equal" then
		return left <= right
	elseif self.op.__name == "greater equal" then
		return left >= right
	elseif self.op.__name == "plus" then
		return left + right
	elseif self.op.__name == "minus" then
		return left - right
	elseif self.op.__name == "star" then
		return left * right
	elseif self.op.__name == "slash" then
		return left / right
	elseif self.op.__name == "less less" then
		return left << right
	elseif self.op.__name == "greater greater" then
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



AST.Expr.Varlist = {}
AST.Expr.Varlist.__index = AST.Expr.Varlist
AST.Expr.Varlist.__name = "Varlist"

function AST.Expr.Varlist.new(variables)
	local self = {}
	self.variables = variables
	return setmetatable(self, AST.Expr.Varlist)
end

function AST.Expr.Varlist:evaluate(env)
	local values = {}
	for _, variable in ipairs(self.variables) do
		table.insert(values, variable:evaluate(env))
	end
	return values
end

function AST.Expr.Varlist:__tostring()
	local variables = {}
	for _, variable in ipairs(self.variables) do
		table.insert(variables, tostring(variable))
	end
	return "("..table.concat(self.variables, ", ")..")"
end

setmetatable(AST.Expr.Varlist, {
	__call = function(_, ...) return AST.Expr.Varlist.new(...) end,
})



AST.Expr.Variable = {}
AST.Expr.Variable.__index = AST.Expr.Variable
AST.Expr.Variable.__name = "Variable"

function AST.Expr.Variable.new(name)
	local self = {}
	self.name = name
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:evaluate(env)
	return env:get(self.name.lexeme)
end

function AST.Expr.Variable:__tostring()
	return tostring(self.name.lexeme)
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
	local environment = AST.Environment(parent)
	for _, statement in ipairs(self.statements) do
		statement:evaluate(environment)
	end
	return self
end

function AST.Expr.Block:__tostring()
	local strings = {}
	for _, statement in ipairs(self.statements) do
		table.insert(strings, tostring(statement))
	end
	return "Block {"..table.concat(strings, "; ").."}"
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
	for i, parameter in ipairs(self.parameters.variables) do
		self.environment:set(parameter.name.lexeme, arguments[i])
	end
	return self.body:evaluate(self.environment)
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
	if not fn or fn.__index ~= AST.Expr.Function then error("Attempt to call non-function") end
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

function AST.Expr.Assignment.new(name, expr)
	local self = {}
	self.name = name
	self.expr = expr
	return setmetatable(self, AST.Expr.Assignment)
end

function AST.Expr.Assignment:evaluate(env)
	local value = self.expr:evaluate(env)
	env:set(self.name.lexeme, value)
	return value
end

function AST.Expr.Assignment:__tostring()
	return self.name.lexeme.." = "..tostring(self.expr)
end

setmetatable(AST.Expr.Assignment, {
	__call = function(_, ...) return AST.Expr.Assignment.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal
AST.Expr.Literal.__name = "Literal"

function AST.Expr.Literal.new(value)
	local self = {}
	self.value = value
	return setmetatable(self, AST.Expr.Literal)
end

function AST.Expr.Literal:evaluate()
	return self.value.literal
end

function AST.Expr.Literal:__tostring()
	return self.value.lexeme
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
	return "(nil)"
end

setmetatable(AST.Expr.Literal.Nil, {
	__call = function(_, ...) return AST.Expr.Literal.Nil.new(...) end,
	__index = AST.Expr.Literal,
})

return AST
