-- Inspired by http://craftinginterpreters.com/parsing-expressions.html
-- and https://craftinginterpreters.com/evaluating-expressions.html

local Parser = {}
Parser.__index = Parser

Parser.Expr = {}

Parser.Expr.Unary = {}
Parser.Expr.Unary.__index = Parser.Expr.Unary

function Parser.Expr.Unary.new(op, right)
	local self = {}
	self.op = op
	self.right = right
	return setmetatable(self, Parser.Expr.Unary)
end

function Parser.Expr.Unary:evaluate()
	-- TODO: generalise
	local right = self.right:evaluate()
	if self.op.type == "minus" then
		return -right
	elseif self.op.type == "exclamation" then
		return not right
	end
end

function Parser.Expr.Unary:__tostring()
	return string.format("(%s%s)", self.op.lexeme, self.right)
end

setmetatable(Parser.Expr.Unary, {
	__call = function(_, ...) return Parser.Expr.Unary.new(...) end,
})



Parser.Expr.Binary = {}
Parser.Expr.Binary.__index = Parser.Expr.Binary

function Parser.Expr.Binary.new(left, op, right)
	local self = {}
	self.left = left
	self.op = op
	self.right = right
	return setmetatable(self, Parser.Expr.Binary)
end

function Parser.Expr.Binary:evaluate()
	-- TODO: generalise
	local left = self.left:evaluate()
	local right = self.right:evaluate()
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

function Parser.Expr.Binary:__tostring()
	return string.format("(%s %s %s)", self.left, self.op.lexeme, self.right)
end

setmetatable(Parser.Expr.Binary, {
	__call = function(_, ...) return Parser.Expr.Binary.new(...) end,
})



Parser.Expr.Group = {}
Parser.Expr.Group.__index = Parser.Expr.Group

function Parser.Expr.Group.new(expr)
	local self = {}
	self.expr = expr
	return setmetatable(self, Parser.Expr.Group)
end

function Parser.Expr.Group:evaluate()
	return self.expr:evaluate()
end

function Parser.Expr.Group:__tostring()
	return string.format("(%s)", self.expr)
end

setmetatable(Parser.Expr.Group, {
	__call = function(_, ...) return Parser.Expr.Group.new(...) end,
})



Parser.Expr.Variable = {}
Parser.Expr.Variable.__index = Parser.Expr.Variable

function Parser.Expr.Variable.new(name)
	local self = {}
	self.name = name
	return setmetatable(self, Parser.Expr.Variable)
end

function Parser.Expr.Variable:evaluate()
	-- TODO: implement
end

function Parser.Expr.Variable:__tostring()
	return tostring(self.name.lexeme)
end

setmetatable(Parser.Expr.Variable, {
	__call = function(_, ...) return Parser.Expr.Variable.new(...) end,
})



Parser.Expr.Block = {}
Parser.Expr.Block.__index = Parser.Expr.Block

function Parser.Expr.Block.new(statements, parentEnvironment)
	local self = {}
	self.statements = statements
	self.environment = {}
	self.parentEnv = parentEnvironment
	return setmetatable(self, Parser.Expr.Block)
end

function Parser.Expr.Block:evaluate()
	for _, statement in ipairs(self.statements) do
		statement:evaluate()
	end
	return self
end

function Parser.Expr.Block:__tostring()
	local strings = {}
	for _, statement in ipairs(self.statements) do
		table.insert(strings, tostring(statement))
	end
	return "Block {"..table.concat(strings, "; ").."}"
end

setmetatable(Parser.Expr.Block, {
	__call = function(_, ...) return Parser.Expr.Block.new(...) end,
})



Parser.Expr.Assignment = {}
Parser.Expr.Assignment.__index = Parser.Expr.Assignment

function Parser.Expr.Assignment.new(name, expr)
	local self = {}
	self.name = name
	self.expr = expr
	return setmetatable(self, Parser.Expr.Assignment)
end

function Parser.Expr.Assignment:evaluate()
	-- TODO: implement
end

function Parser.Expr.Assignment:__tostring()
	return self.name.." = "..self.expr
end

setmetatable(Parser.Expr.Assignment, {
	__call = function(_, ...) return Parser.Expr.Assignment.new(...) end,
})



Parser.Expr.Literal = {}
Parser.Expr.Literal.__index = Parser.Expr.Literal

function Parser.Expr.Literal.new(value)
	local self = {}
	self.value = value
	return setmetatable(self, Parser.Expr.Literal)
end

function Parser.Expr.Literal:evaluate()
	return self.value
end

function Parser.Expr.Literal:__tostring()
	return tostring(self.value)
end

