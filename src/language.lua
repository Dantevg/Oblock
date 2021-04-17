local Lexer, Parser = require "Lexer", require "Parser"

local path = (...)
local file = io.open(path)
local content = file:read("a")
file:close()

print( Parser(Lexer(content):lex()):parse():evaluate() )
