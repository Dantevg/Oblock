-- Inspired by https://craftinginterpreters.com/scanning.html

function Token(type, lexeme, literal, line)
	local token = {}
	token.type = type
	token.lexeme = lexeme
	token.literal = literal
	token.line = line
	return token
end

local Lexer = {}
Lexer.__index = Lexer

function Lexer.checkNext(char)
	return function(self, type)
		self:addToken(self:match(char) and type.." "..Lexer.tokens[char][2] or type)
	end
end

Lexer.tokens = {
	["("] = {Lexer.addToken, "opening parenthesis"},
	[")"] = {Lexer.addToken, "closing parenthesis"},
	["{"] = {Lexer.addToken, "opening curly bracket"},
	["}"] = {Lexer.addToken, "closing curly bracket"},
	["["] = {Lexer.addToken, "opening bracket"},
	["]"] = {Lexer.addToken, "closing bracket"},
	[","] = {Lexer.addToken, "comma"},
	["."] = {Lexer.addToken, "dot"},
	["-"] = {Lexer.addToken, "minus"},
	["+"] = {Lexer.addToken, "plus"},
	["*"] = {Lexer.addToken, "star"},
	["/"] = {Lexer.addToken, "slash"},
	[";"] = {Lexer.addToken, "semicolon"},
	["!"] = {Lexer.checkNext("="), "exclamation"},
	["="] = {Lexer.checkNext("="), "equal"},
	["<"] = {Lexer.checkNext("="), "less"},
	[">"] = {Lexer.checkNext("="), "greater"},
	['"'] = {Lexer.string, "string"},
}

Lexer.ignored = {[" "] = true, ["\r"] = true, ["\t"] = true}

function Lexer.new(source)
	local self = {}
	self.source = source
	self.tokens = {}
	self.start, self.current, self.line = 1, 1, 1
	self.hasError = false
	return setmetatable(self, Lexer)
end

function Lexer:lex()
	while self.current <= #self.source do
		self.start = self.current
		self:scanToken()
	end
	table.insert(self.tokens, Token("EOF", "", nil, self.line))
	return self.tokens
end

function Lexer:error(where, message)
	self.hasError = true
	print("["..self.line.."] Error"..(where or "")..": "..(message or ""))
end

function Lexer:advance()
	self.current = self.current+1
	return self.source:sub(self.current-1, self.current-1)
end

function Lexer:peek()
	return self.current <= #self.source and self.source:sub(self.current, self.current) or "\0"
end

function Lexer:match(char)
	if self:peek() == char then
		self.current = self.current+1
		return true
	else
		return false
	end
end

function Lexer:addToken(type, literal)
	local text = self.source:sub(self.start, self.current)
	table.insert(self.tokens, Token(type, text, literal, self.line))
end

function Lexer:string()
	while self:peek() ~= '"' and self.current <= #self.source do
		if self:peek() == "\n" then self.line = self.line+1 end
		self:advance()
	end
	
	if self.current > #self.source then
		self:error("Unterminated string")
		return
	end
	
	self:advance() -- Closing "
	self:addToken("string", self.source:sub(self.start+1, self.current-1))
end

function Lexer:scanToken()
	local char = self:advance()
	local token = Lexer.tokens[char]
	if char == "\n" then
		self.line = self.line+1
	elseif token then
		token[1](self, table.unpack(token, 2))
	elseif not Lexer.ignored[char] then
		self:error("Unexpected character")
	end
end

return setmetatable(Lexer, {
	__call = function(_, ...) return Lexer.new(...) end,
})