local tc = {}

tc.start = "\x1b["

-- Cursor
local s = tc.start
tc.cursor = {}
tc.cursor._up            = s.."@1A"
tc.cursor._down          = s.."@1B"
tc.cursor._right         = s.."@1C"
tc.cursor._left          = s.."@1D"
tc.cursor._nextline      = s.."@1E"
tc.cursor._prevline      = s.."@1F"
tc.cursor._hor           = s.."@1G"
tc.cursor._pos           = s.."@2;@1H"
tc.cursor.clearend       = s.."0J"
tc.cursor.clearbegin     = s.."1J"
tc.cursor.clear          = s.."2J"
tc.cursor.cleardel       = s.."2J"
tc.cursor.clearlineend   = s.."0K"
tc.cursor.clearlinebegin = s.."1K"
tc.cursor.clearline      = s.."2K"
tc.cursor._scrollup      = s.."@1S"
tc.cursor._scrolldown    = s.."@1T"

tc.cursor.__index = function(t, k)
	if rawget(t, "_"..k) then
		return function(...)
			local arg = {...}
			return t["_"..k]:gsub("@(%d)", function(x) return arg[tonumber(x)] or "" end)
		end
	end
end

setmetatable(tc.cursor, tc.cursor)

-- Effects
tc.reset     = 0
tc.bright    = 1
tc.dim       = 2
tc.underline = 4
tc.blink     = 5
tc.invert    = 7
tc.strike    = 9

-- Foreground / text colour
tc.fg = {}
tc.fg.black   = 30
tc.fg.red     = 31
tc.fg.green   = 32
tc.fg.yellow  = 33
tc.fg.blue    = 34
tc.fg.magenta = 35
tc.fg.cyan    = 36
tc.fg.white   = 37
tc.fg.grey    = 90

tc.fg.rgb = function(r, g, b)
	return 38, 2, r, g, b
end

-- Background colour
tc.bg = {}
tc.bg.black   = 40
tc.bg.red     = 41
tc.bg.green   = 42
tc.bg.yellow  = 43
tc.bg.blue    = 44
tc.bg.magenta = 45
tc.bg.cyan    = 46
tc.bg.white   = 47
tc.bg.grey    = 100

tc.bg.rgb = function(r, g, b)
	return 48, 2, r, g, b
end

-- Aliases
tc.bold = tc.bright
tc.fg.gray = tc.fg.grey
tc.bg.gray = tc.bg.grey

-- Functions
function tc.colour(...)
	local arg = {...}
	if type(arg[1]) == "table" then arg = arg[1] end
	return tc.start..table.concat(arg, ";").."m"
end

-- Parse colour codes like "{reset}" or "{fg.red}"
function tc.parse(str)
	-- Pattern captures:
	-- a = ([^%.}]*) = everything before a '.' or '}'
	-- b =   ([^}]*) = everything before a '}'
	return (str:gsub("{([^%.}]*)%.?([^}]*)}", function(a, b)
		if tc[a] and b == "" then
			return tc.colour(tc[a])
		else
			if b == "" and tc.fg[a] then a, b = "fg", a end
			if tc[a] and tc[a][b] then return tc.colour(tc[a][b]) end
		end
	end))
end

return setmetatable(tc, {
	__call = function(_, ...) return tc.colour(...) end,
})
