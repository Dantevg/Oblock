local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"

local args = {...}
local function hasArg(name)
	for _, arg in ipairs(args) do
		if arg == name then return true end
	end
	return false
end

local path = args[1]
local isDemo = hasArg("--demo")
local isDebug = hasArg("--debug")
local isInteractive = hasArg("--interactive") or hasArg("-i")
local file = (path and not isInteractive) and io.open(path) or io.stdin
local filename = (file == io.stdin) and "stdin" or string.match(path or "", "/([^/]+)$") or path

local interpreter = Interpreter()

function eval(content)
	if isDemo then print() end
	
	local tokens = Lexer(content, filename):lex()
	if not tokens then return end
	local program = Parser(tokens, filename):parse()
	if not program then return end
	
	if isDebug then print(program:debug()) end
	
	if isDemo then
		interpreter:interpret(program)
		print()
	else
		print(interpreter:interpret(program))
	end
end

if isDemo then print() end
if isInteractive then
	while true do
		io.write("> ")
		local content = file:read("l")
		if content == nil then print() break end
		eval(content)
	end
else
	local content = file:read("a")
	eval(content)
end
file:close()
