local fn = {}

fn.clock = os.clock

fn.print = print

return function(env)
	for name, f in pairs(fn) do
		env:set(name, {call = function(_, args)
			return f(table.unpack(args))
		end})
	end
end
