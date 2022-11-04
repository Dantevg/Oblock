local stdlib = require "oblock.stdlib"

return function(Vector)
	Vector:set("+", stdlib.NativeFunction(function(self, other)
		local vec = Vector:clone()
		vec:set("x", self:get("x") + other:get("x"))
		vec:set("y", self:get("y") + other:get("y"))
		return vec
	end, "+"))
	
	return Vector
end
