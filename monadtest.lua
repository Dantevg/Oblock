local function just(x)
	return function(fn) return fn(x) end
end

local function none() return none end

local function incr(x) return just(x + 1) end
local function monadprint(x) print(x) return just(x) end

just(10)(incr)(monadprint)
none()(incr)(monadprint)

local function nike(fn)
	local co = coroutine.create(fn)
	local function continue(x)
		local success, value = coroutine.resume(co, x)
		if not success then error(value) end
		return (coroutine.status(co) ~= "dead") and value(continue) or value
	end
	return continue(nil)
end

local bind = coroutine.yield

local a = nike(function()
	local x = bind(just(37))
	local y = bind(none())
	return just(x + y)
end)

local b = nike(function()
	local x = bind(just(37))
	local y = bind(just(5))
	return just(x + y)
end)

a(monadprint) --> does not print
b(monadprint) --> prints 42
