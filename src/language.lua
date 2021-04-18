local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local path = (...)
local file = io.open(path)
local content = file:read("a")
file:close()

local tokens = Lexer(content):lex()
if not tokens then return end
local program = Parser(tokens):parse()
if not program then return end

print(Interpreter(program):interpret())
