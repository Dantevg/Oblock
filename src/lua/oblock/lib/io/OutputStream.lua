local stdlib = require "oblock.stdlib"

return function(OutputStream)
	OutputStream:set("write", stdlib.NativeFunction(function(self, str)
		self.file:write(tostring(str))
	end, "write"))
	
	return OutputStream
end
