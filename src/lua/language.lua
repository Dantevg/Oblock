local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local args = {...}
local path = args[1]
local isDemo = args[1] == "--demo" or args[2] == "--demo" or args[3] == "--demo"
local isDebug = args[1] == "--debug" or args[2] == "--debug" or args[3] == "--debug"
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

if isDebug then
	print(program:debug())
end

if isDemo then
	Interpreter(program):interpret()
	print()
else
	print(Interpreter(program):interpret())
end
