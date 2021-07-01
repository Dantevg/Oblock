local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local args = {...}
local path = args[1]
local isDemo = args[1] == "--demo" or args[2] == "--demo"
local file = path and io.open(path) or io.stdin

if isDemo then print() end
local content = file:read("a")
file:close()
if isDemo then print() end

local filename = string.match(path or "", "/([^/]+)$") or path or "stdin"

local tokens = Lexer(content, filename):lex()
if not tokens then return end
local program = Parser(tokens, filename):parse()
if not program then return end

if isDemo then
	Interpreter(program):interpret()
	print()
else
	print(Interpreter(program):interpret())
end