setmetatable(Parser.Expr.Literal, {
	__call = function(_, ...) return Parser.Expr.Literal.new(...) end,
})



Parser.Expr.Literal.Nil = {}
Parser.Expr.Literal.Nil.__index = Parser.Expr.Literal.Nil

function Parser.Expr.Literal.Nil.new()
	return setmetatable({}, Parser.Expr.Literal.Nil)
end

function Parser.Expr.Literal.Nil:evaluate()
	return nil
end

function Parser.Expr.Literal.Nil:__tostring()
	return "(nil)"
end

setmetatable(Parser.Expr.Literal.Nil, {
	__call = function(_, ...) return Parser.Expr.Literal.Nil.new(...) end,
	__index = Parser.Expr.Literal,
})



Parser.Statement = {}

Parser.Statement.Print = {}
Parser.Statement.Print.__index = Parser.Statement.Print

function Parser.Statement.Print.new(expr)
	local self = {}
	self.expr = expr
	return setmetatable(self, Parser.Statement.Print)
end

function Parser.Statement.Print:evaluate()
	print(self.expr:evaluate())
	return Parser.Expr.Literal.Nil()
end

function Parser.Statement.Print:__tostring()
	return string.format("print(%s)", self.expr)
end

setmetatable(Parser.Statement.Print, {
	__call = function(_, ...) return Parser.Statement.Print.new(...) end,
})



function Parser.new(tokens)
	local self = {}
	self.tokens = tokens
	self.current = 1
	return setmetatable(self, Parser)
end

function Parser.error(token, message)
	error("["..token.line.."] Error at '"..token.lexeme.."': "..(message or ""))
end

function Parser:peek()
	return self.tokens[self.current]
end

function Parser:previous()
	return self.tokens[self.current-1]
end

function Parser:advance()
	if self:peek().type ~= "EOF" then self.current = self.current+1 end
	return self:previous()
end

function Parser:match(types, whitespaceSensitive)
	local token = self:peek()
	while not whitespaceSensitive and token.type == "whitespace" do
		-- Skip whitespace
		self:advance()
		token = self:peek()
	end
	for _, t in ipairs(types) do
		if token.type == t then
			self:advance()
			return true
		end
	end
	return false
end

function Parser:consume(type, message)
	if self:peek().type == type then
		return self:advance()
	else
		Parser.error(self:peek(), message)
	end
end

function Parser:binary(tokens, next)
	local expr = next(self)
	
	while self:match(tokens) do
		local op = self:previous()
		local right = self:binary(tokens, next)
		expr = Parser.Expr.Binary(expr, op, right)
	end
	
	return expr
end

function Parser:parse()
	return self:expression()
end

function Parser:expression()
	return self:match {"opening curly bracket"}
		and self:block()
		or self:assignment()
end

function Parser:assignment()
	local expr = self:comparison()
	
	if self:match {"equal"} then
		local equal = self:previous()
		local value = self:assignment()
		if expr.__index == Parser.Expr.Variable then
			return Parser.Expr.Assignment(expr.name, value)
		else
			Parser.error(equal, "Attempt to assign to non-variable")
		end
	end
	
	return expr
end

function Parser:comparison()
	return self:binary({
		"equal equal", "exclamation equal", "less", "greater",
		"less equal", "greater equal"
	}, Parser.bitwise)
end

function Parser:bitwise()
	return self:binary({"less less", "greater greater"}, Parser.addsub)
end

function Parser:addsub()
	return self:binary({"plus", "minus"}, Parser.muldiv)
end

function Parser:muldiv()
	return self:binary({"star", "slash"}, Parser.unary)
end

function Parser:unary()
	if self:match {"minus", "exclamation"} then
		local op = self:previous()
		local right = self:unary()
		return Parser.Expr.Unary(op, right)
	else
		return self:primary()
	end
end

function Parser:primary()
	if self:match {"number", "string"} then
		return Parser.Expr.Literal(self:previous().literal)
	elseif self:match {"opening parenthesis"} then
		local expr = self:expression()
		self:consume("closing parenthesis", "Expected ')'")
		return Parser.Expr.Group(expr)
	elseif self:match {"identifier"} then -- variable
		return Parser.Expr.Variable(self:previous())
	end
end

function Parser:block()
	local statements = {}
	while not self:match {"closing curly bracket"} do
		table.insert(statements, self:statement())
	end
	return Parser.Expr.Block(statements)
end

function Parser:statement()
	if self:match {"print"} then
		return self:printStatement()
	else
		return self:expression()
	end
end

function Parser:printStatement()
	return Parser.Statement.Print(self:expression())
end

return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
