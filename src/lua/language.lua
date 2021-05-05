local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local path = (...)
local file = path and io.open(path) or io.stdin
local content = file:read("a")
file:close()

local filename = string.match(path or "", "/([^/]+)$") or path

local tokens = Lexer(content, filename):lex()
if not tokens then return end
local program = Parser(tokens, filename):parse()
if not program then return end

print(Interpreter(program):interpret())
