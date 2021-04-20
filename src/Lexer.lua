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

function Lexer.new(source)
	local self = {}
	self.source = source
	self.tokens = {}
	self.start, self.current, self.line = 1, 1, 1
	self.hasError = false
	return setmetatable(self, Lexer)
end

function Lexer.checkNext(...)
	local chars = {...}
	return function(self, type)
		for _, char in ipairs(chars) do
			if self:match(char) then
				self:addToken(type.." "..Lexer.tokens[char][2])
				return
			end
		end
		self:addToken(type)
	end
end

function Lexer:lex()
	while self.current <= #self.source do
		self.start = self.current
		self:scanToken()
	end
	table.insert(self.tokens, Token("EOF", "", nil, self.line))
	if not self.hasError then return self.tokens end
end

function Lexer:addToken(type, literal)
	local text = self:sub()
	table.insert(self.tokens, Token(type, text, literal, self.line))
end

function Lexer:error(message, where)
	self.hasError = true
	print("["..self.line.."] Error"..(where or "")..": "..(message or ""))
end

function Lexer:advance()
	self.current = self.current+1
	return self.source:sub(self.current-1, self.current-1)
end

function Lexer:peek(n)
	n = n or 0
	return self.current+n <= #self.source and self.source:sub(self.current+n, self.current+n) or "\0"
end

function Lexer:match(char)
	if self:peek() == char then
		self.current = self.current+1
		return true
	else
		return false
	end
end

function Lexer:sub()
	return self.source:sub(self.start, self.current-1)
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
	self:addToken("string", self.source:sub(self.start+1, self.current-2))
end

function Lexer:number()
	while self:peek():match("%d") do self:advance() end
	
	if self:peek() == "." and self:peek(1):match("%d") then
		self:advance()
		while self:peek():match("%d") do self:advance() end
	end
	
	self:addToken("number", tonumber(self:sub()))
end

function Lexer:identifier()
	while self:peek():match("[%w_]") do self:advance() end
	local keyword = self:sub()
	self:addToken(Lexer.keywords[keyword] and keyword or "identifier")
end

function Lexer:whitespace()
	while self:peek():match("[ \r\t]") do self:advance() end
	self:addToken("whitespace")
end

function Lexer:scanToken()
	local char = self:advance()
	local token = Lexer.tokens[char]
	if char == "\n" then
		self:addToken("newline")
		self.line = self.line+1
	elseif token then
		token[1](self, table.unpack(token, 2))
	elseif char:match("%d") then
		self:number()
	elseif char:match("[%a_]") then
		self:identifier()
	else
		self:error("Unexpected character")
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
	[":"] = {Lexer.addToken, "colon"},
	["!"] = {Lexer.checkNext("="), "exclamation"},
	["="] = {Lexer.checkNext("=", ">"), "equal"},
	["<"] = {Lexer.checkNext("=", "<"), "less"},
	[">"] = {Lexer.checkNext("=", ">"), "greater"},
	['"'] = {Lexer.string, "string"},
	[" "] = {Lexer.whitespace, "whitespace"},
	["\r"]= {Lexer.whitespace, "whitespace"},
	["\t"]= {Lexer.whitespace, "whitespace"},
}

Lexer.keywords = {
	["if"] = true, ["elseif"] = true, ["else"] = true,
	["while"] = true, ["for"] = true, ["in"] = true,
	["return"] = true, ["yield"] = true,
	["true"] = true, ["false"] = true, -- TODO: remove, temporary!
}

return setmetatable(Lexer, {
	__call = function(_, ...) return Lexer.new(...) end,
})
