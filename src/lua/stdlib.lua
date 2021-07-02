local Interpreter = require "Interpreter"

local fn = {}

fn.clock = function() return Interpreter.Number(nil, os.clock()) end
fn.print = function(_, ...)
	-- Pass-through variables
	print(...)
	return ...
end

fn.type = function(_, x)
	if not x then return "Nil" end
	return Interpreter.String(nil, x.__name)
end

return function(env)
	for name, f in pairs(fn) do
		env:set(name, Interpreter.NativeFunction(env, f), nil, 0)
	end
	env:set("Block", Interpreter.Block.proto, nil, 0)
	env:set("Function", Interpreter.Function.proto, nil, 0)
	env:set("Number", Interpreter.Number.proto, nil, 0)
	env:set("String", Interpreter.String.proto, nil, 0)
	env:set("Boolean", Interpreter.Boolean.proto, nil, 0)
	env:set("Nil", Interpreter.Nil.proto, nil, 0)
	env:set("List", Interpreter.List.proto, nil, 0)
	
	env:set("nil", Interpreter.Nil.proto:get("nil"), nil, 0)
	env:set("true", Interpreter.Boolean.proto:get("true"), nil, 0)
	env:set("false", Interpreter.Boolean.proto:get("false"), nil, 0)
end
