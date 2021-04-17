local AST = {}

AST.Expr = {}

AST.Expr.Unary = {}
AST.Expr.Unary.__index = AST.Expr.Unary

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

function AST.Expr.Group.new(expr)
	local self = {}
	self.expr = expr
	return setmetatable(self, AST.Expr.Group)
end

function AST.Expr.Group:evaluate(env)
	return self.expr:evaluate(env)
end

function AST.Expr.Group:__tostring()
	return string.format("(%s)", self.expr)
end

setmetatable(AST.Expr.Group, {
	__call = function(_, ...) return AST.Expr.Group.new(...) end,
})



AST.Expr.Variable = {}
AST.Expr.Variable.__index = AST.Expr.Variable

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

function AST.Expr.Block.new(statements)
	local self = {}
	self.statements = statements
	self.environment = {}
	return setmetatable(self, AST.Expr.Block)
end

function AST.Expr.Block:evaluate(env)
	self.parent = env
	for _, statement in ipairs(self.statements) do
		statement:evaluate(self)
	end
	return self
end

function AST.Expr.Block:set(name, value)
	self.environment[name] = value
end

function AST.Expr.Block:get(name)
	if self.environment[name] then
		return self.environment[name]
	elseif self.parent then
		return self.parent:get(name)
	else
		return AST.Expr.Literal.Nil()
	end
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



AST.Expr.Assignment = {}
AST.Expr.Assignment.__index = AST.Expr.Assignment

function AST.Expr.Assignment.new(name, expr)
	local self = {}
	self.name = name
	self.expr = expr
	return setmetatable(self, AST.Expr.Assignment)
end

function AST.Expr.Assignment:evaluate(env)
	env:set(self.name.lexeme, self.expr:evaluate(env))
end

function AST.Expr.Assignment:__tostring()
	return self.name.lexeme.." = "..tostring(self.expr)
end

setmetatable(AST.Expr.Assignment, {
	__call = function(_, ...) return AST.Expr.Assignment.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal

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



AST.Statement = {}

AST.Statement.Print = {}
AST.Statement.Print.__index = AST.Statement.Print

function AST.Statement.Print.new(expr)
	local self = {}
	self.expr = expr
	return setmetatable(self, AST.Statement.Print)
end

function AST.Statement.Print:evaluate(env)
	print(self.expr:evaluate(env))
	return AST.Expr.Literal.Nil()
end

function AST.Statement.Print:__tostring()
	return string.format("print(%s)", self.expr)
end

setmetatable(AST.Statement.Print, {
	__call = function(_, ...) return AST.Statement.Print.new(...) end,
})

return AST
