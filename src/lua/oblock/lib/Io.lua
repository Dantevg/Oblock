local stdlib = require "oblock.stdlib"

return function(Io)
	local InputStream = stdlib.import(nil, "io/InputStream")
	local OutputStream = stdlib.import(nil, "io/OutputStream")
	
	Io:set("read", stdlib.NativeFunction(function(self, path)
		local file = io.open(tostring(path))
		if not file then return stdlib.Nil() end
		local content = file:read("a")
		file:close()
		return stdlib.String(content)
	end, "read"))
	
	local stdin = InputStream:clone()
	Io:set("stdin", stdin)
	stdin.file = io.stdin
	
	local stdout = OutputStream:clone()
	Io:set("stdout", stdout)
	stdout.file = io.stdout
	
	return Io
end
