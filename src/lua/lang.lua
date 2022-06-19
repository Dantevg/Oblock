local Lexer = require "Lexer"
local Parser = require "Parser"

return function(interpreter, filename, content)
	if not content then
		local file = io.open(filename, "r")
		if not file then return end
		content = file:read("a")
		file:close()
	end
	local tokens = Lexer(content, filename):lex()
	if not tokens then return end
	local program = Parser(tokens, filename):parse()
	if not program then return end
	
	return interpreter:interpret(program)
end
