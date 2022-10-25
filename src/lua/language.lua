local Lexer = require "Lexer"
local Parser = require "Parser"
local Interpreter = require "Interpreter"
local has_tc, tc = pcall(require, "terminalcolours")

local version = "0.4"

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

if file == io.stdin then
	if has_tc then
		local function withGradient(text, gradient)
			local str = {}
			for _, code in utf8.codes(text) do
				table.insert(str, gradient[#str / 2 + 1])
				table.insert(str, utf8.char(code))
			end
			return table.concat(str, "")..tc.colour(tc.reset)
		end
		
		print("   "..withGradient("        ", {
			tc.colour(tc.bg.rgb(42, 79, 177)),
			tc.colour(tc.bg.rgb(47, 72, 168)),
			tc.colour(tc.bg.rgb(50, 65, 158)),
			tc.colour(tc.bg.rgb(53, 57, 149)),
			tc.colour(tc.bg.rgb(54, 50, 140)),
			tc.colour(tc.bg.rgb(55, 43, 131)),
			tc.colour(tc.bg.rgb(55, 35, 121)),
			tc.colour(tc.bg.rgb(55, 27, 112)),
		})..tc.parse(" {reset}{bg.grey} "..version.." {reset}"))
		
		print(withGradient("░░░ oblock ", {
			tc.colour(tc.fg.rgb(0, 102, 204)),
			tc.colour(tc.fg.rgb(23, 94, 195)),
			tc.colour(tc.fg.rgb(34, 87, 186)),
			tc.colour(tc.reset, tc.bg.rgb(42, 79, 177)),
			tc.colour(tc.bg.rgb(47, 72, 168)),
			tc.colour(tc.bg.rgb(50, 65, 158)),
			tc.colour(tc.bg.rgb(53, 57, 149)),
			tc.colour(tc.bg.rgb(54, 50, 140)),
			tc.colour(tc.bg.rgb(55, 43, 131)),
			tc.colour(tc.bg.rgb(55, 35, 121)),
			tc.colour(tc.bg.rgb(55, 27, 112)),
		}))
	else
		print("oblock "..version)
	end
end

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
		local values = {interpreter:interpret(program)}
		if #values > 0 then print(table.unpack(values)) end
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
