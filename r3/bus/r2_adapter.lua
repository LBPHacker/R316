local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx  = require("spaghetti.bitx")
local plot  = require("spaghetti.plot")
local util  = require("r3.util")

local function build(control_ba, data_ba)
	assert(type(control_ba) == "number", "control_ba must be a number")
	assert(bitx.band(control_ba, 0xFFFF0000) == 0, "control_ba has reserved bits set")
	local terminate
	if data_ba == "terminate" then
		terminate = true
	else
		assert(type(data_ba) == "number", "data_ba must be a number")
		assert(bitx.band(data_ba, 0xFFFF0000) == 0, "data_ba has reserved bits set")
		assert(control_ba ~= data_ba, "control_ba must be distinct from data_ba")
	end
	local pt = plot.pt
	local parts = {}
	local ucontext = util.make_context(parts)
	local part        = ucontext.part
	local aray        = ucontext.aray
	local dray        = ucontext.dray
	local cray        = ucontext.cray
	local ldtc        = ucontext.ldtc
	local solid_spark = ucontext.solid_spark

	local use_insl = {}
	local x_left13 = 2
	part({ type = pt.FILT, x = 0, y = 0 })
	part({ type = pt.FILT, x = 0, y = 1 })
	part({ type = pt.CRMC, x = 1, y = 0 })
	part({ type = pt.CRMC, x = 1, y = 1 })
	part({ type = pt.FILT, x = x_left13, y = 0, ctype = 0x10000003 })

	local x_control_port = 4
	local x_data_port = 15

	-- read control port
	do
		ldtc(x_control_port, 0, 0, 0)
		aray(x_control_port, 0, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_control_port + 1, y = 0 })
		part({ type = pt.STOR, x = x_control_port + 2, y = 0 })
		part({ type = pt.FILT, x = x_control_port + 3, y = 0, tmp = 7, ctype = bitx.bor(0x10080000, control_ba) })
		part({ type = pt.FILT, x = x_control_port + 4, y = 0, ctype = 0x10000004 })

		local x_dtec = x_control_port + 8
		use_insl[x_dtec] = true
		ldtc(x_dtec, 0, x_left13, 0, nil, 1)
		ldtc(x_dtec, 0, x_control_port + 5, 0, nil, 1)
		part({ type = pt.DTEC, x = x_dtec, y = 0, tmp2 = 2 })
		part({ type = pt.CRMC, x = x_dtec - 2, y = 0 })
		part({ type = pt.FILT, x = x_dtec + 1, y = 0 })
		part({ type = pt.SPRK, x = x_dtec, y = -1, ctype = pt.PSCN, life = 4 })
		part({ type = pt.LSNS, x = x_dtec, y = 0, tmp = 3, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 2 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 2 })

		part({ type = pt.INSL, x = x_dtec, y = 4 })
		dray(x_dtec, 5, x_dtec, 3, 1, pt.PSCN)
		dray(x_dtec, 5, x_dtec, 2, 1, pt.PSCN)

		part({ type = pt.CRMC, x = x_dtec - 2, y = 1 })
		part({ type = pt.BRAY, x = x_dtec - 2, y = 4, ctype = 0x10000008, life = 500, tmp = 1 })
		part({ type = pt.BRAY, x = x_dtec - 2, y = 5, ctype = bitx.bor(0x20000000, terminate and 0 or data_ba), life = 500, tmp = 1 })
		aray(x_dtec - 2, 6, 0, 1, pt.METL, 0, 500)

		if not terminate then
			local x_bump = 9
			aray(x_bump - 2, -1, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_bump - 1, y = -1, ctype = 0x00010000 })
			part({ type = pt.FILT, x = x_bump    , y = -1, tmp = 3, ctype = 0x20000000 })
			part({ type = pt.FILT, x = x_bump + 1, y = -1, ctype = 0x10000004 })

			cray(x_bump - 3, 4, x_bump + 2, -1, pt.SPRK, 1, pt.PSCN)
		end

		part({ type = pt.CONV, x = x_dtec, y = 2, ctype = pt.FILT, tmp = pt.INSL })
	end

	-- read data port
	if not terminate then
		ldtc(x_data_port, 0, 0, 0)
		aray(x_data_port, 0, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_data_port + 1, y = 0 })
		part({ type = pt.STOR, x = x_data_port + 2, y = 0 })
		part({ type = pt.FILT, x = x_data_port + 3, y = 0, tmp = 7, ctype = bitx.bor(0x10080000, data_ba) })
		part({ type = pt.FILT, x = x_data_port + 4, y = 0, ctype = 0x10000004 })

		local x_dtec = x_data_port + 6
		use_insl[x_dtec] = true
		ldtc(x_dtec, 0, x_left13, 0, nil, 1)
		ldtc(x_dtec, 0, x_data_port + 5, 0, nil, 1)
		part({ type = pt.FILT, x = x_dtec + 1, y = 0 })
		part({ type = pt.SPRK, x = x_dtec, y = -1, ctype = pt.PSCN, life = 4 })
		part({ type = pt.LSNS, x = x_dtec, y = 0, tmp = 3, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 1 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 2 })
		part({ type = pt.CRAY, x = x_dtec, y = 0, ctype = pt.DTEC, tmp = 1, tmp2 = 2 })

		part({ type = pt.CRMC, x = x_dtec - 2, y = 1 })
		part({ type = pt.BRAY, x = x_dtec - 2, y = 4, ctype = 0x10000008, life = 500, tmp = 1 })
		aray(x_dtec - 2, 6, 0, 1, pt.METL, 0, 500)

		part({ type = pt.INSL, x = x_dtec, y = 4 })
		dray(x_dtec, 5, x_dtec, 3, 1, pt.PSCN)
		dray(x_dtec, 5, x_dtec, 2, 1, pt.PSCN)

		part({ type = pt.CRAY, x = x_dtec - 1, y = 8, ctype = pt.SPRK, tmp = 1, tmp2 = 7 })
		solid_spark(x_dtec, 9, -1, 0, pt.PSCN)

		part({ type = pt.FILT, x = x_data_port + 1, y = -1, ctype = 0x20000000, tmp = 3 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  1, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  4, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  5, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_data_port + 2, y =  5, tmp = 6 })
		part({ type = pt.FILT, x = x_data_port + 3, y =  5, tmp = 6 })
		part({ type = pt.FILT, x = x_data_port + 4, y =  5, tmp = 6 })
		part({ type = pt.BRAY, x = x_data_port + 5, y =  5, life = 500, ctype = 0xFFFFFFFF })
		aray(x_data_port, 5, -1, 0, pt.METL, nil, 500)
		cray(3, 5, 20, 5, pt.SPRK, 1, pt.PSCN)
		dray(x_data_port + 2, -1, x_control_port + 5, -1, 1, pt.PSCN)

		part({ type = pt.CONV, x = x_dtec, y = 2, ctype = pt.FILT, tmp = pt.INSL })
	end

	-- write data port
	if not terminate then
		part({ type = pt.FILT, x = x_data_port + 1, y =  6, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  7, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  8, ctype = 0x20000000, tmp = 6 })
		part({ type = pt.FILT, x = x_data_port + 1, y =  9, ctype = 0x20000000, tmp = 6 })
		part({ type = pt.DTEC, x = x_data_port + 2, y =  9, tmp2 = 1 })
		part({ type = pt.STOR, x = x_data_port + 2, y =  8, tmp2 = 1 })
		part({ type = pt.STOR, x = x_data_port + 2, y =  9, tmp2 = 1 })
		part({ type = pt.CRMC, x = x_data_port + 4, y =  8 })
		part({ type = pt.CRMC, x = x_data_port + 4, y =  9 })

		ldtc(x_data_port - 10, 8, x_data_port - 10, 0)
		part({ type = pt.STOR, x = x_data_port - 11, y = 9 })
		part({ type = pt.FILT, x = x_data_port - 10, y = 9 })
		for i = 1, 7 do
			part({ type = pt.STOR, x = x_data_port - 10 + i, y = 9 })
		end
		part({ type = pt.FILT, x = x_data_port - 2, y = 9, ctype = bitx.bor(0x10020000, data_ba), tmp = 7 })
		part({ type = pt.FILT, x = x_data_port - 1, y = 9, ctype = 0x20000000 })
		part({ type = pt.STOR, x = x_data_port, y = 9 })
		aray(x_data_port - 12, 9, -1, 0, pt.METL)

		aray(x_data_port - 9, 8, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_data_port - 8, y = 8 })
		for i = 1, 8 do
			part({ type = pt.STOR, x = x_data_port - 8 + i, y = 8 })
		end
		ldtc(x_data_port - 9, 7, 0, 1)
	end

	local x1, y1, x2, y2 = 0, -3, 24, 11
	if terminate then
		x2 = 15
	end

	for xx = 0, x2 do
		part({ type = use_insl[xx] and pt.INSL or pt.FILT, x = xx, y = 2 })
		part({ type = use_insl[xx] and pt.INSL or pt.FILT, x = xx, y = 3 })
	end

	ldtc(x2 - 1, 0, 0, 0)
	ldtc(x2 - 1, 1, 0, 1)
	part({ type = pt.FILT, x = x2, y = 0 })
	part({ type = pt.FILT, x = x2, y = 1 })

	if not terminate then
		part({ type = pt.FILT, x = x_data_port + 1, y = 10 })
		part({ type = pt.FILT, x = x_data_port + 2, y = 10 })
		part({ type = pt.FILT, x = x_data_port + 1, y = 11 })
		part({ type = pt.FILT, x = x_data_port + 2, y = 11 })
	end

	for xx = x1 + 1, x2 - 1 do
		part({ type = pt.DMND, x = xx, y = y1    , unstack = true })
		part({ type = pt.DMND, x = xx, y = y1 + 1, unstack = true })
		part({ type = pt.DMND, x = xx, y = y2 - 1, unstack = true })
		part({ type = pt.DMND, x = xx, y = y2    , unstack = true })
	end
	for yy = y1 + 1, y2 - 1 do
		part({ type = pt.DMND, x = x1    , y = yy, unstack = true })
		part({ type = pt.DMND, x = x1 + 1, y = yy, unstack = true })
		part({ type = pt.DMND, x = x2 - 1, y = yy, unstack = true })
		part({ type = pt.DMND, x = x2    , y = yy, unstack = true })
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
