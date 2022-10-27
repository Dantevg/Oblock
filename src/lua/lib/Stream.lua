local stdlib = require "stdlib"

return function(Stream)
	Stream:set("toString", stdlib.NativeFunction(function(self)
		local strings = {}
		local value = self:get("read"):call()
		while value.__name ~= "Nil" do
			table.insert(strings, tostring(value))
			value = self:get("read"):call()
		end
		return stdlib.String(table.concat(strings))
	end, "toString"))
	
	return Stream
end
