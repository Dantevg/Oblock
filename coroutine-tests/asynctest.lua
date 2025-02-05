local function parallel(fns)
	local cos = {}
	for _, fn in ipairs(fns) do
		table.insert(cos, {
			co = coroutine.create(fn),
			blockingOn = nil
		})
	end
	
	local function anyAlive()
		for _, co in ipairs(cos) do
			if coroutine.status(co.co) ~= "dead" then
				return true
			end
		end
		return false
	end
	
	while anyAlive() do
		-- print "iteration"
		for _, co in ipairs(cos) do
			if coroutine.status(co.co) ~= "dead" then
				if co.blockingOn == nil or co.blockingOn() then
					local success, value = coroutine.resume(co.co)
					co.blockingOn = value
				end
			end
		end
	end
end

local function waitFor(fn)
	while not fn() do end
end

local function isAfter(time)
	return function() return os.clock() > time end
end

local function sleep(time)
	coroutine.yield(isAfter(os.clock() + time))
end

parallel {
	function()
		print "A1"
		sleep(2)
		print "A2"
		sleep(2)
		print "A3"
	end,
	function()
		print "B1"
		sleep(1)
		print "B2"
	end
}
