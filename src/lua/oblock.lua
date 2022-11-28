#!/usr/bin/env lua

package.path = package.path..";lib/?.lua"

local Lexer = require "oblock.Lexer"
local Parser = require "oblock.Parser"
local Interpreter = require "oblock.Interpreter"
local stdlib = require "oblock.stdlib"
local has_tc, tc = pcall(require, "terminalcolours")
local pretty = require("pretty").new { deep = 2, multiline = true}

local version = "0.5"

local args = {...}
local function hasArg(name)
	for _, arg in ipairs(args) do
		if arg == name then return true end
	end
	return false
end

local path = args[1]
local doParse = not hasArg("--lex")
local doInterpret = doParse and not hasArg("--parse")
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
if isInteractive then
	interpreter.environment:setHere("O", stdlib.Block())
end

function perform(content)
	-- Lex
	local tokens = Lexer(content, filename):lex()
	if not tokens then return end
	
	if not doParse then
		print(pretty(tokens))
		return
	end
	
	-- Parse
	local program = Parser(tokens, filename):parse(isInteractive)
	if not program then return end
	
	if not doInterpret then
		print(program)
		print( (program:debug()) )
		return
	end
	
	-- Interpret
	local values = {interpreter:interpret(program)}
	if #values > 0 then print(table.unpack(values)) end
end

if isInteractive then
	while true do
		io.write("> ")
		local content = file:read("l")
		if content == nil then print() break end
		perform(content)
	end
else
	local content = file:read("a")
	perform(content)
end
file:close()
