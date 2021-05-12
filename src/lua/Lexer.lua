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

function Lexer.new(source, name)
	local self = {}
	self.source = source
	self.name = name
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
	if not self.hasError then return self.tokens end
end

function Lexer:addToken(type, literal)
	local text = self:sub()
	table.insert(self.tokens, Token(type, text, literal, self.line))
end

function Lexer:error(message, where)
	self.hasError = true
	print("["..(self.name and self.name..":" or "")..self.line.."]"..(where and where..": " or " ")..(message or ""))
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

function Lexer:string(quote)
	while self:peek() ~= quote and self.current <= #self.source do
		if self:peek() == "\n" then self.line = self.line+1 end
		self:advance()
	end
	
	if self.current > #self.source then
		self:error("Unterminated string")
		return
	end
	
	self:advance() -- Closing " or '
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

local function canCombineWith(token, char)
	for i = 2, #token do
		if token[i] == char then return true end
	end
	return false
end

function Lexer:combine(token)
	local name = token[1]
	local nextChar = self:peek()
	while canCombineWith(token, nextChar) do
		self:advance()
		token = Lexer.tokens[nextChar]
		name = name.." "..token[1]
		nextChar = self:peek()
	end
	self:addToken(name)
end

function Lexer:whitespace(char)
	-- Collapse multiple whitespace and newline characters into a single token
	-- (or no token if no newlines were present)
	local hasNewline = (char == "\n")
	if hasNewline then self.line = self.line+1 end
	while self:peek():match("[ \r\t\n]") do
		if self:advance() == "\n" then
			hasNewline = true
			self.line = self.line+1
		end
	end
	if hasNewline then self:addToken("newline") end
end

function Lexer:scanToken()
	local char = self:advance()
	if char:match("[ \r\t\n]") then
		self:whitespace(char)
	elseif Lexer.tokens[char] then
		self:combine(Lexer.tokens[char])
	elseif char == '"' or char == "'" then
		self:string(char)
	elseif char:match("%d") then
		self:number()
	elseif char:match("[%a_]") then
		self:identifier()
	else
		self:error("Unexpected character: '"..char.."'")
	end
end

-- Contains the name and other characters after this one to combine with
-- example: "+=" will combine into token with name "plus equal"
Lexer.tokens = {
	["("] = {"opening parenthesis"},
	[")"] = {"closing parenthesis"},
	["{"] = {"opening curly bracket"},
	["}"] = {"closing curly bracket"},
	["["] = {"opening bracket"},
	["]"] = {"closing bracket"},
	["!"] = {"exclamation", '='},
	["#"] = {"hash", '='},
	["$"] = {"dollar", '='},
	["%"] = {"percent", '='},
	["&"] = {"and", '=', '&'},
	["*"] = {"star", '='},
	["+"] = {"plus", '='},
	[","] = {"comma"},
	["-"] = {"minus", '='},
	["."] = {"dot", '.'},
	["/"] = {"slash", '='},
	[":"] = {"colon", '='},
	[";"] = {"semicolon"},
	["<"] = {"less", '=', '<'},
	["="] = {"equal", '=', '>'},
	[">"] = {"greater", '=', '>'},
	["?"] = {"question", '='},
	["@"] = {"at", '='},
	["\\"]= {"backslash"},
	["^"] = {"hat", '='},
	["`"] = {"backtick"},
	["|"] = {"bar", '=', '|'},
	["~"] = {"tilde", '='},
}

Lexer.keywords = {
	["if"] = true, ["else"] = true,
	["while"] = true, ["for"] = true, ["in"] = true,
	["return"] = true, ["yield"] = true,
	["var"] = true, ["const"] = true, ["instance"] = true,
}

return setmetatable(Lexer, {
	__call = function(_, ...) return Lexer.new(...) end,
})