-- Inspired by http://craftinginterpreters.com/parsing-expressions.html

local AST = require "oblock.AST"

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

function Parser:loc(token)
	token = token or self:previous() or self:peek()
	return {
		file = self.name,
		line = token.line,
		column = token.column,
	}
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

function Parser:assert(value, type, token)
	if not value then self:error(token or self:peek(), "Expected "..type) end
	return value
end

function Parser:binary(tokens, next, fn)
	local expr = next(self)
	
	while self:match(tokens) do
		local op = self:previous()
		local right = next(self)
		if fn then
			-- For logical operators
			expr = fn(expr, op, right, self:loc(op))
		else
			-- Desugar normal binary operator into function call
			expr = AST.Expr.Call(
				AST.Expr.Index(expr, AST.Expr.Literal(op.lexeme, op.lexeme, self:loc(op))),
				right, self:loc(op), true
			)
		end
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
		error(result, 0)
	end
end

function Parser:expression()
	return self:control()
end

function Parser:defExpr()
	return self:assignment(true)
end

function Parser:control()
	if self:match {"if"} then
		return self:ifExpr(self:loc())
	elseif self:match {"while"} then
		return self:whileExpr(self:loc())
	elseif self:match {"for"} then
		return self:forExpr(self:loc())
	else
		return self:func()
	end
end

function Parser:ifExpr(loc)
	local condition = self:assert(self:expression(), "expression")
	self:consume("colon", "Expected ':'")
	local ifTrue = self:assert(self:statement(), "statement")
	local ifFalse
	if self:match {"else"} then
		ifFalse = self:assert(self:statement(), "statement")
	end
	return AST.Expr.If(condition, ifTrue, ifFalse, loc)
end

function Parser:whileExpr(loc)
	local condition = self:assert(self:expression(), "expression")
	self:consume("colon", "Expected ':'")
	local body = self:assert(self:statement(), "statement")
	return AST.Expr.While(condition, body, loc)
end

function Parser:forExpr(loc)
	local pattern = AST.Pattern.Group(self:anylist(self.expression, "expression", true))
	self:consume("in", "Expected 'in'")
	local expr = self:assert(self:expression(), "expression")
	self:consume("colon", "Expected ':'")
	local body = self:assert(self:statement(), "statement")
	return AST.Expr.For(pattern, expr, body, loc)
end

function Parser:func()
	local expr = self:disjunction()
	local pattern = expr and AST.Pattern(expr)
	
	if expr and expr.__name ~= "Call" and self:match {"equal greater"} then
		local arrow = self:previous()
		if not pattern then
			self:error(arrow, "Invalid function pattern: "..expr.__name)
		end
		local body = self:expression()
		
		return AST.Expr.Function(pattern, body, self:loc(arrow))
	end
	
	return expr
end

function Parser:disjunction()
	return self:binary({"or"}, Parser.conjunction, AST.Expr.Logical)
end

function Parser:conjunction()
	return self:binary({"and"}, Parser.pipe, AST.Expr.Logical)
end

function Parser:pipe()
	return self:binary({"bar greater"}, Parser.lowpredop)
end

function Parser:lowpredop()
	return self:binary({"plus plus"}, Parser.comparison)
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
		return AST.Expr.Call(
				AST.Expr.Index(right, AST.Expr.Literal(op.lexeme, op.lexeme, self:loc(op))),
				AST.Expr.Group({}, self:loc(op)), self:loc(op), true
			)
	else
		return self:varcall()
	end
end

function Parser:varcall()
	local expr = self:primary()
	while true do
		local loc = self:loc()
		if self:match {"dot"} then
			expr = AST.Expr.Index(expr, self:primary(), loc)
		else
			local nl = self.nlSensitive
			self.nlSensitive = true
			local arglist = self:primary()
			self.nlSensitive = nl
			if not arglist then break end
			expr = AST.Expr.Call(expr, arglist, loc)
		end
	end
	return expr
end

function Parser:primary()
	if self:match {"number", "string"} then
		return AST.Expr.Literal(self:previous(), nil, self:loc())
	elseif self:match {"opening parenthesis"} then
		self.nlSensitive = false
		return self:group(self:loc())
	elseif self:match {"opening bracket"} then
		self.nlSensitive = false
		return self:list(self:loc())
	elseif self:match {"opening curly bracket"} then
		self.nlSensitive = false
		return self:block(self:loc())
	elseif self:match {"identifier"} then
		return AST.Expr.Variable(self:previous(), self:loc())
	end
end

