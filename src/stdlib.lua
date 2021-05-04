local Interpreter = require "Interpreter"

local fn = {}

fn.clock = os.clock
fn.print = function(...)
	-- Pass-through variables
	print(...)
	return ...
end

return function(env)
	for name, f in pairs(fn) do
		env:define(name, Interpreter.NativeFunction(env, f))
	end
	env:define("nil", Interpreter.Nil(env))
	env:define("true", Interpreter.Boolean(env, true))
	env:define("false", Interpreter.Boolean(env, false))
end
