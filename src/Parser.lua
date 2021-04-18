-- Inspired by http://craftinginterpreters.com/parsing-expressions.html
-- and https://craftinginterpreters.com/evaluating-expressions.html

local AST = require "AST"

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
	local self = {}
	self.tokens = tokens
	self.current = 1
	return setmetatable(self, Parser)
end

function Parser.error(token, message)
	error("["..token.line.."] Error at '"..token.lexeme.."': "..(message or ""), 2)
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
		expr = AST.Expr.Binary(expr, op, right)
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
		if expr.__index == AST.Expr.Variable then
			return AST.Expr.Assignment(expr.name, value)
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
		return AST.Expr.Unary(op, right)
	else
		return self:call()
	end
end

function Parser:call()
	local expr = self:primary()
	local arglist = self:primary()
	while arglist do
		expr = AST.Expr.Call(expr, arglist)
		arglist = self:primary()
	end
	return expr
end

function Parser:primary()
	if self:match {"number", "string"} then
		return AST.Expr.Literal(self:previous())
	elseif self:match {"opening parenthesis"} then
		return self:group()
	elseif self:match {"identifier"} then -- variable
		return AST.Expr.Variable(self:previous())
	end
end

function Parser:group()
	local expressions = {}
	while not self:match {"closing parenthesis"} do
		local expression = self:expression()
		if not expression then
			Parser.error(self:peek(), "Expected expression")
		end
		table.insert(expressions, expression)
		if not self:match {"comma"} then
			self:consume("closing parenthesis", "Expected ')'")
			break
		end
	end
	return AST.Expr.Group(expressions)
end

function Parser:block()
	local statements = {}
	while not self:match {"closing curly bracket"} do
		local statement = self:statement()
		if not statement then
			Parser.error(self:peek(), "Expected statement")
		end
		table.insert(statements, statement)
	end
	return AST.Expr.Block(statements)
end

function Parser:statement()
	if self:match {"return"} then
		return self:returnStatement()
	else
		return self:expression()
	end
end

function Parser:returnStatement()
	return nil
end

return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
