local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx  = require("spaghetti.bitx")
local plot  = require("spaghetti.plot")
local util  = require("r3.util")

local function build()
	local pt = plot.pt
	local parts = {}
	local ucontext = util.make_context(parts)
	local part = ucontext.part
	local aray = ucontext.aray
	local ldtc = ucontext.ldtc

	ldtc(1, 0, -1, 0)
	part({ type = pt.FILT, x = 2, y = 0 })
	aray(1, 0, -1, 0, pt.METL)
	part({ type = pt.STOR, x = 3, y = 0 })
	part({ type = pt.FILT, x = 4, y = 0, tmp = 1, ctype = 0x000A0000 })
	part({ type = pt.FILT, x = 5, y = 0, ctype = 0x10000001 })

	part({ type = pt.FILT, x = 0, y = 2 })
	part({ type = pt.FILT, x = 1, y = 2 })
	part({ type = pt.FILT, x = 2, y = 2 })
	part({ type = pt.FILT, x = 3, y = 2 })
	part({ type = pt.DTEC, x = 4, y = 2, tmp2 = 2 })

	for x = 0, 7 do
		part({ type = pt.DMND, x = x, y = -2, unstack = true })
		part({ type = pt.DMND, x = x, y = -1, unstack = true })
		part({ type = pt.DMND, x = x, y =  4, unstack = true })
		part({ type = pt.DMND, x = x, y =  5, unstack = true })
	end
	for y = -1, 4 do
		part({ type = pt.DMND, x = 7, y = y, unstack = true })
		part({ type = pt.DMND, x = 8, y = y, unstack = true })
	end

	for _, part in ipairs(parts) do
		part.dcolour = 0xFF007F7F
		if part.type == pt.DMND then
			part.dcolour = 0xFFFFFFFF
		end
		if part.type == pt.FILT then
			part.dcolour = 0xFF00FFFF
		end
	end
	return parts
end

return {
	build = build,
}
