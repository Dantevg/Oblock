-- Inspired by http://craftinginterpreters.com/parsing-expressions.html

local AST = require "AST"

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens, name)
	local self = {}
	self.tokens = tokens
	self.name = name
	self.current = 1
	self.nlSensitive = false
	return setmetatable(self, Parser)
end

function Parser:error(token, message)
	token.lexer:printError(token, message)
	error(true)
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
		self:error(token, message)
	end
end

function Parser:binary(tokens, next, fn)
	local expr = next(self)
	
	while self:match(tokens) do
		local op = self:previous()
		local right = next(self)
		expr = (fn or AST.Expr.Binary)(expr, op, right)
	end
	
	return expr
end

function Parser:parse()
	local success, result = pcall(function()
		local expr = self:expression()
		if self:peek().type ~= "EOF" then
			self:error(self:peek(), "Expected EOF")
		end
		return expr
	end)
	if success then
		return result
	elseif result ~= true then
		error(result)
	end
end

function Parser:expression()
	return self:func()
end

function Parser:defExpr()
	return self:assignment(true)
end

function Parser:func()
	local expr = self:disjunction()
	
	if expr and expr.__name ~= "Call" and self:match {"equal greater"} then
		local arrow = self:previous()
		local body = self:expression()
		-- Check if expression is variable or group of variables
		if expr.__name == "Variable" then -- arg => body
			return AST.Expr.Function(AST.Expr.Group {expr}, body)
		elseif expr.__name == "Group" then -- (arg, arg) => body
			return AST.Expr.Function(expr, body)
		else
			self:error(arrow, "Invalid function parameter: "..expr.__name)
		end
	end
	-- other case: name arg => body  or  name(arg, arg) => body
	
	return expr
end

function Parser:disjunction()
	return self:binary({"bar bar"}, Parser.conjunction, AST.Expr.Logical)
end

function Parser:conjunction()
	return self:binary({"and and"}, Parser.pipe, AST.Expr.Logical)
end

function Parser:pipe()
	return self:binary({"bar greater"}, Parser.comparison)
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
	local expr = self:variable()
	local nl = self.nlSensitive
	self.nlSensitive = true
	local arglist = self:variable()
	while arglist do
		expr = AST.Expr.Call(expr, arglist)
		self.nlSensitive = true
		arglist = self:variable()
	end
	self.nlSensitive = nl
	return expr
end

function Parser:variable()
	local expr = self:primary()
	while self:match {"dot"} do
		expr = AST.Expr.Index(expr, self:primary())
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
		return AST.Expr.Variable(self:previous())
	end
end

function Parser:group()
	return AST.Expr.Group(self:sequence("closing parenthesis", "comma", "defExpr"))
end

function Parser:list()
	return AST.Expr.List(self:sequence("closing bracket", "comma", "defExpr"))
end

function Parser:block()
	return AST.Expr.Block(self:sequence("closing curly bracket", "semicolon", "statement"))
end

function Parser:sequence(endTokenName, separator, type)
	local elements = {}
	while not self:match {endTokenName} do
		while self:match {separator} do end -- Skip separators
		local element = self[type](self)
		if not element then
			self:error(self:peek(), "Expected "..type)
		end
		table.insert(elements, element)
		while self:match {separator} do end -- Skip separators
	end
	return elements
end

function Parser:anylist(first, next, typename)
	local elements = {first}
	if not first then self:error(self:previous(), "Expected "..typename, 0) end
	while self:match {"comma"} do
		local element = next(self)
		if element then
			table.insert(elements, element)
		else
			self:error(self:previous(), "Expected "..typename)
		end
	end
	return elements
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
	elseif self:match {"for"} then
		return self:forStatement()
	else
		return self:assignment()
	end
end

function Parser:returnStatement()
	local values = self:anylist(self:expression(), self.expression, "expression")
	return AST.Stat.Return(values)
end

function Parser:yieldStatement()
	local values = self:anylist(self:expression(), self.expression, "expression")
	return AST.Stat.Yield(values)
end

function Parser:ifStatement()
	local condition = self:expression()
	self:consume("colon", "Expected ':'")
	local ifTrue = self:statement()
	if not ifTrue then self:error(self:peek(), "Expected statement") end
	local ifFalse
	if self:match {"else"} then
		ifFalse = self:statement()
		if not ifFalse then
			self:error(self:peek(), "Expected statement")
		end
	end
	return AST.Stat.If(condition, ifTrue, ifFalse)
end

function Parser:whileStatement()
	local condition = self:expression()
	self:consume("colon", "Expected ':'")
	local body = self:statement()
	if not body then self:error(self:peek(), "Expected statement") end
	return AST.Stat.While(condition, body)
end

function Parser:forStatement()
	local variable = AST.Expr.Variable(
		AST.Expr.Literal(self:consume("identifier", "Expected identifier"))
	)
	self:consume("in", "Expected 'in'")
	local expr = self:expression()
	self:consume("colon", "Expected ':'")
	local body = self:statement()
	if not body then self:error(self:peek(), "Expected statement") end
	
	return AST.Stat.For(variable, expr, body)
end

function Parser:assignment(isExpr)
	local modifiers = {}
	local isAssignment, isFunction = false, false
	
	-- Match modifiers: `var`, `const`, `instance`
	while self:match {"var", "const", "instance"} do
		local mod = self:previous().type
		if modifiers[mod] then self:error(self:previous(), "duplicate modifier") end
		modifiers[mod] = true
	end
	
	-- Match assignment target
	local variables = isExpr
		and {self:expression()}
		or self:anylist(self:expression(), self.expression, "expression")
	local expr = variables[1]
	
	if self:match {"equal"} then -- a = b
		isAssignment = true
	elseif self:match {"equal greater"} then -- a => b
		isFunction = true
	elseif modifiers.var or modifiers.const or modifiers.instance then -- var a
		return AST.Stat.Assignment(variables, {}, modifiers, false)
	end
	
	if isAssignment or isFunction then
		-- Match `=` and values
		local equal = self:previous()
		local values = isExpr
			and {self:expression()}
			or self:anylist(self:expression(), self.expression, "expression")
		if isAssignment then
			return AST.Stat.Assignment(variables, values, modifiers, false)
		elseif isFunction and expr.__name == "Call" and #variables == 1 then
			local name, parameters = expr.expression, expr.arglist
			if parameters.__name == "Variable" then -- name arg => body
				parameters = AST.Expr.Group {parameters}
			elseif parameters.__name ~= "Group" then -- name(arg, arg) => body
				self:error(equal, "Invalid function parameter: "..parameters.__name)
			end
			return AST.Stat.Assignment({name}, {AST.Expr.Function(parameters, values[1])}, modifiers, true)
		else
			self:error(equal, "Invalid assignment target: "..expr.__name)
		end
	end
	
	return expr
end


return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
