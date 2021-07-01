-- Inspired by https://craftinginterpreters.com/scanning.html

local tc = require "terminalcolours"

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new(source, name)
	local self = {}
	self.source = source
	self.name = name
	self.tokens = {}
	self.start, self.current, self.line = 1, 1, 1
	self.lineStart, self.column = 1, 1
	self.hasError = false
	return setmetatable(self, Lexer)
end

function Lexer.getLine(source, lineStart)
	local lineEnd = source:find("\n", lineStart, true)
	return source:sub(lineStart, lineEnd and lineEnd-1)
end

function Lexer.getLineFromToken(token)
	if not token.lexer then return "" end
	return Lexer.getLine(token.lexer.source, token.lineStart)
end

function Lexer:token(type, lexeme, literal)
	return {
		lexer = self,
		type = type,
		lexeme = lexeme,
		literal = literal,
		line = self.line,
		column = self.column,
		lineStart = self.lineStart,
	}
end

function Lexer:lex()
	while self.current <= #self.source do
		self.start = self.current
		self.column = self.start - self.lineStart + 1
		self:scanToken()
	end
	table.insert(self.tokens, self:token("EOF", "", nil))
	if not self.hasError then return self.tokens end
end

function Lexer:addToken(type, literal)
	local text = self:sub()
	table.insert(self.tokens, self:token(type, text, literal))
end

function Lexer:getCurrentLine()
	return Lexer.getLine(self.source, self.lineStart)
end

function Lexer:printError(token, message)
	local line = token and token.line or self.line
	local column = token and token.column or self.column
	local code = token and Lexer.getLineFromToken(token) or self:getCurrentLine()
	
	print(tc(tc.fg.red)..string.format("[%s%d:%d] %s",
		(self.name and self.name..":" or ""), line, column, message))
	print(tc(tc.reset)..line.." | "..code)
	print(tc(tc.fg.red)..string.rep(' ', #tostring(line) + 3 + column-1)
		..string.rep('▔', token and #token.lexeme or 1)..tc(tc.reset))
end

function Lexer:error(message)
	self.hasError = true
	self:printError(nil, message)
end

function Lexer:advance()
	self.current = self.current+1
	return self.source:sub(self.current-1, self.current-1)
end

function Lexer:nextLine()
	self.line = self.line+1
	self.lineStart = self.current
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
		if self:peek() == "\n" then self:nextLine() end
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
	if hasNewline then self:nextLine() end
	while self:peek():match("[ \r\t\n]") do
		if self:advance() == "\n" then
			hasNewline = true
			self:nextLine()
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
	["|"] = {"bar", '=', '|', '>'},
	["~"] = {"tilde", '='},
}

Lexer.keywords = {
	["if"] = true, ["else"] = true,
	["while"] = true, ["for"] = true, ["in"] = true,
	["return"] = true, ["yield"] = true,
	["var"] = true, ["const"] = true,
	["static"] = true, ["instance"] = true,
}

return setmetatable(Lexer, {
	__call = function(_, ...) return Lexer.new(...) end,
})
