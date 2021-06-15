local Interpreter = require "Interpreter"

local fn = {}

fn.clock = os.clock
fn.print = function(...)
	-- Pass-through variables
	print(...)
	return ...
end

fn.type = function(x)
	if not x then return "Nil" end
	return x.__name
end

return function(env)
	for name, f in pairs(fn) do
		env:define(name, Interpreter.NativeFunction(env, f))
	end
	env:define("Block", Interpreter.Block.proto)
	env:define("Function", Interpreter.Function.proto)
	env:define("Number", Interpreter.Number.proto)
	env:define("String", Interpreter.String.proto)
	env:define("Boolean", Interpreter.Boolean.proto)
	env:define("Nil", Interpreter.Nil.proto)
	env:define("List", Interpreter.List.proto)
	
	env:define("nil", Interpreter.Nil.proto:get("nil"))
	env:define("true", Interpreter.Boolean.proto:get("true"))
	env:define("false", Interpreter.Boolean.proto:get("false"))
end
