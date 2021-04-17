local Lexer, Parser = require "Lexer", require "Parser"

local path = (...)
local file = io.open(path)
local content = file:read("a")
file:close()

local tokens = Lexer(content):lex()
if not tokens then return end
local program = Parser(tokens):parse()
if not program then return end
print(program:evaluate())