function Parser:group(loc)
	return AST.Expr.Group(self:expseq("closing parenthesis"), loc)
end

function Parser:list(loc)
	return AST.Expr.List(self:expseq("closing bracket"), loc)
end

function Parser:block(loc)
	return AST.Expr.Block(self:statseq(), loc)
end

function Parser:expseq(endTokenName)
	local elements = {}
	while not self:match {endTokenName} do
		while self:match {"comma"} do end -- Skip separators
		local element = self:assert(self:defExpr(), "expression")
		table.insert(elements, element)
		while self:match {"comma"} do end -- Skip separators
	end
	return elements
end

function Parser:statseq()
	local elements = {}
	while self:peek().type ~= "closing curly bracket" and self:peek().type ~= "EOF" do
		local success, element = pcall(self.statement, self)
		if success then
			table.insert(elements, element)
		else
			error(element)
		end
	end
	self:consume("closing curly bracket", "Expected '}'")
	return elements
end

function Parser:anylist(next, typename, required)
	local elements = {next(self)}
	self.nlSensitive = false
	self:assert(#elements == 1 or not required, typename)
	if #elements == 0 then return elements end
	while self:match {"comma"} do
		local element = next(self)
		self:assert(element, typename)
		table.insert(elements, element)
	end
	return elements
end

function Parser:statement()
	if self:match {"return"} then
		return self:returnStatement(self:loc())
	elseif self:match {"yield"} then
		return self:yieldStatement(self:loc())
	elseif self:match {"break"} then
		return self:breakStatement(self:loc())
	elseif self:match {"continue"} then
		return self:continueStatement(self:loc())
	elseif self:match {"semicolon"} then
		return
	else
		return self:assignment()
	end
end

function Parser:returnStatement(loc)
	local values = self:anylist(self.expression, "expression")
	return AST.Stat.Return(values, loc)
end

function Parser:yieldStatement(loc)
	local values = self:anylist(self.expression, "expression")
	return AST.Stat.Yield(values, loc)
end

function Parser:breakStatement(loc)
	local nl = self.nlSensitive
	self.nlSensitive = true
	local level = 1
	while self:match {"break"} do level = level+1 end
	local values = self:anylist(self.expression, "expression")
	self.nlSensitive = nl
	return AST.Stat.Break(values, level, loc)
end

function Parser:continueStatement(loc)
	return AST.Stat.Continue(loc)
end

function Parser:assignment(isExpr)
	local modifiers = {empty = true}
	local isAssignment, isFunction = false, false
	local compoundOp = nil
	local loc = self:loc(self:peek())
	
	-- Match modifiers: `var`, `const`
	while self:match {"var", "const"} do
		local mod = self:previous().type
		if modifiers[mod] then self:error(self:previous(), "duplicate modifier") end
		modifiers[mod] = true
		modifiers.empty = false
	end
	
	-- Match assignment target
	local patterns = isExpr
		and {self:expression()}
		or self:anylist(self.expression, "expression", true)
	local pattern = AST.Pattern.Group(patterns)
	local expr = patterns[1]
	
	if self:match {"equal"} then -- a = b
		isAssignment = true
		loc = self:loc()
	elseif modifiers.empty and self:peek().type:find(" equal$") then -- a += b
		self:advance()
		isAssignment = true
		loc = self:loc()
		local opToken = self:previous()
		local opLexeme = opToken.lexeme:sub(1, -2) -- Strip away '='
		compoundOp = AST.Expr.Literal(opLexeme, opLexeme, self:loc(opToken))
	elseif self:match {"equal greater"} then -- a => b
		isFunction = true
		loc = self:loc()
	elseif not modifiers.empty then -- var a, const a
		return AST.Stat.Assignment(pattern, {}, modifiers, false, nil, loc)
	end
	
	if isAssignment or isFunction then
		-- Match `=` and values
		local equal = self:previous()
		local values = isExpr
			and {self:expression()}
			or self:anylist(self.expression, "expression", true)
		if isAssignment then
			return AST.Stat.Assignment(pattern, values, modifiers, false, compoundOp, loc)
		elseif isFunction and expr.__name == "Call" and #patterns == 1 then
			local name, parameters = expr.expression, AST.Pattern(expr.arglist)
			return AST.Stat.Assignment(
				AST.Pattern(name), {AST.Expr.Function(parameters, values[1], loc)},
				modifiers, true, nil, loc)
		else
			self:error(equal, "Invalid assignment target: "..expr.__name)
		end
	end
	
	return expr
end


return setmetatable(Parser, {
	__call = function(_, ...) return Parser.new(...) end,
})
