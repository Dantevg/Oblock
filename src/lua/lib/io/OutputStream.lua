local stdlib = require "stdlib"

return function(OutputStream)
	OutputStream:setHere("write", stdlib.NativeFunction(function(self, str)
		self.file:write(tostring(str))
	end, "write"))
	
	return OutputStream
end