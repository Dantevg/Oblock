local stdlib = require "stdlib"

return function(Vector)
	Vector:setHere("+", stdlib.NativeFunction(function(self, other)
		local vec = Vector:clone()
		vec:setHere("x", self:get("x") + other:get("x"))
		vec:setHere("y", self:get("y") + other:get("y"))
		return vec
	end, "+"))
	
	return Vector
end
