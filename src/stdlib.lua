local Interpreter = require "Interpreter"

local fn = {}

fn.clock = os.clock
fn.print = print

return function(env)
	for name, f in pairs(fn) do
		env:define(name, Interpreter.NativeFunction(env, f))
	end
end
