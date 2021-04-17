local Parser = {}
Parser.__index = Parser

Parser.Expr = {}

Parser.Expr.Unary = {}
Parser.Expr.Unary.__index = Parser.Expr.Unary

function Parser.Expr.Unary.new(op, right)
	local self = Parser.Expr()
	self.op = op
	self.right = right
	return setmetatable(self, Parser.Expr.Unary)
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
	local self = Parser.Expr()
	self.left = left
	self.op = op
	self.right = right
	return setmetatable(self, Parser.Expr.Binary)
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
	local self = Parser.Expr()
	self.expr = expr
	return setmetatable(self, Parser.Expr.Group)
end

function Parser.Expr.Group:__tostring()
	return string.format("(%s)", self.expr)
end

setmetatable(Parser.Expr.Group, {
	__call = function(_, ...) return Parser.Expr.Group.new(...) end,
})



Parser.Expr.Literal = {}
Parser.Expr.Literal.__index = Parser.Expr.Literal

function Parser.Expr.Literal.new(value)
	local self = Parser.Expr()
	self.value = value
	return setmetatable(self, Parser.Expr.Literal)
end

function Parser.Expr.Literal:__tostring()
	return tostring(self.value)
end

setmetatable(Parser.Expr.Literal, {
	__call = function(_, ...) return Parser.Expr.Literal.new(...) end,
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

function Parser:expression()
	return self:assignment()
end

function Parser:assignment()
	return self:comparison()
end

function Parser:comparison()
	return self:binary({
		"equal equal", "exclamation equal", "less", "greater",
		"less equal", "greater equal"
	}, Parser.bitwise)
end

function Parser:comparison()
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
	-- TODO: variables
	if self:match {"number", "string"} then
		return Parser.Expr.Literal(self:previous().literal)
	elseif self:match {"opening parenthesis"} then
		local expr = self:expression()
		self:consume("closing parenthesis", "Expected ')'")
		return Parser.Expr.Group(expr)
	end
end

return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
