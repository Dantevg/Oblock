-- Inspired by http://craftinginterpreters.com/parsing-expressions.html

local AST = require "AST"

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
	local self = {}
	self.tokens = tokens
	self.current = 1
	self.nlSensitive = false
	return setmetatable(self, Parser)
end

function Parser.error(token, message)
	error("["..token.line.."] Error at '"..token.lexeme.."': "..(message or ""), 2)
end

function Parser:nextIndex()
	return (self.nlSensitive or self.tokens[self.current].type ~= "newline")
		and self.current or self.current+1
end

function Parser:peek()
	return self.tokens[self:nextIndex()]
end

function Parser:previous()
	return self.tokens[self.current-1]
end

function Parser:advance()
	if self:peek().type ~= "EOF" then self.current = self:nextIndex()+1 end
	return self:previous()
end

function Parser:match(types)
	local token = self:peek()
	for _, t in ipairs(types) do
		if token.type == t then
			self:advance()
			return true
		end
	end
	return false
end

function Parser:consume(type, message)
	local token = self:peek()
	if token.type == type then
		return self:advance()
	else
		Parser.error(token, message)
	end
end

function Parser:binary(tokens, next)
	local expr = next(self)
	
	while self:match(tokens) do
		local op = self:previous()
		local right = next(self)
		expr = AST.Expr.Binary(expr, op, right)
	end
	
	return expr
end

function Parser:parse()
	local expr = self:expression()
	if self:peek().type ~= "EOF" then
		Parser.error(self:peek(), "Expected EOF")
	end
	return expr
end

function Parser:expression()
	return self:definition()
end

function Parser:definition()
	local modifiers = {}
	while self:match {"var", "const", "instance"} do
		local mod = self:previous().type
		if modifiers[mod] then Parser.error(self:previous(), "duplicate modifier") end
		modifiers[mod] = true
	end
	
	local expr = self:func()
	local isDefinition, isAssignment = false, false
	
	if modifiers.var or modifiers.const or modifiers.instance then
		if self:match {"equal"} then
			isDefinition = true
		else
			if expr.__name ~= "Variable" then
				Parser.error(self:previous(), "Attempt to assign to non-variable type "..expr.__name)
			else
				return AST.Expr.Definition(expr, nil, modifiers)
			end
		end
	elseif self:match {"colon equal"} then
		isDefinition = true
	elseif self:match {"equal"} then
		isAssignment = true
	end
	
	if isDefinition or isAssignment then
		local equal = self:previous()
		local value = self:expression()
		if expr.__name == "Variable" then
			modifiers.var = nil
			return isDefinition
				and AST.Expr.Definition(expr, value, modifiers)
				or AST.Expr.Assignment(expr, value)
		else
			Parser.error(equal, "Attempt to assign to non-variable type "..expr.__name)
		end
	end
	
	return expr
end

function Parser:func()
	local expr = self:comparison()
	
	if self:match {"equal greater"} then
		local arrow = self:previous()
		local body = self:expression()
		-- Check if expression is variable or group of variables
		if expr.__name == "Variable" then
			return AST.Expr.Function(AST.Expr.Group {expr}, body)
		elseif expr.__name == "Group" then
			return AST.Expr.Function(expr, body)
		else
			Parser.error(arrow, "Invalid function argument")
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
	if self:match {"minus", "exclamation", "dot dot dot"} then
		local op = self:previous()
		local right = self:unary()
		return AST.Expr.Unary(op, right)
	else
		return self:call()
	end
end

function Parser:call()
	local expr = self:index()
	local nl = self.nlSensitive
	self.nlSensitive = true
	local arglist = self:index()
	while arglist do
		expr = AST.Expr.Call(expr, arglist)
		self.nlSensitive = true
		arglist = self:index()
	end
	self.nlSensitive = nl
	return expr
end

function Parser:index()
	local expr = self:primary()
	while self:match {"dot"} do
		if self:match {"opening bracket"} then
			local expression = self:expression()
			self:consume("closing bracket", "expected ']'")
			expr = AST.Expr.Variable(expr, expression)
		elseif self:match {"identifier"} then
			local name = self:previous().lexeme
			expr = AST.Expr.Variable(expr, AST.Expr.Literal(name, name))
		else
			Parser.error(self:peek(), "Expected identifier or []")
		end
	end
	return expr
end

function Parser:primary()
	if self:match {"number", "string"} then
		return AST.Expr.Literal(self:previous())
	elseif self:match {"true"} then
		return AST.Expr.Literal.True()
	elseif self:match {"false"} then
		return AST.Expr.Literal.False()
	elseif self:match {"opening parenthesis"} then
		self.nlSensitive = false
		return self:group()
	elseif self:match {"opening bracket"} then
		self.nlSensitive = false
		return self:list()
	elseif self:match {"opening curly bracket"} then
		self.nlSensitive = false
		return self:block()
	elseif self:match {"identifier"} then
		local name = self:previous().lexeme
		return AST.Expr.Variable(nil, AST.Expr.Literal(name, name))
	end
end

function Parser:group()
	local expressions = self:explist("closing parenthesis", ")")
	return AST.Expr.Group(expressions)
end

function Parser:list()
	local expressions = self:explist("closing bracket", "]")
	return AST.Expr.List(expressions)
end

function Parser:explist(endTokenName, endChar)
	local expressions = {}
	while not self:match {endTokenName} do
		local expression = self:expression()
		if not expression then
			Parser.error(self:peek(), "Expected expression")
		end
		table.insert(expressions, expression)
		if not self:match {"comma"} then
			self:consume(endTokenName, "Expected '"..endChar.."'")
			break
		end
	end
	return expressions
end

function Parser:block()
	local statements = {}
	while not self:match {"closing curly bracket"} do
		while self:match {"semicolon"} do end -- Skip semicolons
		local statement = self:statement()
		if not statement then
			Parser.error(self:peek(), "Expected statement")
		end
		table.insert(statements, statement)
		while self:match {"semicolon"} do end -- Skip semicolons
	end
	return AST.Expr.Block(statements)
end

function Parser:statement()
	if self:match {"return"} then
		return self:returnStatement()
	elseif self:match {"yield"} then
		return self:yieldStatement()
	elseif self:match {"if"} then
		return self:ifStatement()
	elseif self:match {"while"} then
		return self:whileStatement()
	else
		return self:expression()
	end
end

function Parser:returnStatement()
	return AST.Stat.Return(self:expression())
end

function Parser:yieldStatement()
	return AST.Stat.Yield(self:expression())
end

function Parser:ifStatement()
	local condition = self:expression()
	self:consume("colon", "Expected ':'")
	local ifTrue = self:statement()
	if not ifTrue then Parser.error(self:peek(), "Expected statement") end
	local ifFalse
	if self:match {"else"} then
		ifFalse = self:statement()
		if not ifFalse then
			Parser.error(self:peek(), "Expected statement")
		end
	end
	return AST.Stat.If(condition, ifTrue, ifFalse)
end

function Parser:whileStatement()
	local condition = self:expression()
	self:consume("colon", "Expected ':'")
	local body = self:statement()
	if not body then Parser.error(self:peek(), "Expected statement") end
	return AST.Stat.While(condition, body)
end

return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
