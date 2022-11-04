local has_tc, tc = pcall(require, "terminalcolours") -- Can do without colours
if not has_tc then
	-- So that the program will still run without terminalcolours
	tc = setmetatable(
		{fg = {}, bg = {}, cursor = {}},
		{__call = function() return "" end}
	)
end

local pretty = {}

pretty.colours = {}
pretty.colours._reset   = tc(tc.reset, tc.bright)
pretty.colours._special = tc(tc.bright, tc.fg.magenta)
pretty.colours._mt      = tc(tc.reset, tc.fg.grey)
pretty.colours._nil     = tc(tc.reset, tc.fg.grey)
pretty.colours._number  = tc(tc.reset, tc.fg.cyan)
pretty.colours._string  = tc(tc.reset, tc.fg.green)
pretty.colours._boolean = tc(tc.reset, tc.fg.yellow)
pretty.colours._error   = tc(tc.bright, tc.fg.red)

function pretty:colour(name)
	return self.coloured and self.colours["_"..tostring(name)] or ""
end

function pretty:nop(x) return self:colour("reset")..tostring(x)..self:colour("reset") end

function pretty:special(x)
	return string.format("%s[%s]%s", self:colour("special"), tostring(x), self:colour("reset"))
end

function pretty:prettyprint(x, ...)
	local t = type(x)
	local mt = getmetatable(x) or {}
	
	if self[t] and not (type(mt) == "table" and rawget(mt, "__tostring")) then
		if type(mt) ~= "table" then
			return self[t](self, x, ...)..self:colour("mt")
				.." (metatable is a "..type(mt).."!)"..self:colour("reset")
		else
			return self[t](self, x, ...)
		end
	else
		return self:nop(x)
	end
end

function pretty:prettykey(x)
	if type(x) == "string" and x:match("^[%a_][%w_]*$") then
		return tostring(x)
	else
		return "["..self:prettyprint(x).."]"
	end
end

pretty["nil"]     = function(self, x) return self:colour("nil")        ..tostring(x)..self:colour("reset") end
pretty["number"]  = function(self, x) return self:colour("number")     ..tostring(x)..self:colour("reset") end
pretty["string"]  = function(self, x) return self:colour("string")..'"'..tostring(x)..self:colour("string")..'"'..self:colour("reset") end
pretty["boolean"] = function(self, x) return self:colour("boolean")    ..tostring(x)..self:colour("reset") end

pretty["table"] = function(self, x, depth)
	if type(x) ~= "table" and not rawget(getmetatable(x) or {}, "__pairs") then
		return self:error("not a table")
	end
	depth = depth or 0
	if depth >= self.deep then return self:special(x) end
	
	local contents = {}
	
	if type(x) == "table" then
		for _, v in ipairs(x) do
			table.insert(contents, self:prettyprint(v, depth + 1))
		end
	end
	
	for k, v in pairs(x) do
		if not contents[k] then
			table.insert(contents, self:prettykey(k).." = "..self:prettyprint(v, depth + 1))
		end
	end
	
	if self.multiline then
		local indent = string.rep("  ", depth)
		local newindent = indent.."  "
		return self:colour("reset").."{\n"
			..newindent..table.concat(contents, ",\n"..newindent).."\n"
			..indent..self:colour("reset").."}"
			..(getmetatable(x) and self:colour("mt").." + mt"..self:colour("reset") or "")
	else
		return self:colour("reset").."{ "..table.concat(contents, ", ")..self:colour("reset").." }"
			..(getmetatable(x) and self:colour("mt").." + mt"..self:colour("reset") or "")
	end
end

pretty["function"] = function(self, x)
	if type(x) ~= "function" then return self:error("not a function") end
	local d = debug.getinfo(x, "S")
	local filename = d.short_src:match("([^/]+)$")
	local str = string.format("%s[%s @ %s:%d]",
		self:colour("special"), tostring(x), filename, d.linedefined)
		
	if self.deep == 0 or d.source:sub(1,1) ~= "@" or d.source == "@stdin" then
		return str
	end
	
	local file = io.open(d.source:sub(2))
	local contents = {}
	local i = 1
	for line in file:lines() do
		if i >= d.linedefined then
			if i > d.linedefined then break end
			table.insert(contents, line)
		end
		i = i+1
	end
	file:close()
	return str..self:colour("reset").."\n"..table.concat(contents, "\n")..self:colour("reset")
end

pretty["thread"] = pretty.special
pretty["userdata"] = pretty.special

pretty["error"] = function(self, x)
	return self:colour("error")..tostring(x)..self:colour("reset")
end

function pretty.new(options)
	local self = setmetatable({}, pretty)
	options = options or {}
	if options.deep ~= nil then self.deep = options.deep end
	if options.multiline ~= nil then self.multiline = options.multiline end
	if options.coloured ~= nil then self.coloured = options.coloured end
	
	if self.deep == true then self.deep = 128 end
	if not self.deep then self.deep = 0 end
	
	return self
end

pretty.deep = 128
pretty.multiline = false
pretty.coloured = true

pretty.__index = pretty
pretty.__call = pretty.prettyprint

return setmetatable(pretty, {
	__call = function(_, ...) return pretty:prettyprint(...) end,
})
