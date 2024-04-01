local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx = require("spaghetti.bitx")
local plot = require("spaghetti.plot")

local rread = require("r3.rread.generated")
local core  = require("r3.core.generated")

local function sig_magn(x)
	local magn = math.abs(x)
	return x == 0 and 0 or (x / magn), magn
end

local function build(core_count, height_order, machine_id)
	machine_id = machine_id or 1337
	local width_order = 7
	local regs_order = 5
	assert(core_count >= 1, "core count too small")
	assert(height_order >= 4, "height order too small")
	assert(width_order >= 6, "width order too small")
	local height_order_2 = height_order + 1
	assert(width_order >= height_order_2, "bad aspect ratio")
	local addr_bits = width_order + height_order
	assert(addr_bits <= 16, "too many address bits")
	local width = bitx.lshift(1, width_order)
	local height = bitx.lshift(1, height_order)
	local ram_mask = bitx.bor(0x20000000, width * height - 1)
	local regs = bitx.lshift(1, regs_order)
	local height_order_up = width_order
	if height_order_up % 2 == 1 then
		height_order_up = height_order_up + 1
	end
	local width_order_up = width_order
	if width_order_up % 2 == 1 then
		width_order_up = width_order_up + 1
	end

	local y_filt_block = 7
	local y_ldtc_dray_bank = 10
	local y_call_sites = 18
	local core_pitch = 6

	local function per_core(func)
		for i = 1, core_count do
			local y = y_call_sites + (i - 1) * core_pitch
			func(i, y)
		end
	end

	local pt = plot.pt
	local parts = {}
	local function mutate(p, m)
		local q = {}
		for key, value in pairs(p) do
			q[key] = value
		end
		for key, value in pairs(m) do
			q[key] = value
		end
		return q
	end
	local function piston_extend(k)
		if k == math.huge then
			return 10000
		end
		return 273.15 + (k or 0) * 10
	end
	local function part(p)
		local m = {}
		if p.type == pt.PSTN then
			if not p.temp then
				m.temp = piston_extend(p.extend)
			end
			if not p.ctype then
				m.ctype = pt.INSL
			end
			if not p.tmp2 then
				m.tmp2 = 1000
			end
		end
		if p.type == pt.LSNS then
			if not p.tmp2 then
				m.tmp2 = 1
			end
		end
		if p.type == pt.DTEC then
			if not p.tmp2 then
				m.tmp2 = 1
			end
		end
		if p.type == pt.ARAY then
			if not p.life then
				m.life = 1
			end
		end
		if p.type == pt.BRAY then
			if not p.life then
				m.life = 1
			end
		end
		local q = mutate(p, m)
		table.insert(parts, q)
		return q
	end
	local function spark(p)
		return part(mutate(p, {
			ctype = p.type,
			type = pt.SPRK,
			life = p.life or 4,
		}))
	end
	local function xy_key(x, y)
		return y * sim.XRES + x
	end
	local solid_spark
	do
		local map = {}
		function solid_spark(x, y, x_off, y_off, conductor)
			local key = xy_key(x + x_off, y + y_off)
			if map[key] then
				if not (map[key].x == x and map[key].y == y and map[key].conductor == conductor) then
					error("spark conflict", 2)
				end
			else
				part ({ type = pt.CONV  , x = x        , y = y        , tmp = pt.SPRK, ctype = conductor, z = 10000000 })
				part ({ type = pt.CONV  , x = x        , y = y        , tmp = conductor, ctype = pt.SPRK, z = 10000001 })
				spark({ type = conductor, x = x + x_off, y = y + y_off })
				map[key] = {
					x = x,
					y = y,
					conductor = conductor,
				}
			end
		end
	end
	local lsns_taboo
	do
		local dmnds = {}
		function lsns_taboo(x, y)
			local key = xy_key(x, y)
			if not dmnds[key] then
				dmnds[key] = true
				part({ type = pt.DMND, x = x, y = y })
			end
		end
	end
	local lsns_spark
	do
		local lmap = {}
		local function lsns(p)
			local key = xy_key(p.x, p.y)
			if not lmap[key] then
				lmap[key] = true
				part(mutate(p, { type = pt.LSNS, tmp = 3 }))
			end
		end
		local fmap = {}
		local function filt(p, life)
			local key = xy_key(p.x, p.y)
			if not fmap[key] then
				fmap[key] = life
				part(mutate(p, { type = pt.FILT, ctype = 0x10000000 + life }))
			else
				if fmap[key] ~= life then
					error("lsns spark conflict", 3)
				end
			end
		end
		function lsns_spark(p, x_l_off, y_l_off, x_f_off, y_f_off)
			assert(p and x_l_off and y_l_off and x_f_off and y_f_off)
			spark(p)
			lsns({ x = p.x + x_l_off, y = p.y + y_l_off })
			filt({ x = p.x + x_f_off, y = p.y + y_f_off }, p.life)
		end
	end
	local function dray(x, y, x_to, y_to, count, conductor, z)
		assert(x and y and x_to and y_to and count and conductor)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.DRAY, x = x, y = y, tmp = count, tmp2 = magn - count - 1, z = z })
		solid_spark(x, y, -dx_sig, -dy_sig, conductor)
		return q
	end
	local function ldtc(x, y, x_to, y_to, z)
		assert(x and y and x_to and y_to)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.LDTC, x = x, y = y, life = magn - 1, z = z })
		return q
	end
	local function cray(x, y, x_to, y_to, ptype, count, conductor, z)
		assert(x and y and x_to and y_to and ptype and count and conductor)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.CRAY, x = x, y = y, ctype = ptype, tmp = count, tmp2 = magn - 1, z = z })
		solid_spark(x, y, -dx_sig, -dy_sig, conductor)
		return q
	end
	local function aray(x, y, x_off, y_off, conductor, z, life)
		assert(x and y and x_off and y_off and conductor)
		local q = part({ type = pt.ARAY, x = x, y = y, z = z, life = life })
		solid_spark(x, y, x_off, y_off, conductor)
		return q
	end
	local apom_order_pre = {}
	local part_injected, part_injected_patch
	do
		local y_apom_juggle = -7
		local inject_z = 0
		local per_core_info = {}
		local cray_groups = 4
		per_core(function(i)
			per_core_info[i] = {
				cray_groups = {},
			}
			for j = 1, cray_groups do
				per_core_info[i].cray_groups[j] = {}
			end
		end)
		local apom_depth_at = {}
		function part_injected(p, order, apom_depth, skip_payload, y_cleanup)
			local y_target = p.y
			per_core(function(i, y)
				if not skip_payload then
					table.insert(per_core_info[i].cray_groups[1], cray(p.x, y, p.x, y_apom_juggle, pt.BRCK, 1, pt.PSCN, 1900)) -- the 1 gets patched in part_injected_patch
					table.insert(per_core_info[i].cray_groups[2], cray(p.x, y, p.x, y_apom_juggle, pt.BRCK, 1, pt.PSCN, 1901)) -- the 1 gets patched in part_injected_patch
					table.insert(per_core_info[i].cray_groups[3], cray(p.x, y, p.x, y_apom_juggle, pt.BRCK, 1, pt.PSCN, 1902)) -- the 1 gets patched in part_injected_patch
				end
			end)
			per_core(function(i, y)
				cray(p.x, y + core_pitch, p.x, y_cleanup or p.y, pt.SPRK, 1, pt.PSCN, 2000 + inject_z)
			end)
			per_core(function(i, y)
				if not skip_payload then
					part(mutate(p, { y = y - 1 }))
				end
				if not skip_payload then
					table.insert(per_core_info[i].cray_groups[4], cray(p.x, y, p.x, y_apom_juggle, pt.BRCK, 1, pt.PSCN, 2100)) -- the 1 gets patched in part_injected_patch
				end
				dray(p.x, y, p.x, p.y, 1, pt.PSCN, 3000 + inject_z)
			end)
			inject_z = inject_z + 1
			apom_depth_at[p.x] = (apom_depth_at[p.x] or 0) + 1
			table.insert(apom_order_pre, {
				x        = p.x,
				order    = order,
				inject_z = inject_z,
			})
		end
		function part_injected_patch()
			local insls = {}
			local function add_insl(x, y)
				if not insls[xy_key(x, y)] then
					insls[xy_key(x, y)] = true
					part({ type = pt.INSL, x = x, y = y })
				end
			end
			local function patch_crays(crays)
				local clone = {}
				for _, cray in ipairs(crays) do
					table.insert(clone, cray)
				end
				table.sort(clone, function(lhs, rhs)
					if lhs.x ~= rhs.x then return lhs.x < rhs.x end
					return false
				end)
				local apom_depth = 0
				for i = #clone, 1, -1 do
					apom_depth = apom_depth + apom_depth_at[clone[i].x]
					clone[i].tmp = apom_depth
					clone[i].tmp2 = clone[i].tmp2 - apom_depth
					add_insl(clone[i].x, clone[i].y - clone[i].tmp2)
					add_insl(clone[i].x, clone[i].y - clone[i].tmp2 - apom_depth - 1)
				end
			end
			per_core(function(i)
				for j = 1, cray_groups do
					patch_crays(per_core_info[i].cray_groups[j])
				end
			end)
		end
	end

	-- block of filt
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local addr = y * width + x
			table.insert(parts, { type = pt.FILT, x = x, y = y_filt_block - height + y + 1, ctype = 0x2000DEAD })
		end
	end

	for y = 0, height - 1 do
		local dist = y + y_ldtc_dray_bank - y_filt_block
		-- active reader head template
		part({ type = pt.LDTC, x = y * 2    , y = y_ldtc_dray_bank    , life = dist + 2 })
		part({ type = pt.FILT, x = y * 2    , y = y_ldtc_dray_bank + 1 })
		-- active writer head template
		part ({ type = pt.DRAY, x = y * 2 + 1, y = y_ldtc_dray_bank    , tmp = 1, tmp2 = dist + 1 })
		spark({ type = pt.PSCN, x = y * 2 + 1, y = y_ldtc_dray_bank + 1, life = 3 }) -- spark for the above
	end
	-- active head second row template
	local x_ah_sr_template = -10 - height_order_up - width_order_up
	lsns_spark({ type = pt.PSCN, x = x_ah_sr_template, y = y_ldtc_dray_bank + 1, life = 3 }, -1, -1, -1, 0)
	dray(x_ah_sr_template - 2, y_ldtc_dray_bank + 1, 0, y_ldtc_dray_bank + 1, 2, pt.PSCN)
	-- logarithmically clone active head second row template
	for i = 1, height_order do
		local w = bitx.lshift(1, i)
		dray(-1, y_ldtc_dray_bank + 1, w, y_ldtc_dray_bank + 1, w, pt.PSCN)
	end

	-- line of filt to be dray'd into the filt block above
	for x = -2, width - 1 do
		part({ type = pt.FILT, x = x, y = y_ldtc_dray_bank + 2 })
	end

	-- memory read value in write cycles
	part({ type = pt.FILT, x = width + 1, y = y_ldtc_dray_bank + 4, ctype = 0xFFFFFFFF })

	local x_core = 40
	local function x_storage_slot(k)
		return x_core + 2 + k
	end

	-- input and output
	local x_ram_inject = -27
	local x_io = 135
	local x_ram_data_up = x_storage_slot(64)
	per_core(function(i, y)
		local function filt_line_to(x, y)
			local qs = {}
			for xx = x, x_io do
				table.insert(qs, part({ type = pt.FILT, x = xx, y = y }))
			end
			return qs
		end
		filt_line_to(x_io, y - 3)
		filt_line_to(x_io, y - 2)
		filt_line_to(x_io - 4, y)
		local qs_io_state = filt_line_to(x_io - 7, y - 1)
		local x_default_io = x_io - 13
		part({ type = pt.FILT, x = x_default_io, y = y - 1, ctype = 0x10000000 }) -- default io state
		ldtc(x_io - 8, y - 1, x_default_io, y - 1)
		ldtc(x_io - 1, y - 3, x_io - 4, y - 3)
		ldtc(x_io - 1, y - 2, x_ram_data_up + 2, y - 2)
		part({ type = pt.FILT, x = x_ram_data_up + 2, y = y + 4 })

		local x_io_state = x_storage_slot(86)
		ldtc(x_io_state, y + 1, x_io_state, y - 1)
		part({ type = pt.FILT, x = x_io_state, y = y + 2 })
		part({ type = pt.FILT, x = x_io - 4, y = y - 2, ctype = 0x00000008 })
		qs_io_state[4].tmp = 1
		if i ~= 1 then
			cray(98, y - 4, x_io - 4, y - 4, pt.METL, 1, pt.PSCN)
			cray(98, y - 4, x_io - 4, y - 4, pt.METL, 1, pt.PSCN)
			local sprk = cray(114, y - 4, x_io - 4, y - 4, pt.SPRK, 1, pt.INWR)
			sprk.life = 3
			part({ type = pt.SPRK, x = x_io - 4, y = y - 4, life = 3, ctype = pt.METL })
		end
		part({ type = pt.INSL, x = x_io - 4, y = y + 1 }) -- id donor
		dray(x_io - 3, y + 1, x_ram_inject, y + 1, 1, pt.PSCN)

		part({ type = pt.DTEC, x = x_ram_inject, y = y + 2 })
		part({ type = pt.CONV, x = x_ram_inject, y = y + 2, tmp = pt.BRAY, ctype = pt.INSL }) -- hide bray so it doesn't interfere with dtecs
		local x_fix_core_left13 = x_io - 3
		ldtc(x_ram_inject, y + 3, x_fix_core_left13, y + 3)
		part({ type = pt.FILT, x = x_fix_core_left13, y = y + 3, ctype = 0x10000003 })
	end)
	part({ type = pt.INSL, x = x_io - 4, y = y_call_sites + core_count * core_pitch - 4 })
	lsns_spark({ type = pt.METL, x = x_io - 4, y = y_call_sites - 4, life = 3 }, 0, -1, 0, -2)
	per_core(function(i, y)
		local y_io_apom_float = y_call_sites - 8
		local y_io_apom_reset = y_call_sites + core_count * core_pitch
		local y_ram_inject_cleanup = y_call_sites + core_count * core_pitch + 2
		cray(x_io - 4, y_io_apom_float, x_io - 4, y - 3 + 4, pt.SPRK, 1, pt.PSCN)
		cray(x_io - 4, y_io_apom_float, x_io - 4, y - 3, pt.ARAY, 1, pt.PSCN)
		dray(x_io - 4, y_io_apom_reset, x_io - 4, y - 3 + 4, 1, pt.PSCN)
		cray(x_io - 4, y_io_apom_reset, x_io - 4, y - 3, pt.SPRK, 1, pt.PSCN)
		cray(x_io - 4, y_io_apom_reset, x_io - 4, y - 3 + 4, pt.INSL, 1, pt.PSCN)
		dray(x_ram_inject, y_ram_inject_cleanup, x_ram_inject, y + 1, 1, pt.PSCN)
	end)

	-- bank piston frame
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank - 2 })
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank - 1 })
	-- bank piston
	local x_bank_piston = -3 - height_order_up
	part_injected({ type = pt.PSTN, x = x_bank_piston    , y = y_ldtc_dray_bank - 1, extend = 2 }, 0, 11) -- extend to the programmed distance
	lsns_spark   ({ type = pt.PSCN, x = x_bank_piston    , y = y_ldtc_dray_bank    , life = 3 }, -1, 1, 0, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = x_bank_piston - 1, y = y_ldtc_dray_bank - 1 }) -- filler
	part_injected({ type = pt.PSTN, x = x_bank_piston - 2, y = y_ldtc_dray_bank - 1, extend = math.huge }, 3, 10) -- retract fully
	lsns_spark   ({ type = pt.NSCN, x = x_bank_piston - 2, y = y_ldtc_dray_bank    , life = 3 }, 1, 1, 2, 1) -- spark for the above
	part         ({ type = pt.INSL, x = x_bank_piston - 3, y = y_ldtc_dray_bank - 1 }) -- left cap
	part         ({ type = pt.INSL, x = height * 2       , y = y_ldtc_dray_bank - 1 }) -- right cap
	for i = height_order_2 + 1, height_order_up do
		part({ type = pt.PSTN, x = -2 - i, y = y_ldtc_dray_bank - 1 }) -- filler
	end

	-- particles to be overwritten by address piston drays
	part({ type = pt.INSL, x = -3, y = y_ldtc_dray_bank })
	part({ type = pt.INSL, x = x_bank_piston    , y = y_ldtc_dray_bank + 4 })
	part({ type = pt.INSL, x = x_bank_piston - 2, y = y_ldtc_dray_bank + 4 })
	part({ type = pt.INSL, x = x_bank_piston - 4, y = y_ldtc_dray_bank + 4 })
	per_core(function(i, y)
		part({ type = pt.INSL, x = x_bank_piston    , y = y - (i == 1 and 3 or 4) })
		part({ type = pt.INSL, x = x_bank_piston - 2, y = y - (i == 1 and 3 or 4) })
	end)

	-- active head piston frame
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank + 3 })
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank + 4 })
	-- active head piston
	local x_ah_piston = -3 - height_order_up - width_order_up
	part_injected({ type = pt.PSTN, x = x_ah_piston    , y = y_ldtc_dray_bank + 3, extend = 1 }, 5, 9) -- retract to the programmed distance
	lsns_spark   ({ type = pt.NSCN, x = x_ah_piston    , y = y_ldtc_dray_bank + 4, life = 3 }, -1, 1, -2, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = x_ah_piston - 1, y = y_ldtc_dray_bank + 3 }) -- filler
	part_injected({ type = pt.PSTN, x = x_ah_piston - 2, y = y_ldtc_dray_bank + 3, extend = math.huge }, 4, 8) -- extend fully
	lsns_spark   ({ type = pt.PSCN, x = x_ah_piston - 2, y = y_ldtc_dray_bank + 4, life = 3 }, 1, 1, 0, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = x_ah_piston - 3, y = y_ldtc_dray_bank + 3 }) -- filler
	part_injected({ type = pt.PSTN, x = x_ah_piston - 4, y = y_ldtc_dray_bank + 3, extend = math.huge }, 9, 7) -- retract fully
	lsns_spark   ({ type = pt.NSCN, x = x_ah_piston - 4, y = y_ldtc_dray_bank + 4, life = 3 }, 1, 1, 2, 1) -- spark for the above
	part         ({ type = pt.INSL, x = x_ah_piston - 5, y = y_ldtc_dray_bank + 3 }) -- left cap
	part         ({ type = pt.INSL, x = width          , y = y_ldtc_dray_bank + 3 }) -- right cap
	for i = 1, height_order_2 do
		part({ type = pt.PSTN, x = -2 - i, y = y_ldtc_dray_bank + 3 }) -- filler
	end
	for i = height_order_2 + 1, height_order_up do
		part({ type = pt.PSTN, x = -2 - i - width_order, y = y_ldtc_dray_bank + 3 }) -- filler
	end
	for i = width_order + 1, width_order_up do
		part({ type = pt.PSTN, x = -2 - i - height_order_up, y = y_ldtc_dray_bank + 3 }) -- filler
	end

	-- reset active head to cray(sprk)'able particles
	per_core(function(i, y)
		dray(-1, y + core_pitch, -1, y_ldtc_dray_bank + 3, 1, pt.PSCN, 900)
		dray(-1, y + core_pitch, -1, y_ldtc_dray_bank + 4, 1, pt.PSCN, 901)
		if i == core_count then
			part({ type = pt.INSL, x = -1, y = y - 1 + core_pitch })
		end
	end)
	-- copy active head
	local active_head_copier = { type = pt.DRAY, x = -1, y = y_ldtc_dray_bank - 1, tmp = 2, tmp2 = 1 }
	part_injected(mutate(active_head_copier, { y = y_ldtc_dray_bank - 10 }), 1, 6, true)
	lsns_spark   ({ type = pt.PSCN, x = -1, y = y_ldtc_dray_bank - 11, life = 3 }, -1, 0, -1, -1) -- spark for the above
	-- active head copier
	part_injected(active_head_copier, 2, 5)
	lsns_spark   ({ type = pt.PSCN, x = -1, y = y_ldtc_dray_bank - 2, life = 3 }, -1, -1, -2, -1) -- spark for the above
	-- active head placeholders
	part_injected(mutate(active_head_copier, { y = y_ldtc_dray_bank - 6 }), 7, 4, true, y_ldtc_dray_bank + 4)
	part_injected(mutate(active_head_copier, { y = y_ldtc_dray_bank - 5 }), 8, 3, true, y_ldtc_dray_bank + 3)

	-- get ctype into the line of filt above the active head
	part_injected({ type = pt.LDTC, x = -3, y = y_ldtc_dray_bank + 2 }, 6, 2)
	do
		local x = -7 - height_order_up
		part({ type = pt.FILT, x = x, y = y_ldtc_dray_bank + 2, ctype = 0x10000000 })
		per_core(function(i, y)
			part({ type = pt.FILT, x = x, y = y - 1 })
			dray(x, y, x, y_ldtc_dray_bank + 2, 1, pt.PSCN)
			part({ type = pt.FILT, x = x_ram_data_up + 3, y = y + 5, tmp2 = 2 })
			dray(x_ram_data_up + 4, y - 1, x, y - 1, 1, pt.PSCN)
		end)
	end

	-- get ctype from active head
	local x_get_ctype = -10 - width_order_up - height_order_up
	part         ({ type = pt.FILT, x = x_get_ctype    , y = y_ldtc_dray_bank + 4 })
	part_injected({ type = pt.LDTC, x = x_get_ctype + 1, y = y_ldtc_dray_bank + 4, life = -3 - x_get_ctype }, 10, 1)
	per_core(function(i, y)
		part({ type = pt.FILT, x = x_get_ctype, y = y + 2 })
		ldtc(x_get_ctype, y + 1, x_get_ctype, y_ldtc_dray_bank + 4)
	end)

	part_injected_patch()
	table.sort(apom_order_pre, function(lhs, rhs)
		if lhs.x        ~= rhs.x        then return lhs.x        < rhs.x        end
		if lhs.inject_z ~= rhs.inject_z then return lhs.inject_z < rhs.inject_z end
		return false
	end)
	local apom_order = {}
	for i = 1, #apom_order_pre do
		table.insert(apom_order, apom_order_pre[i].order)
	end

	local x_apom_parts = 118
	for j = 1, #apom_order do
		apom_order[j] = apom_order[j] + x_apom_parts
	end
	-- float apom'd particles
	per_core(function(i, y)
		for j = #apom_order, 1, -1 do
			part({ type = pt.BRCK, x = apom_order[j], y = y })
			cray(-11 - height_order_up - width_order_up, y, apom_order[j], y, pt.BRCK, 1, pt.PSCN)
		end
	end)
	-- restore apom'd particles
	local y_restore = core_count * core_pitch + y_call_sites + 1
	per_core(function(i, y)
		for j = #apom_order, 1, -1 do
			local x = apom_order[j]
			cray(2, y + core_pitch, x, y + core_pitch, pt.BRCK, 1, pt.PSCN)
			cray(x, y_restore + x % 2, x, y + core_pitch, pt.BRCK, 1, pt.PSCN)
			cray(x, y_restore + x % 2, x, y             , pt.BRCK, 1, pt.PSCN)
		end
	end)

	-- ram piston demuxer
	for i = 1, height_order_2 do
		part({ type = pt.BRCK, x = -2 - i, y = y_ldtc_dray_bank - 1 })
	end
	for i = 1, width_order do
		part({ type = pt.BRCK, x = -2 - i - height_order_2, y = y_ldtc_dray_bank + 3 })
	end
	local x_stack = 1
	local x_take_addr = -13 - height_order_up - width_order_up
	local reclaimed_voids = { 30, 31, 32, 59, 60, 61, 75 }
	per_core(function(i, y)
		for j = 0, height_order_2 - 1 do
			local x = -3 - j
			local stagger = x % 2
			part({ type = pt.INSL, x = x, y = y - 2 })
			dray(x, y - 1 + stagger, x, y_ldtc_dray_bank - 1 + stagger, 1 + stagger, pt.PSCN)
		end
		for j = 0, width_order - 1 do
			local x = -3 - j - height_order_2
			local stagger = x % 2
			part({ type = pt.INSL, x = x, y = y - 2 })
			dray(x, y - 1 + stagger, x, y_ldtc_dray_bank + 3 + stagger, 1 + stagger, pt.PSCN)
		end

		local x_filt_bank = x_stack + 2
		local function change_conductor(conductor)
			part({ type = pt.CONV, x = x_stack, y = y - 2, ctype = conductor, tmp = pt.SPRK })
			part({ type = pt.CONV, x = x_stack, y = y - 2, ctype = pt.SPRK, tmp = conductor })
			part({ type = pt.LSNS, x = x_stack, y = y - 2, tmp = 3 })
			lsns_taboo(x_stack + 1, y - 1)
		end

		spark({ type = pt.METL, x = x_stack + 1, y = y - 2 })
		part ({ type = pt.FILT, x = x_stack - 1, y = y - 2, ctype = 0x10000003 })
		part ({ type = pt.STOR, x = x_stack - 2, y = y - 2 })
		part ({ type = pt.FILT, x = x_stack - 3, y = y - 2, tmp = 1 })

		part({ type = pt.FILT, x = x_filt_bank, y = y - 2, ctype = 0x10000003 })
		local filt_offsets = {}
		local add_bit
		do
			local seen = 0
			function add_bit(k)
				part({ type = pt.FILT, x = x_filt_bank + seen + 1, y = y - 2, ctype = bitx.lshift(1, k) })
				filt_offsets[k] = seen
				seen = seen + 1
			end
		end
		for i = 0, width_order + height_order - 1 do
			add_bit(i)
		end
		add_bit(16)

		-- important: the ids of the pistons here never change, they get allocated from the same set every time
		change_conductor(pt.PSCN)
		part({ type = pt.CRAY, x = x_stack, y = y - 2, tmp = width_order + height_order_2    , tmp2 = 3, ctype = pt.SPRK })
		part({ type = pt.CRAY, x = x_stack, y = y - 2, tmp = width_order + height_order_2 - 1, tmp2 = 3, ctype = pt.STOR })
		change_conductor(pt.METL)
		local function handle_bit(address_index, piston_bit, piston_index, last, invert)
			part({ type = pt.LDTC, x = x_stack, y = y - 2, life = x_filt_bank - x_stack + filt_offsets[address_index] })
			part({ type = pt.ARAY, x = x_stack, y = y - 2 })
			part({ type = pt.LDTC, x = x_stack, y = y - 2, life = x_filt_bank - x_stack - 1 })
			change_conductor(pt.PSCN)
			local extend_if_set = piston_extend(bitx.lshift(1, piston_bit))
			local extend_if_clear = piston_extend(0)
			if invert then
				extend_if_clear, extend_if_set = extend_if_set, extend_if_clear
			end
			if last then
				part({ type = pt.CRAY, x = x_stack, y = y - 2, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = extend_if_clear })
			else
				part({ type = pt.CRAY, x = x_stack, y = y - 2, tmp = 2, tmp2 = 2 + piston_index, ctype = pt.PSTN, temp = extend_if_clear })
			end
			change_conductor(pt.METL)
			part({ type = pt.CRAY, x = x_stack, y = y - 2, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = extend_if_set })
		end
		for i = 0, width_order - 1 do
			handle_bit(i, i, width_order + height_order_2 - 1 - i, false, true)
		end
		for i = 0, height_order - 1 do
			handle_bit(i + width_order, i + 1, height_order_2 - 1 - i, false, true)
		end
		handle_bit(16, 0, 0, true, false)

		local pistons = width_order + height_order_2
		cray(x_stack - 4 - pistons, y - 2, x_stack - 3 - pistons, y - 2, pt.INSL, pistons, pt.PSCN)
		cray(x_stack - 4 - pistons, y - 2, x_stack - 3 - pistons, y - 2, pt.INSL, pistons, pt.PSCN)

		local fix_lsns_x = 119
		part({ type = pt.BRCK, x = fix_lsns_x - 1, y = y + 3 })
		for _, index in ipairs(reclaimed_voids) do
			dray(fix_lsns_x, y + 3, x_storage_slot(index), y + 3, 1, pt.PSCN) -- reclaim voids
		end
		if i ~= 1 then
			dray(fix_lsns_x, y - 3, x_stack, y - 3, 1, pt.PSCN) -- fix lsns in S neighbour stack being confused by this filt
			dray(fix_lsns_x, y - 3, x_stack - 2, y - 3, 1, pt.PSCN) -- fix template ltdc clobbering register 19 through this filt
			dray(fix_lsns_x, y - 3, -25, y - 3, 1, pt.PSCN) -- fix dtec in SW neighbour stack clobbering register 31
		end
	end)

	-- forward ram addr
	per_core(function(i, y)
		aray(x_take_addr, y - 2, 0, 1, pt.METL)
		part({ type = pt.BRAY, x = x_take_addr    , y = y - 4 })
		part({ type = pt.INSL, x = x_take_addr    , y = y - 5 })
		part({ type = pt.INSL, x = x_take_addr - 1, y = y - 2 })
		part({ type = pt.DTEC, x = x_take_addr + 3, y = y - 2, tmp2 = 3 })
		part({ type = pt.FILT, x = x_take_addr + 4, y = y - 2, tmp = 1 })
		dray(x_take_addr + 3, y - 2, x_stack - 3, y - 2, 1, pt.PSCN)
		dray(129, y - 3, x_take_addr, y - 3, 1, pt.PSCN)
		dray(x_take_addr, y_call_sites + core_pitch * core_count, x_take_addr, y - 3, 1, pt.PSCN) -- cleanup
	end)

	-- registers
	local x_registers = 38
	per_core(function(i, y)
		local y_registers = y + 2
		for j = 1, regs - 1 do
			part({ type = pt.FILT, x = x_registers - j * 2, y = y_registers, ctype = 0x20000000 + j })
		end
		if i ~= 1 then
			for j = 1, regs - 1 do
				ldtc(x_registers - j * 2, y_registers - 1, x_registers - j * 2, y_registers - core_pitch)
			end
		end
	end)
	for j = 1, regs - 1 do
		local y_last_registers = y_call_sites + core_count * core_pitch + 2
		local y_bottom_rep = y_call_sites + core_pitch * core_count + 1
		part({ type = pt.FILT, x = x_registers - j * 2, y = y_bottom_rep, ctype = 0x20000000 + j })
		ldtc(x_registers - j * 2, y_bottom_rep - 1, x_registers - j * 2, y_last_registers - core_pitch)
		dray(x_registers - j * 2, y_bottom_rep + 1, x_registers - j * 2, y_call_sites + 2, 1, pt.PSCN)
	end

	-- r0 bray source
	do
		local zero_ctype = 0x20000000
		local zero_life = 1000
		local y_bottom_rep = y_call_sites + core_pitch * core_count + 1
		aray(x_registers + 2, y_bottom_rep, 1, 0, pt.METL, nil, zero_life)
		part({ type = pt.FILT, x = x_registers + 1, y = y_bottom_rep, ctype = zero_ctype })
		part({ type = pt.BRAY, x = x_registers    , y = y_bottom_rep, ctype = zero_ctype, life = zero_life })
		part({ type = pt.DMND, x = x_registers - 1, y = y_bottom_rep })
		per_core(function(i, y)
			dray(x_registers, y_bottom_rep + 1, x_registers, y + 2, 1, pt.PSCN)
			part({ type = pt.BRAY, x = x_registers, y = y + 2, ctype = zero_ctype, life = zero_life })
		end)
	end

	-- last core ram addr and data repeaters
	do
		local function repeater(x, y, count)
			for j = 0, count - 1 do
				part({ type = pt.FILT, x = x, y = y - j })
			end
			dray(x, y + core_pitch * core_count + 1, x, y, count, pt.PSCN)
		end
		repeater(x_ram_data_up + 2, y_call_sites - 2, 1)
		repeater(x_ram_data_up + 3, y_call_sites - 1, 1)
		repeater(x_storage_slot(86), y_call_sites - 3, 1)
	end

	-- register readers
	per_core(function(i, y)
		local x_reader = 73
		local x_reader_storage = x_reader + 2
		local y_reader = y + 2
		ldtc(x_reader_storage - 1, y, x_reader_storage - core_pitch + 2, y - core_pitch + 3)
		part({ type = pt.FILT, x = x_reader_storage, y = y + 1 }) -- conduit for the above
		ldtc(x_reader_storage + 18, y, x_reader_storage - core_pitch + 21, y - core_pitch + 3)
		part({ type = pt.FILT, x = x_reader_storage + 17, y = y + 1 }) -- conduit for the above
		plot.merge_parts(x_reader, y + 2, parts, rread)
		dray(x_get_ctype - 1, y + 2, x_reader_storage + 2, y + 2, 1, pt.PSCN)

		part({ type = pt.INSL, x = x_reader + 52, y = y_reader })
		part({ type = pt.DTEC, x = x_reader + 38, y = y_reader })
		part({ type = pt.BRAY, x = x_reader + 37, y = y_reader })
		part({ type = pt.FILT, x = x_reader + 36, y = y_reader })
		dray(x_get_ctype - 1, y + 2, x_reader + 36, y + 2, 1, pt.PSCN)
		local function reader(stage_1_offset, storage_slot)
			local x_stage_1 = x_reader + stage_1_offset
			ldtc(x_stage_1 - 3, y_reader, x_reader_storage + storage_slot, y_reader)
			part({ type = pt.FILT, x = x_stage_1 - 2, y = y_reader })
			part({ type = pt.LSNS, x = x_stage_1 - 1, y = y_reader, tmp = 3 })
			lsns_taboo(x_stage_1 - 1, y_reader - 1)
			lsns_taboo(x_stage_1    , y_reader - 1)
			part({ type = pt.LDTC, x = x_stage_1    , y = y_reader })
			part({ type = pt.FILT, x = x_stage_1 + 1, y = y_reader })
			part({ type = pt.LDTC, life = 1, x = x_stage_1 + 3, y = y_reader })
			part({ type = pt.ARAY, x = x_stage_1 + 3, y = y_reader })
			part({ type = pt.DTEC, x = x_stage_1 + 3, y = y_reader, tmp2 = 2 })
			solid_spark(x_stage_1 + 3, y_reader, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_stage_1 + 4, y = y_reader })
			part({ type = pt.BRAY, x = x_stage_1 + 5, y = y_reader })
		end
		reader(30, 1)
		reader(46, 2)
	end)

	-- cores
	local vertical_inputs = {}
	local function vertical_input(index, repeater, y_source)
		table.insert(vertical_inputs, {
			index    = index,
			repeater = repeater,
			y_source = y_source,
		})
	end
	vertical_input(10,  true, 0)
	vertical_input(14,  true, 0)
	vertical_input(16,  true, 0)
	vertical_input(29, false, 3)
	vertical_input(54,  true, 3)
	vertical_input(62, false, 0)
	vertical_input( 7, false, 0)
	per_core(function(i, y)
		for _, info in ipairs(vertical_inputs) do
			if info.repeater then
				local x = x_storage_slot(info.index)
				ldtc(x, y, x, y - core_pitch + 3)
				part({ type = pt.FILT, x = x, y = y + 1 })
			end
		end
		plot.merge_parts(x_core - 2, y + 3, parts, core)
	end)
	for _, info in ipairs(vertical_inputs) do
		local x = x_storage_slot(info.index)
		local y = y_call_sites - 3
		part({ type = pt.FILT, x = x, y = y })
		ldtc(x, y + 1, x, y + core_pitch * core_count + info.y_source)
	end

	-- register writers
	per_core(function(i, y)
		local x_bank_dray = 45
		local x_stack = x_bank_dray + regs + 9
		local y_stack = y
		local x_filt_bank = x_stack + 20
		local function change_conductor(conductor)
			part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = pt.SPRK })
			part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
			part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3 })
			lsns_taboo(x_stack + 1, y_stack + 1)
		end

		part({ type = pt.PSTN, x = x_stack - 1, y = y_stack, extend = 1 })
		part({ type = pt.PSTN, x = x_stack - 2, y = y_stack, extend = 1 })
		part({ type = pt.PSTN, x = x_stack - 3, y = y_stack, extend = 1 })
		part({ type = pt.PSTN, x = x_stack - 4 - regs_order, y = y_stack })

		ldtc(x_bank_dray + 1, y_stack, x_bank_dray - 2, y_stack - 3) -- set register template
		part({ type = pt.FILT, x = x_bank_dray, y = y_stack + 1 }) -- conduit
		part({ type = pt.FILT, x = x_bank_dray - 1, y = y_stack + 2 }) -- register template

		local x_filt13 = x_filt_bank + 7
		part({ type = pt.FILT, x = x_filt13, y = y_stack, ctype = 0x10000003 })
		ldtc(x_filt_bank, y_stack - 1, x_filt_bank - 2, y_stack - 3)
		part({ type = pt.FILT, x = x_filt_bank + 1, y = y_stack })
		local filt_offsets = {}
		local add_bit
		do
			local seen = 0
			function add_bit(k)
				local x_seen = seen
				if k == 2 then
					x_seen = 6 -- so it doesn't get clobbered by the core's pri_reg input
				end
				part({ type = pt.FILT, x = x_filt_bank + x_seen + 2, y = y_stack, ctype = bitx.lshift(1, k) })
				filt_offsets[k] = x_seen
				seen = seen + 1
			end
		end
		for i = 0, regs_order - 1 do
			add_bit(i)
		end

		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 3, ctype = pt.SPRK })
		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 3, ctype = pt.FILT, ctype_high = 1 })
		ldtc(x_stack, y_stack, x_filt_bank + 1, y_stack)
		part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.STOR, tmp = pt.FILT })
		part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 1 })
		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, ctype = pt.SPRK })
		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, ctype = pt.FILT })
		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = regs_order, tmp2 = 3, ctype = pt.SPRK })
		part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = regs_order - 1, tmp2 = 3, ctype = pt.STOR })
		ldtc(x_stack, y_stack, x_filt13, y_stack)
		change_conductor(pt.METL)
		local function handle_bit(address_index, piston_bit, piston_index, last)
			part({ type = pt.INSL, x = x_stack - 4 - piston_index, y = y_stack })
			ldtc(x_stack, y_stack, x_filt_bank + 2 + filt_offsets[address_index], y_stack)
			part({ type = pt.ARAY, x = x_stack, y = y_stack })
			ldtc(x_stack, y_stack, x_filt13, y_stack)
			change_conductor(pt.PSCN)
			if last then
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = piston_extend(0) })
			else
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 2 + piston_index, ctype = pt.PSTN, temp = piston_extend(0) })
			end
			change_conductor(pt.METL)
			part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = piston_extend(bitx.lshift(1, piston_bit)) })
		end
		for j = 0, regs_order - 1 do
			handle_bit(j, j, regs_order - j - 1, j == regs_order - 1)
		end
		change_conductor(pt.PSCN)
		part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.PSTN, tmp = pt.FILT })
		part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 1 })
		part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 1 })
		part({ type = pt.PSTN, x = x_stack, y = y_stack, tmp = 1000 }) -- relies on the extension length of the dummy pstn on top
		part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.PSTN, tmp = pt.SPRK })
		for j = 0, regs - 1 do
			local q = { type = pt.BRCK, x = x_stack - 9 - regs + j, y = y_stack }
			if j ~= 0 then
				q.type = pt.DRAY
				q.tmp = 1
				q.tmp2 = j * 2 + x_bank_dray - x_registers - 2
			end
			part(q)
		end

		part({ type = pt.PSTN, x = x_stack, y = y_stack }) -- stack top placeholder
		part({ type = pt.PSTN, x = x_stack + 1, y = y_stack }) -- stack spark placeholder
		solid_spark(x_stack - 11 - 2 * regs, y_stack + 1, 1, -1, pt.PSCN) -- marks end of travel and provides the spark for the stack
		part({ type = pt.PSTN, x = x_stack - 11 - 2 * regs, y = y_stack, extend = -2 }) -- dummy pstn, this is what the active pstn in the stack relies on
		dray(x_stack - 12 - 2 * regs, y_stack, x_stack, y_stack, 2, pt.PSCN) -- replace placeholder with insl so the stack can make it work

		local x_retract = x_stack + 10
		part({ type = pt.PSTN, x = x_retract, y = y_stack, extend = math.huge, tmp = 1000 })
		solid_spark(x_retract - 1, y_stack + 1, 1, 0, pt.NSCN)
		for j = x_stack + 2, x_retract - 1 do
			part({ type = pt.PSTN, x = j, y = y_stack })
		end

		local x_bank_dray_donor = x_retract - 3
		cray(x_bank_dray_donor, y_stack - 1, x_bank_dray_donor, y_stack, pt.SPRK, 1, pt.PSCN) -- float bank dray's id before its update
		cray(x_stack - 12 - 2 * regs, y_stack, x_bank_dray_donor, y_stack, pt.PSTN, 1, pt.PSCN) -- spawn a dummy piston in its place
		cray(x_bank_dray_donor + 10, y_stack, x_bank_dray_donor, y_stack, pt.SPRK, 1, pt.PSCN) -- remove dummy piston from its place
		cray(x_bank_dray_donor, y_stack + 1, x_bank_dray_donor, y_stack, pt.PSTN, 1, pt.PSCN) -- restore bank dray's id after its update
		dray(x_bank_dray_donor + 3, y_stack - 1, x_bank_dray, y_stack - 1, 1, pt.PSCN) -- restore bank dray's id before its update
		part({ type = pt.DRAY, x = x_bank_dray_donor + 2, y = y_stack - 1, tmp = 1, tmp2 = 1 }) -- bank dray template
		cray(x_bank_dray - 2, y_stack + 1, x_bank_dray, y_stack - 1, pt.SPRK, 1, pt.PSCN) -- float bank dray's id after its update

		lsns_spark({ type = pt.PSCN, x = x_bank_dray, y = y_stack - 2, life = 3 }, -1, 1, -2, 1)
		lsns_taboo(x_bank_dray + 2, y_stack - 1)

		part({ type = pt.INSL, x = x_bank_dray, y = y_stack + 2 }) -- bank dray placeholder
		solid_spark(x_bank_dray + 2, y_stack + 2, -1, 0, pt.PSCN)
	end)

	-- tptasm anchor
	do
		local x_anchor = 41
		local y_anchor = y_call_sites + core_count * core_pitch + 3
		part({ x = x_anchor - 1, y = y_anchor, type = pt.FILT, ctype = machine_id })
		part({ x = x_anchor    , y = y_anchor, type = pt.QRTZ, ctype = 0x1864A205, tmp2 = 0x201 }) -- data in ctype, dx = 1, dy = 0
		local checksum = 0
		local x_push = x_anchor + 1
		local function push(value)
			part({ x = x_push, y = y_anchor, type = pt.FILT, ctype = value })
			checksum = checksum + value
			x_push = x_push + 1
		end
		local model_name = ("R3A%s%02i"):format(string.char(addr_bits + 64), core_count)
		for ch in model_name:gmatch(".") do
			push(ch:byte())
		end
		push(0)
		push(checksum)
	end

	do -- frame
		local x1 = -15 - height_order_up - width_order_up
		local x2 = width + 6
		local y1 = y_filt_block - height
		local y2 = y_call_sites + core_count * core_pitch + 4
		local x_buttons = 76
		local function button(p, x)
			for yy = 0, 3 do
				for xx = 0, 7 do
					if not (yy == 0 and (xx == 0 or xx == 7)) then
						part(mutate(p, { x = x + xx, y = y2 - 2 + yy }))
					end
				end
			end
		end
		local x_button_reset = x_buttons - 25
		local x_button_stop  = x_buttons - 14
		local x_button_start = x_buttons -  3
		local x_running      = x_buttons + 22
		button({ type = pt.INST, dcolour = 0xFF7F7F7F }, x_button_reset)
		button({ type = pt.INST, dcolour = 0xFF7F7F7F }, x_button_stop )
		button({ type = pt.INST, dcolour = 0xFF7F7F7F }, x_button_start)
		button({ type = pt.LCRY, dcolour = 0xFF00FF00 }, x_running     )

		do
			local x_source = x_storage_slot(10)
			local x_target = x_running + 3
			local y_indicator = y_call_sites + (core_count - 1) * core_pitch + 6
			ldtc(x_source, y_indicator - 1, x_source, y_call_sites + core_count * core_pitch - 3)
			part({ type = pt.FILT, x = x_source    , y = y_indicator })
			part({ type = pt.STOR, x = x_source - 1, y = y_indicator })
			part({ type = pt.FILT, x = x_source - 2, y = y_indicator, tmp = 1, ctype = 0x00000008 })
			part({ type = pt.NSCN, x = x_source - 3, y = y_indicator })
			part({ type = pt.INSL, x = x_source - 4, y = y_indicator })
			aray(x_source + 1, y_indicator, 1, 0, pt.METL)

			local sprk = cray(x_source - 8, y_indicator, x_source - 3, y_indicator, pt.SPRK, 1, pt.INWR)
			sprk.life = 3
			dray(x_source - 5, y_indicator, x_target, y_indicator, 2, pt.PSCN)
			cray(x_source - 5, y_indicator, x_source - 3, y_indicator, pt.SPRK, 1, pt.PSCN)
			part({ type = pt.LCRY, x = x_target + 1, y = y_indicator + 1, dcolour = 0xFF000000 })

			cray(x_source +  7, y_indicator, x_source - 3, y_indicator, pt.PSCN, 1, pt.PSCN)
			cray(x_source + 10, y_indicator, x_source - 3, y_indicator, pt.NSCN, 1, pt.METL)

			part({ type = pt.INSL, x = x_target    , y = y_indicator })
			part({ type = pt.INSL, x = x_target + 1, y = y_indicator })
		end

		do
			local x_reset = x_storage_slot(14)
			local y_reset = y_call_sites + (core_count - 1) * core_pitch + 6
			part({ type = pt.FILT, x = x_reset    , y = y_reset - 1, ctype = 0x10000000 })
			part({ type = pt.DRAY, x = x_reset    , y = y_reset    , tmp = 1, tmp2 = 1 })
			part({ type = pt.PSCN, x = x_reset    , y = y_reset + 1 })
			part({ type = pt.METL, x = x_reset + 1, y = y_reset + 1 })
			part({ type = pt.NSCN, x = x_reset + 2, y = y_reset + 2 })
		end

		local patch_filt_list = {}
		local function patch_filt(x, y, ctype)
			patch_filt_list[xy_key(x, y)] = ctype
		end

		local x_ram_mask = x_storage_slot(29)
		local x_sync_bit = x_storage_slot(54)
		do
			local y_sync_bit = y_call_sites + (core_count - 1) * core_pitch - 1

			per_core(function(i, y)
				if i == core_count then
					dray(x_sync_bit - 5, y_sync_bit + 9, x_sync_bit, y + 3, 1, pt.PSCN)
				else
					dray(x_sync_bit, y_sync_bit + 9, x_sync_bit, y + 3, 1, pt.PSCN)
				end
				local value = i == core_count and 0x00010001 or 0x00010000
				patch_filt(x_sync_bit, y + 3, value)
			end)

			local x_dtec = x_sync_bit - 5
			aray(x_dtec - 3, y_sync_bit + 6, -1, 0, pt.METL)
			local y_source = y_call_sites + core_count * core_pitch
			ldtc(x_sync_bit, y_source - 1, x_sync_bit, y_source - 3)
			part({ type = pt.FILT, x = x_dtec - 2, y = y_sync_bit + 6, ctype = 0x00010001 })
			part({ type = pt.BRAY, x = x_dtec - 1, y = y_sync_bit + 6, ctype = 0x00010001 })
			part({ type = pt.INSL, x = x_dtec    , y = y_sync_bit + 6 })
			part({ type = pt.FILT, x = x_dtec - 2, y = y_sync_bit + 7, ctype = 0x00010011 })
			part({ type = pt.INSL, x = x_dtec - 0, y = y_sync_bit + 7 })
			part({ type = pt.FILT, x = x_dtec - 2, y = y_sync_bit + 8, ctype = 0x00010009 })
			part({ type = pt.DTEC, x = x_dtec    , y = y_sync_bit + 8, tmp2 = 2 })
			part({ type = pt.FILT, x = x_dtec + 1, y = y_sync_bit + 8, ctype = 0x00010001 })

			part({ type = pt.FILT, x = x_sync_bit     , y = y_sync_bit + 7, ctype = 0x00010000 })
			part({ type = pt.FILT, x = x_sync_bit     , y = y_sync_bit + 8, ctype = 0x00010000 })
			part({ type = pt.FILT, x = x_sync_bit -  1, y = y_sync_bit + 8, ctype = 0x00010000 })
			part({ type = pt.FILT, x = x_sync_bit - 23, y = y_sync_bit + 8, ctype = 0x00010000 })
			ldtc(x_sync_bit - 2, y_sync_bit + 8, x_sync_bit - 23, y_sync_bit + 8)

			local function connect_button(x, y)
				for xx = x, x_dtec - 3 do
					if not ( xx == x_ram_mask or
					        (xx == x_sync_bit and y == y_sync_bit + 8)) then
						part({ type = pt.STOR, x = xx, y = y })
					end
				end
				part({ type = pt.ARAY, x = x - 1, y = y })
				part({ type = pt.NSCN, x = x - 2, y = y })
			end
			connect_button(x_button_stop  + 5, y_sync_bit + 7)
			connect_button(x_button_start + 5, y_sync_bit + 8)
		end
		-- ram mask
		do
			local y_source = y_call_sites + core_count * core_pitch
			ldtc(x_ram_mask, y_source - 1, x_ram_mask, y_source - 3)
			part({ type = pt.FILT, x = x_ram_mask    , y = y_source    , ctype = ram_mask })
			part({ type = pt.FILT, x = x_ram_mask    , y = y_source + 1, ctype = ram_mask })
			part({ type = pt.FILT, x = x_ram_mask - 1, y = y_source + 1, ctype = ram_mask })
			part({ type = pt.FILT, x = x_ram_mask - 4, y = y_source + 1, ctype = ram_mask })
			ldtc(x_ram_mask - 2, y_source + 1, x_ram_mask - 4, y_source + 1)
			per_core(function(i, y)
				dray(x_ram_mask, y_source + 2, x_ram_mask, y + 3, 1, pt.PSCN)
				patch_filt(x_ram_mask, y + 3, ram_mask)
			end)
		end

		local parts_by_pos = {}
		for _, part in ipairs(parts) do
			parts_by_pos[xy_key(part.x, part.y)] = part
			if not part.dcolour then
				part.dcolour = 0xFF3F3F3F
			end
		end
		local function add_dmnd(x, y)
			local key = xy_key(x, y)
			local q = parts_by_pos[key]
			if q then
				if q.type == pt.FILT  then
					q.dcolour = 0xFF00FFFF
				end
				if q.type == pt.LDTC then
					q.dcolour = 0xFF007F7F
				end
			else
				parts_by_pos[key] = part({ type = pt.DMND, x = x, y = y, dcolour = 0xFFFFFFFF })
			end
		end
		for x = x1, x2 do
			add_dmnd(x, y1)
			add_dmnd(x, y1 - 1)
			add_dmnd(x, y2)
			add_dmnd(x, y2 + 1)
		end
		for y = y1, y2 do
			add_dmnd(x1, y)
			add_dmnd(x1 - 1, y)
			add_dmnd(x2, y)
			add_dmnd(x2 + 1, y)
		end

		local y_top    = y_call_sites - 3
		local y_bottom = y_call_sites + core_count * core_pitch - 3
		patch_filt(x_storage_slot(10)    ,     y_bottom, 0x10000008) -- state -- TODO: halt by default
		patch_filt(x_storage_slot(29)    , y_bottom + 3, 0x10000000) -- curr_instr
		patch_filt(x_storage_slot(54)    , y_bottom + 3, 0x10000000) -- curr_imm
		patch_filt(x_storage_slot(14)    ,     y_bottom, 0x10000000) -- pc
		patch_filt(x_storage_slot(16)    ,     y_bottom, 0x10000000) -- flags
		patch_filt(x_storage_slot( 7)    ,     y_bottom, 0x10000000) -- wreg_data
		patch_filt(x_storage_slot(62)    ,     y_bottom, 0x10000000) -- wreg_addr
		patch_filt(x_storage_slot(86)    ,    y_top + 0, 0x10040000) -- ram_addr*
		patch_filt(x_storage_slot(64) + 2,    y_top + 1, 0x10000000) -- ram_data*
		patch_filt(x_storage_slot(64) + 3,    y_top + 2, 0x10000000) -- ram_data*
		for key, ctype in pairs(patch_filt_list) do
			parts_by_pos[key].ctype = ctype
		end

		-- reclaim voids
		per_core(function(i, y)
			for _, index in ipairs(reclaimed_voids) do
				parts_by_pos[xy_key(x_storage_slot(index), y + 3)].type = pt.BRCK
			end
		end)
	end

	return parts
end

return {
	build = build,
}
