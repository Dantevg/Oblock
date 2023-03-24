-- Inspired by https://craftinginterpreters.com/scanning.html

local tc = require "terminalcolours"

---@class Lexer
---@field source string
---@field name string?
local Lexer = {}
Lexer.__index = Lexer

--- Create a new lexer instance.
---@param source string
---@param name string?
---@return Lexer
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

--- Get an entire line of the given `source` at the given index `lineStart`.
---@param source string
---@param lineStart integer
---@return string
function Lexer.getLine(source, lineStart)
	local lineEnd = source:find("\n", lineStart, true)
	return source:sub(lineStart, lineEnd and lineEnd-1)
end

--- Get the entire line of code which the `token` is placed in.
---@param token Token
---@return string
function Lexer.getLineFromToken(token)
	if not token.lexer then return "" end
	return Lexer.getLine(token.lexer.source, token.lineStart)
end

---@class Token
---@field lexer Lexer
---@field type string
---@field lexeme string
---@field literal any?
---@field line integer
---@field column integer
---@field lineStart integer

--- Create a new token.
---@param type string
---@param lexeme string
---@param literal any?
---@return Token
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

--- Lex the source file.
--- Returns `nil` if there were errors.
---@return Token[]?
function Lexer:lex()
	while self.current <= #self.source do
		self.start = self.current
		self.column = self.start - self.lineStart + 1
		self:scanToken()
	end
	self.start = self.current
	self.column = self.start - self.lineStart + 1
	table.insert(self.tokens, self:token("EOF", "", nil))
	if not self.hasError then return self.tokens end
end

--- Add a token of given `type` to the token list.
---@param type string
---@param literal any?
function Lexer:addToken(type, literal)
	local text = self:sub()
	table.insert(self.tokens, self:token(type, text, literal))
end

--- Get the line of code the lexer is currently at.
---@return string
function Lexer:getCurrentLine()
	return Lexer.getLine(self.source, self.lineStart)
end

