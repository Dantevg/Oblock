local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local path = (...)
local file = path and io.open(path) or io.stdin
local content = file:read("a")
file:close()

local tokens = Lexer(content):lex()
if not tokens then return end
local program = Parser(tokens):parse()
if not program then return end

print(Interpreter(program):interpret())
