local bitx     = require("spaghetti.bitx")
local plot     = require("spaghetti.plot")
local misc     = require("spaghetti.misc")
local check    = require("spaghetti.check")
local r3_check = require("r3.check")

local function build(params, params_name)
	r3_check.base_address(params_name .. ".bump_address", params.bump_address, 0xFFFF)
	check.table(params_name .. ".ports", params.ports)
	if #params.ports == 0 then
		misc.user_error("%s is empty", params_name .. ".ports")
	end
	local areas = {}
	local parts_out = {}
	local seen_address = {}
	seen_address[params.bump_address] = true
	for ix_port, port in ipairs(params.ports) do
		local port_name = ("params.ports[%i]"):format(ix_port)
		r3_check.base_address(port_name .. ".data_address", port.data_address, 0xFFFF)
		if seen_address[port.data_address] then
			misc.user_error("%s is not unique", port_name .. ".data_address")
		end
		seen_address[port.data_address] = true
		local port_x = r3_check.lowhigh(port_name, port, "left", "right")
		local parts = {}
		local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
		local part        = ucontext.part
		local aray        = ucontext.aray
		local dray        = ucontext.dray
		local cray        = ucontext.cray
		local ldtc        = ucontext.ldtc
		local solid_spark = ucontext.solid_spark
		local pt = plot.pt
		local width = 41
		local xoff
		if port_x.which == "left" then
			xoff = port_x.value
		else
			xoff = port_x.value - width + 1
		end

		local input_0, input_1
		for y = 0, 3 do
			part({ type = pt.FILT, x = 0, y = y })
			local p = part({ type = pt.FILT, x = 1, y = y })
			if y == 0 then
				input_0 = p
			elseif y == 1 then
				input_1 = p
			end
		end
		part({ type = pt.FILT, x = width - 1, y = 0 })
		part({ type = pt.FILT, x = width - 1, y = 1 })
		part({ type = pt.FILT, x = width - 1, y = 2 })
		part({ type = pt.FILT, x = width - 1, y = 3 })
		part({ type = pt.FILT, x = width - 2, y = 2 })
		part({ type = pt.FILT, x = width - 2, y = 3 })
		for x = 2, width - 3 do
			part({ type = pt.FILT, x = x, y = 2, unstack = true })
			part({ type = pt.FILT, x = x, y = 3, unstack = true })
		end
		ldtc(width - 2, 0, input_0.x, input_0.y)
		ldtc(width - 2, 1, input_1.x, input_1.y)
		local bump_check
		local x_cleanup = width - 4
		do
			local x_recv = 5
			local x_wait = x_recv + 9
			local x_send = x_wait + 9
			local x_bump = x_send + 8
			ldtc(x_recv - 1, 0, input_0.x, input_0.y)
			dray(x_recv - 1, 0, x_wait, 0, 1, pt.METL)
			dray(x_recv - 1, 0, x_send, 0, 1, pt.METL)
			dray(x_recv - 1, 0, x_bump, 0, 1, pt.METL)
			aray(x_recv - 1, 0, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_recv    , y = 0 })
			part({ type = pt.STOR, x = x_recv + 1, y = 0 })

			local arays = {}
			local dtecs = {}

			do
				part({ type = pt.FILT, x = x_recv + 6, y = -1 })
				table.insert(dtecs, part({ type = pt.DTEC, x = x_recv + 5, y = 0 }))
				part({ type = pt.LSNS, x = x_recv + 5, y = 0, tmp = 3 })
				part({ type = pt.BRAY, x = x_recv + 4, y = -1, ctype = 0x10000003, life = 4 })
				part({ type = pt.BRAY, x = x_recv + 4, y =  4, ctype = 0x10000008, life = 10000, tmp = 1 })
				local target_reset = part({ type = pt.CONV, x = x_recv + 5, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
				local target_0 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y })
				local target_1 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y + 1 })
				cray(x_recv + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_recv + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_recv + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_recv + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				part({ type = pt.ARAY, x = x_recv + 5, y = 8 })
				dray(x_recv + 5, 9, target_0.x, target_0.y, 1, pt.PSCN)
				dray(x_recv + 5, 9, target_1.x, target_1.y, 1, pt.PSCN)
				part({ type = pt.FILT, x = x_recv + 2, y = 0, tmp = 7, ctype = bitx.bor(0x10080000, port.data_address) })
				part({ type = pt.FILT, x = x_recv + 3, y = 0, ctype = 0x10000004 })
			end
			do
				table.insert(arays, aray(x_wait - 1, 0, -1, 0, pt.METL))
				part({ type = pt.FILT, x = x_wait + 6, y = -1 })
				table.insert(dtecs, part({ type = pt.DTEC, x = x_wait + 5, y = 0 }))
				part({ type = pt.LSNS, x = x_wait + 5, y = 0, tmp = 3 })
				part({ type = pt.BRAY, x = x_wait + 4, y = -1, ctype = 0x10000003, life = 4 })
				part({ type = pt.BRAY, x = x_wait + 4, y =  4, ctype = 0x10000008, life = 10000, tmp = 1 })
				part({ type = pt.BRAY, x = x_wait + 6, y =  5, ctype = bitx.bor(0x20000000, port.data_address), life = 10000, tmp = 1 })
				part({ type = pt.LSNS, x = x_wait + 5, y = 5, tmp = 3 })
				part({ type = pt.FILT, x = x_wait + 4, y = 5, ctype = 0x10001000 })
				local target_reset = part({ type = pt.CONV, x = x_wait + 5, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
				local target_0 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y })
				local target_1 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y + 1 })
				cray(x_wait + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_wait + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_wait + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				cray(x_wait + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
				bump_check = part({ type = pt.FILT, x = x_wait + 1, y = 0, tmp = 2, ctype = 0x20000000 })
				part({ type = pt.FILT, x = x_wait + 2, y = 0, tmp = 7, ctype = bitx.bor(0x30090000, params.bump_address) })
				part({ type = pt.FILT, x = x_wait + 3, y = 0, ctype = 0x10000004 })
				part({ type = pt.ARAY, x = x_wait + 5, y = 8 })
				dray(x_wait + 5, 9, target_0.x, target_0.y, 1, pt.PSCN)
				dray(x_wait + 5, 9, target_1.x, target_1.y, 1, pt.PSCN)
			end
			do
				table.insert(arays, aray(x_send - 1, 0, -1, 0, pt.METL))
				part({ type = pt.FILT, x = x_send + 5, y = -1 })
				table.insert(dtecs, part({ type = pt.DTEC, x = x_send + 4, y = 0 }))
				part({ type = pt.LSNS, x = x_send + 4, y = 0, tmp = 3 })
				part({ type = pt.BRAY, x = x_send + 3, y = -1, ctype = 0x10000003, life = 4 })
				part({ type = pt.BRAY, x = x_send + 3, y =  4, ctype = 0x10000000, life = 10000, tmp = 1 })
				part({ type = pt.LSNS, x = x_send + 4, y =  4, tmp = 3 })
				part({ type = pt.FILT, x = x_send + 5, y =  5, ctype = 0x10001000 })
				local target_reset_0 = part({ type = pt.CONV, x = x_send + 4, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
				local target_0 = part({ type = pt.ARAY, x = target_reset_0.x, y = target_reset_0.y })
				local target_reset_1 = part({ type = pt.CONV, x = x_send + 4, y = 6, ctype = pt.FILT, tmp = pt.ARAY })
				local target_1 = part({ type = pt.ARAY, x = target_reset_1.x, y = target_reset_1.y + 1 })
				cray(x_send + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
				cray(x_send + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
				cray(x_send + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
				cray(x_send + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
				part({ type = pt.FILT, x = x_send + 1, y = 0, tmp = 7, ctype = bitx.bor(0x10020000, port.data_address) })
				part({ type = pt.FILT, x = x_send + 2, y = 0, ctype = 0x10000004 })
				part({ type = pt.ARAY, x = x_send + 4, y = 8 })
				dray(x_send + 4, 9, target_0.x, target_0.y, 1, pt.PSCN)
				dray(x_send + 4, 9, target_1.x, target_1.y, 1, pt.PSCN)
			end
			do
				table.insert(arays, aray(x_bump - 1, 0, -1, 0, pt.METL))
				part({ type = pt.FILT, x = x_bump + 5, y = -1 })
				table.insert(dtecs, part({ type = pt.DTEC, x = x_bump + 4, y = 0 }))
				part({ type = pt.LSNS, x = x_bump + 4, y = 0, tmp = 3 })
				part({ type = pt.BRAY, x = x_bump + 3, y = -1, ctype = 0x10000003, life = 4 })
				part({ type = pt.BRAY, x = x_bump + 3, y =  4, ctype = 0x10000000, life = 10000, tmp = 1 })
				local target_reset_0 = part({ type = pt.CONV, x = x_bump + 4, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
				local target_0 = part({ type = pt.ARAY, x = target_reset_0.x, y = target_reset_0.y })
				local target_reset_1 = part({ type = pt.CONV, x = x_bump + 4, y = 6, ctype = pt.FILT, tmp = pt.ARAY })
				local target_1 = part({ type = pt.ARAY, x = target_reset_1.x, y = target_reset_1.y + 1 })
				cray(x_bump + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
				cray(x_bump + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
				cray(x_bump + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
				cray(x_bump + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
				part({ type = pt.FILT, x = x_bump + 1, y = 0, tmp = 7, ctype = bitx.bor(0x10020000, params.bump_address) })
				part({ type = pt.FILT, x = x_bump + 2, y = 0, ctype = 0x10000004 })
				part({ type = pt.ARAY, x = x_bump + 4, y = 8 })
				dray(x_bump + 4, 9, target_0.x, target_0.y, 1, pt.PSCN)
				dray(x_bump + 4, 9, target_1.x, target_1.y, 1, pt.PSCN)
			end

			for _, p in ipairs(dtecs) do
				dray(x_cleanup, 0, p.x - 1, 0, 1, pt.PSCN)
			end
			for _, p in ipairs(arays) do
				dray(x_cleanup, 0, p.x + 1, 0, 1, pt.PSCN)
			end
		end
		do
			local x_vert = 4
			part({ type = pt.FILT, x = x_vert + 1, y = -3, ctype = 0x20000000 })
			local input = part({ type = pt.FILT, x = x_vert + 1, y = -2 })
			part({ type = pt.FILT, x = x_vert    , y = 5,          ctype = 0x20000000 })
			part({ type = pt.FILT, x = x_vert + 1, y = 5, tmp = 2, ctype = 0x20000000 })
			local recv_read = part({ type = pt.FILT, x = x_vert + 3, y = 5, ctype = 0x0002FFFF, tmp = 1 })
			part({ type = pt.STOR, x = x_vert + 4, y = 5 })
			part({ type = pt.BRAY, x = x_vert + 5, y = 5, ctype = 0x0000FFFF, life = 10000, tmp = 1 })
			local bump_read = part({ type = pt.DTEC, x = bump_check.x, y = 5 })
			part({ type = pt.FILT, x = bump_check.x, y = 1 })
			part({ type = pt.FILT, x = bump_check.x, y = 4 })
			aray(x_vert - 1, 5, -1, 0, pt.METL)
			cray(x_vert - 1, 5, x_vert + 7, 5, pt.STOR, 1, pt.METL)
			dray(x_vert - 1, 5, bump_read.x - 3, bump_read.y, 3, pt.METL)
			for y = 6, 12 do
				part({ type = pt.FILT, x = x_vert, y = y, ctype = 0x20000000 })
			end
			for y = -2, 5 do
				part({ type = pt.FILT, x = x_vert + 1, y = y, ctype = 0x20000000, unstack = true })
			end
			part({ type = pt.DMND, x = x_vert + 8, y = bump_read.y, z = 20000000 })
			dray(x_vert + 8, bump_read.y, x_vert + 6, bump_read.y, 1, pt.PSCN)
			part({ type = pt.LSNS, x = x_vert + 6, y = bump_read.y, tmp = 3 })
			part({ type = pt.FILT, x = x_vert + 7, y = bump_read.y + 1, ctype = 0x10001000 })
			part({ type = pt.CONV, x = x_vert + 7, y = bump_read.y - 1, ctype = pt.STOR, tmp = pt.BRAY })
			part({ type = pt.STOR, x = x_vert + 6, y = bump_read.y })
			dray(x_cleanup, 5, x_vert + 7, bump_read.y, 1, pt.PSCN)
			for x = x_vert - 1, width - 6 do
				part({ type = pt.FILT, x = x, y = 7, unstack = true })
			end
			part({ type = pt.BRAY, x = recv_read.x - 1, y = recv_read.y, life = 1 })
			part({ type = pt.BRAY, x = x_vert + 10, y = recv_read.y, life = 1 })
			local target = part({ type = pt.FILT, x = width - 3, y = 7, ctype = 0x20000000 })
			ldtc(target.x - 2, target.y, target.x, target.y)
			part({ type = pt.FILT, x = 5, y = 12 })
			ldtc(5, 11, 5, 7)
			part({ type = pt.FILT, x = 4, y = -3 })
			part({ type = pt.FILT, x = 4, y = -2 })
			part({ type = pt.DTEC, x = 4, y = -1 })
			aray(3, 8, 0, 1, pt.INST, nil, 2)
			part({ type = pt.STOR, x = 3, y = 6 })
			part({ type = pt.STOR, x = 3, y = 5, z = 20000000 })
			part({ type = pt.STOR, x = 3, y = 4 })
			part({ type = pt.FILT, x = 3, y = 3, tmp = 6 })
			part({ type = pt.FILT, x = 3, y = 2, tmp = 6 })
			part({ type = pt.STOR, x = 3, y = 1 })
			local top_out = part({ type = pt.BRAY, x = 3, y = -1, life = 2, ctype = 0x20000000 })
			cray(top_out.x + 3, top_out.y, top_out.x, top_out.y, pt.SPRK, 1, pt.PSCN)
		end
		do
			local x_send = 22
			local y_send = 6
			aray(x_send - 5, y_send, -1, 0, pt.METL)
			ldtc(x_send, 1, input_1.x, input_1.y)
			local prev = part({ type = pt.FILT, x = x_send + 1, y = 1 })
			ldtc(x_send + 1, y_send - 1, prev.x, prev.y)
			part({ type = pt.FILT, x = x_send + 1, y = y_send, tmp = 2 })
			part({ type = pt.FILT, x = x_send - 1, y = y_send, ctype = 0x20020000 })
			part({ type = pt.STOR, x = x_send - 4, y = y_send })
			part({ type = pt.STOR, x = x_send - 3, y = y_send })
			part({ type = pt.STOR, x = x_send - 2, y = y_send })
			part({ type = pt.STOR, x = x_send    , y = y_send })
			part({ type = pt.STOR, x = x_send + 2, y = y_send })
			part({ type = pt.FILT, x = x_send + 3, y = y_send, tmp = 1, ctype = 0x2002FFFF })
			part({ type = pt.STOR, x = x_send + 5, y = y_send, z = 20000000 })
			for x = x_send + 6, x_send + 9 do
				part({ type = pt.STOR, x = x, y = y_send })
			end
			part({ type = pt.BRAY, x = x_send + 12, y = y_send - 1, ctype = 0x20010000, life = 10000, tmp = 1 })
			part({ type = pt.LSNS, x = x_send + 13, y = y_send - 1, tmp = 3 })
			part({ type = pt.FILT, x = x_send + 14, y = y_send - 2, ctype = 0x10001000 })
			part({ type = pt.FILT, x = x_send + 10, y = y_send, tmp = 7, ctype = bitx.bor(0x20020000, port.data_address) })
			part({ type = pt.FILT, x = x_send + 11, y = y_send, ctype = 0x20000000 })
			part({ type = pt.BRAY, x = x_send +  4, y = y_send, life = 1 })
			part({ type = pt.BRAY, x = x_send + 12, y = y_send, life = 1 })
		end

		for i = 1, #parts do
			local part = parts[i]
			part.dcolour = 0xFF007F7F
			if part.type == pt.FILT then
				part.dcolour = 0xFF00FFFF
			end
		end
		ucontext.frame(1, -2, width - 2, 11, 0, 1)
		plot.merge_parts(xoff, params.bus.y, parts_out, parts)
		local interface = {
			type = "solid",
			name = "port" .. (ix_port - 1),
			x    = xoff,
			y    = params.bus.y - 3,
			w    = width,
			h    = 16,
		}
		table.insert(areas, interface)
		table.insert(params.bus.through_areas, interface)
	end
	do
		local term_x = r3_check.lowhigh(params_name, params, "term_left", "term_right")
		local width = 16
		local xoff
		if term_x.which == "term_left" then
			xoff = term_x.value
		else
			xoff = term_x.value - width + 1
		end

		local parts = {}
		local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
		local part        = ucontext.part
		local aray        = ucontext.aray
		local dray        = ucontext.dray
		local cray        = ucontext.cray
		local ldtc        = ucontext.ldtc
		local solid_spark = ucontext.solid_spark
		local pt = plot.pt

		local x_cleanup = width - 4
		local input_0, input_1
		for y = 0, 3 do
			part({ type = pt.FILT, x = 0, y = y })
			local p = part({ type = pt.FILT, x = 1, y = y })
			if y == 0 then
				input_0 = p
			elseif y == 1 then
				input_1 = p
			end
		end
		part({ type = pt.FILT, x = width - 1, y = 0 })
		part({ type = pt.FILT, x = width - 1, y = 1 })
		part({ type = pt.FILT, x = width - 1, y = 2 })
		part({ type = pt.FILT, x = width - 1, y = 3 })
		part({ type = pt.FILT, x = width - 2, y = 2 })
		part({ type = pt.FILT, x = width - 2, y = 3 })
		for x = 2, width - 3 do
			part({ type = pt.FILT, x = x, y = 2, unstack = true })
			part({ type = pt.FILT, x = x, y = 3, unstack = true })
		end
		ldtc(width - 2, 0, input_0.x, input_0.y)
		ldtc(width - 2, 1, input_1.x, input_1.y)
		do
			local x_wait = 6
			ldtc(x_wait - 2, 0, input_0.x, input_0.y)
			aray(x_wait - 2, 0, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_wait - 1, y = 0 })
			part({ type = pt.STOR, x = x_wait    , y = 0 })
			part({ type = pt.FILT, x = x_wait + 1, y = 0, tmp = 7, ctype = bitx.bor(0x10080000, params.bump_address) })
			local bray_before = part({ type = pt.FILT, x = x_wait + 2, y = 0, ctype = 0x10000004 })
			part({ type = pt.FILT, x = x_wait + 5, y = -1 })
			part({ type = pt.DTEC, x = x_wait + 4, y = 0 })
			part({ type = pt.LSNS, x = x_wait + 4, y = 0, tmp = 3 })
			part({ type = pt.BRAY, x = x_wait + 3, y = -1, ctype = 0x10000003, life = 4 })
			part({ type = pt.BRAY, x = x_wait + 3, y =  4, ctype = 0x10000008, life = 10000, tmp = 1 })
			part({ type = pt.BRAY, x = x_wait + 5, y =  5, ctype = 0x0000FFFF, life = 10000, tmp = 1 })
			part({ type = pt.LSNS, x = x_wait + 4, y = 5, tmp = 3 })
			part({ type = pt.FILT, x = x_wait + 3, y = 5, ctype = 0x10001000 })
			local target_reset = part({ type = pt.CONV, x = x_wait + 4, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
			local target_0 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y     })
			local target_1 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y + 1 })
			cray(x_wait + 4, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
			cray(x_wait + 4, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
			cray(x_wait + 4, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
			cray(x_wait + 4, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
			part({ type = pt.ARAY, x = x_wait + 4, y = 8 })
			dray(x_wait + 4, 9, target_0.x, target_0.y, 1, pt.PSCN)
			dray(x_wait + 4, 9, target_1.x, target_1.y, 1, pt.PSCN)
			dray(x_cleanup, 0, bray_before.x + 1, 0, 1, pt.PSCN)
		end

		for i = 1, #parts do
			local part = parts[i]
			part.dcolour = 0xFF007F7F
			if part.type == pt.FILT then
				part.dcolour = 0xFF00FFFF
			end
		end
		ucontext.frame(1, -2, width - 2, 11, 0, 1)
		plot.merge_parts(xoff, params.bus.y, parts_out, parts)
		local interface = {
			type = "solid",
			name = "termination",
			x    = xoff,
			y    = params.bus.y - 3,
			w    = width,
			h    = 16,
		}
		table.insert(areas, interface)
		table.insert(params.bus.through_areas, interface)
	end
	return {
		parts = parts_out,
		areas = areas,
	}
end

local function param_types()
	return {
		term_x = {
			type = "lowhigh",
			low  = "term_left",
			high = "term_right",
		},
		bus = {
			type = "cpu_bus",
		},
	}
end

return {
	build       = build,
	param_types = param_types,
}
