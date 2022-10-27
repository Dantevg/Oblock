local stdlib = require "stdlib"

return function(InputStream)
	InputStream:set("read", stdlib.NativeFunction(function(self)
		local char = self.file:read(1)
		return char and stdlib.String(char) or stdlib.Nil()
	end, "read"))
	
	return InputStream
end