--- Print an error message for the given `token`.
---@param token Token?
---@param message string
function Lexer:printError(token, message)
	local line = token and token.line or self.line
	local column = token and token.column or self.column
	local code = token and Lexer.getLineFromToken(token) or self:getCurrentLine()
	local _, nTabs = code:gsub("\t", "")
	
	print(tc(tc.fg.red)..string.format("[%s%d:%d] %s",
		(self.name and self.name..":" or ""), line, column, message))
	print(tc(tc.reset)..line.." | "..code:gsub("\t", "    "))
	print(tc(tc.fg.red)..string.rep(' ', #tostring(line) + 3 + column-1 + nTabs*3)
		..string.rep('▔', token and math.max(1, #token.lexeme) or 1)..tc(tc.reset))
end

--- Error with the given `message` for the given `token`.
---@param message string
---@param token boolean? whether to add an error token at the current position
function Lexer:error(message, token)
	self.hasError = true
	self:printError(token and self:token("error", self:sub()) or nil, message)
end

--- Advance the scanner and return the character that was advanced over.
---@return string
function Lexer:advance()
	self.current = self.current+1
	return self.source:sub(self.current-1, self.current-1)
end

--- Update the `line` and `lineStart` counters for a line break.
--- Does *not* insert a newline token.
function Lexer:nextLine()
	self.line = self.line+1
	self.lineStart = self.current
end

--- Get the character at the current scanner location, but do not advance.
--- When at or past the end of the file, returns a null-character.
---@param n integer? the index after the current location to peek (default 0)
---@return string
function Lexer:peek(n)
	n = n or 0
	return self.current+n <= #self.source and self.source:sub(self.current+n, self.current+n) or "\0"
end

--- If the current character is `char`, advance.
---@param char string
---@return boolean # whether the character matches
function Lexer:match(char)
	if self:peek() == char then
		self.current = self.current+1
		return true
	else
		return false
	end
end

--- Get the substring from the start of the token to the current position.
---@return string
function Lexer:sub()
	return self.source:sub(self.start, self.current-1)
end

--- Lex a string, including escape characters.
---@param quote string the quote type used to start the string, either `"` or `'`
function Lexer:string(quote)
	local strTbl = {}
	while self:peek() ~= quote and self.current <= #self.source do
		if self:match("\n") then
			self:nextLine()
			table.insert(strTbl, "\n")
		elseif self:match("\\") then
			if self:match("n") then
				table.insert(strTbl, "\n")
			elseif self:match("t") then
				table.insert(strTbl, "\t")
			elseif self:match("\\") then
				table.insert(strTbl, "\\")
			elseif self:match('"') then
				table.insert(strTbl, '"')
			elseif self:match("'") then
				table.insert(strTbl, "'")
			else
				self:error("Invalid escape sequence: \\"..self:peek())
			end
		else
			table.insert(strTbl, self:advance())
		end
	end
	
	if self.current > #self.source then
		self:error("Unterminated string")
		return
	end
	
	self:advance() -- Closing " or '
	self:addToken("string", table.concat(strTbl))
end

--- Lex a number.
function Lexer:number()
	while self:peek():match("%d") do self:advance() end
	
	if self:peek() == "." and self:peek(1):match("%d") then
		self:advance()
		while self:peek():match("%d") do self:advance() end
	end
	
	self:addToken("number", tonumber(self:sub()))
end

--- Lex an identifier or keyword.
function Lexer:identifier()
	while self:peek():match("[%w_]") do self:advance() end
	local keyword = self:sub()
	self:addToken(Lexer.keywords[keyword] and keyword or "identifier")
end

--- Check if `char` appended to `token` is a valid token.
---@param token Token
---@param char string
---@return boolean
local function canCombineWith(token, char)
	for i = 2, #token do
		if token[i] == char then return true end
	end
	return false
end

--- Try to combine the current token with as many following characters as possible.
---@param token Token
function Lexer:combine(token)
	local name = token[1]
	local nextChar = self:peek()
	while canCombineWith(token, nextChar) do
		self:advance()
		token = Lexer.tokens[nextChar]
		name = name.." "..token[1]
		nextChar = self:peek()
	end
	if self.current > self.start + 2 and not Lexer.longTokens[name]
			and (self:peek(-1) ~= "=" or self:peek(-2) == "=") then
		self:error("Unknown long token", true)
	else
		self:addToken(name)
	end
end

--- Lex whitespace and newlines.
---@param char string the character that started the whitespace
---@param ignore boolean? whether to ignore newlines (to not add newline tokens)
function Lexer:whitespace(char, ignore)
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
	if hasNewline and not ignore then self:addToken("newline") end
end

--- Lex line comments.
function Lexer:lineComment()
	while self:advance() ~= "\n" do end
	-- Prevent multiple newline tokens if there was a newline before this comment
	self:whitespace("\n", #self.tokens == 0 or (self.tokens[#self.tokens].type == "newline"))
end

--- Lex block comments.
function Lexer:blockComment()
	while self:advance() ~= ":" or self:peek() ~= ")" do
		if self:peek() == "\n" then self:nextLine() end
	end
	self:advance() -- Closing )
	-- Prevent multiple newline tokens
	if self:peek():match("[ \r\t\n]") then self:whitespace(self:advance(), true) end
end

--- Scan a single token.
function Lexer:scanToken()
	local char = self:advance()
	if char:match("[ \r\t\n]") then
		self:whitespace(char)
	elseif char == "-" and self:peek() == "-" then
		self:lineComment()
	elseif char == "(" and self:peek() == ":" then
		self:blockComment()
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
	["&"] = {"and", '='},
	["*"] = {"star", '='},
	["+"] = {"plus", '=', '+'},
	[","] = {"comma"},
	["-"] = {"minus", '='},
	["."] = {"dot", '.'},
	["/"] = {"slash", '=', '/'},
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
	["|"] = {"bar", '=', '>'},
	["~"] = {"tilde", '='},
}

Lexer.keywords = {
	["if"] = true, ["else"] = true,
	["while"] = true, ["for"] = true, ["in"] = true,
	["and"] = true, ["or"] = true,
	["break"] = true, ["continue"] = true,
	["return"] = true, ["yield"] = true,
	["var"] = true, ["const"] = true, ["rec"] = true
}

Lexer.longTokens = {["dot dot dot"] = true}

return setmetatable(Lexer, {
	__call = function(_, ...) return Lexer.new(...) end,
})
