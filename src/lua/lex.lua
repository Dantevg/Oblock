local Lexer = require "Lexer"
local pretty = require("pretty").new { deep = 2, multiline = true}

local path = (...)
local file = path and io.open(path) or io.stdin
local content = file:read("a")
file:close()

local filename = string.match(path or "", "/([^/]+)$") or path

local tokens = Lexer(content, filename):lex()
if not tokens then return end

print(pretty(tokens))
