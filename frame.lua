local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx = require("spaghetti.bitx")
local plot = require("spaghetti.plot")

local function sig_magn(x)
	local magn = math.abs(x)
	return x == 0 and 0 or (x / magn), magn
end

local function build(width_order, height_order)
	assert(width_order >= 6, "width order too small")
	local height_order_2 = height_order + 1
	assert(width_order >= height_order_2, "bad aspect ratio")
	assert(width_order + height_order <= 16, "too many address bits")
	local width = bitx.lshift(1, width_order)
	local height = bitx.lshift(1, height_order)
	local height_order_up = height_order_2
	if height_order_up % 2 == 1 then
		height_order_up = height_order_up + 1
	end
	local width_order_up = width_order
	if width_order_up % 2 == 1 then
		width_order_up = width_order_up + 1
	end

	local y_filt_block = 0
	local y_ldtc_dray_bank = 10
	local y_call_sites = 30
	local core_count = 3
	local core_pitch = 8
	local addresses = { 0x2000DEAD, 0x2000DEAD, 0x2000CAFE }
	local writes    = { 0x2000BABE,      false,      false }
	assert(#addresses == core_count)
	assert(#writes == core_count)

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
		function solid_spark(x, y, xoff, yoff, conductor)
			local key = xy_key(x + xoff, y + yoff)
			if map[key] then
				if not (map[key].x == x and map[key].y == y and map[key].conductor == conductor) then
					error("spark conflict", 2)
				end
			else
				part ({ type = pt.CONV  , x = x       , y = y       , tmp = pt.SPRK, ctype = conductor, z = 10000000 })
				part ({ type = pt.CONV  , x = x       , y = y       , tmp = conductor, ctype = pt.SPRK, z = 10000001 })
				spark({ type = conductor, x = x + xoff, y = y + yoff })
				map[key] = {
					x = x,
					y = y,
					conductor = conductor,
				}
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
				part(mutate(p, { type = pt.LSNS, tmp = 3, tmp2 = 1 }))
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
		function lsns_spark(p, lxoff, lyoff, fxoff, fyoff)
			spark(p)
			lsns({ x = p.x + lxoff, y = p.y + lyoff })
			filt({ x = p.x + fxoff, y = p.y + fyoff }, p.life)
		end
	end
	local function dray(x, y, to_x, to_y, count, conductor, z)
		local dx_sig, dx_magn = sig_magn(to_x - x)
		local dy_sig, dy_magn = sig_magn(to_y - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.DRAY, x = x, y = y, tmp = count, tmp2 = magn - count - 1, z = z })
		solid_spark(x, y, -dx_sig, -dy_sig, conductor)
		return q
	end
	local function cray(x, y, to_x, to_y, ptype, count, conductor, z)
		local dx_sig, dx_magn = sig_magn(to_x - x)
		local dy_sig, dy_magn = sig_magn(to_y - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.CRAY, x = x, y = y, ctype = ptype, tmp = count, tmp2 = magn - 1, z = z })
		solid_spark(x, y, -dx_sig, -dy_sig, conductor)
		return q
	end
	local apom_order_pre = {}
	local part_injected, part_injected_patch
	do
		local apom_juggle_y = -10
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
		function part_injected(p, order, apom_depth, skip_payload, cleanup_y)
			local target_y = p.y
			per_core(function(i, y)
				if not skip_payload then
					table.insert(per_core_info[i].cray_groups[1], cray(p.x, y, p.x, apom_juggle_y, pt.CRMC, 1, pt.PSCN, 1900)) -- the 1 gets patched in part_injected_patch
					table.insert(per_core_info[i].cray_groups[2], cray(p.x, y, p.x, apom_juggle_y, pt.CRMC, 1, pt.PSCN, 1901)) -- the 1 gets patched in part_injected_patch
					table.insert(per_core_info[i].cray_groups[3], cray(p.x, y, p.x, apom_juggle_y, pt.CRMC, 1, pt.PSCN, 1902)) -- the 1 gets patched in part_injected_patch
				end
			end)
			per_core(function(i, y)
				cray(p.x, y + core_pitch, p.x, cleanup_y or p.y, pt.SPRK, 1, pt.PSCN, 2000 + inject_z)
			end)
			per_core(function(i, y)
				if not skip_payload then
					part(mutate(p, { y = y - 1 }))
				end
				if not skip_payload then
					table.insert(per_core_info[i].cray_groups[4], cray(p.x, y, p.x, apom_juggle_y, pt.CRMC, 1, pt.PSCN, 2100)) -- the 1 gets patched in part_injected_patch
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
			-- table.insert(parts, { type = pt.FILT, x = x, y = y_filt_block - y, ctype = 0xC0DE0000 + y * width + x })
			table.insert(parts, { type = pt.FILT, x = width - 1 - x, y = y_filt_block - y, ctype = 0xC0DE0000 + y * width + x })
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
	-- active head second row template; TODO: fix life so it doesn't have to be put this far to the left to not extend pistons
	local ah_sr_template_x = -10 - height_order_up - width_order_up
	lsns_spark({ type = pt.PSCN, x = ah_sr_template_x, y = y_ldtc_dray_bank + 1, life = 3 }, -1, -1, -1, 0)
	dray(ah_sr_template_x - 2, y_ldtc_dray_bank + 1, 0, y_ldtc_dray_bank + 1, 2, pt.PSCN)
	-- logarithmically clone active head second row template
	for i = 1, height_order do
		local w = bitx.lshift(1, i)
		dray(-1, y_ldtc_dray_bank + 1, w, y_ldtc_dray_bank + 1, w, pt.PSCN)
	end

	-- line of filt to be dray'd into the filt block above
	for y = -2, width - 1 do
		part({ type = pt.FILT, x = y, y = y_ldtc_dray_bank + 2 })
	end

	-- bank piston frame
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank - 2 })
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank - 1 })
	-- bank piston
	local bank_piston_x = -3 - height_order_up
	part_injected({ type = pt.PSTN, x = bank_piston_x    , y = y_ldtc_dray_bank - 1, extend = 2 }, 0, 11) -- extend to the programmed distance
	lsns_spark   ({ type = pt.PSCN, x = bank_piston_x    , y = y_ldtc_dray_bank    , life = 3 }, -1, 1, 0, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = bank_piston_x - 1, y = y_ldtc_dray_bank - 1 }) -- filler
	part_injected({ type = pt.PSTN, x = bank_piston_x - 2, y = y_ldtc_dray_bank - 1, extend = math.huge }, 3, 10) -- retract fully
	lsns_spark   ({ type = pt.NSCN, x = bank_piston_x - 2, y = y_ldtc_dray_bank    , life = 3 }, 1, 1, 2, 1) -- spark for the above
	part         ({ type = pt.INSL, x = bank_piston_x - 3, y = y_ldtc_dray_bank - 1 }) -- left cap
	part         ({ type = pt.INSL, x = height * 2       , y = y_ldtc_dray_bank - 1 }) -- right cap
	for i = height_order_2 + 1, height_order_up do
		part({ type = pt.PSTN, x = -2 - i, y = y_ldtc_dray_bank - 1 }) -- filler
	end

	-- particles to be overwritten by address piston drays
	part({ type = pt.INSL, x = -3, y = y_ldtc_dray_bank })
	part({ type = pt.INSL, x = bank_piston_x    , y = y_ldtc_dray_bank + 4 })
	part({ type = pt.INSL, x = bank_piston_x - 2, y = y_ldtc_dray_bank + 4 })
	part({ type = pt.INSL, x = bank_piston_x - 4, y = y_ldtc_dray_bank + 4 })
	per_core(function(i, y)
		part({ type = pt.INSL, x = bank_piston_x    , y = y - 3 })
		part({ type = pt.INSL, x = bank_piston_x - 2, y = y - 3 })
	end)

	-- active head piston frame
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank + 3 })
	part         ({ type = pt.FRME, x = -2, y = y_ldtc_dray_bank + 4 })
	-- active head piston
	local ah_piston_x = -3 - height_order_up - width_order_up
	part_injected({ type = pt.PSTN, x = ah_piston_x    , y = y_ldtc_dray_bank + 3, extend = 1 }, 5, 9) -- retract to the programmed distance
	lsns_spark   ({ type = pt.NSCN, x = ah_piston_x    , y = y_ldtc_dray_bank + 4, life = 3 }, -1, 1, -2, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = ah_piston_x - 1, y = y_ldtc_dray_bank + 3 }) -- filler
	part_injected({ type = pt.PSTN, x = ah_piston_x - 2, y = y_ldtc_dray_bank + 3, extend = math.huge }, 4, 8) -- extend fully
	lsns_spark   ({ type = pt.PSCN, x = ah_piston_x - 2, y = y_ldtc_dray_bank + 4, life = 3 }, 1, 1, 0, 1) -- spark for the above
	part         ({ type = pt.PSTN, x = ah_piston_x - 3, y = y_ldtc_dray_bank + 3 }) -- filler
	part_injected({ type = pt.PSTN, x = ah_piston_x - 4, y = y_ldtc_dray_bank + 3, extend = math.huge }, 9, 7) -- retract fully
	lsns_spark   ({ type = pt.NSCN, x = ah_piston_x - 4, y = y_ldtc_dray_bank + 4, life = 3 }, 1, 1, 2, 1) -- spark for the above
	part         ({ type = pt.INSL, x = ah_piston_x - 5, y = y_ldtc_dray_bank + 3 }) -- left cap
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
	lsns_spark   ({ type = pt.PSCN, x = -1, y = y_ldtc_dray_bank - 2, life = 3 }, 0, -1, -1, -1) -- spark for the above
	-- active head placeholders
	part_injected(mutate(active_head_copier, { y = y_ldtc_dray_bank - 6 }), 7, 4, true, y_ldtc_dray_bank + 4)
	part_injected(mutate(active_head_copier, { y = y_ldtc_dray_bank - 5 }), 8, 3, true, y_ldtc_dray_bank + 3)

	-- get ctype into the line of filt above the active head
	part_injected({ type = pt.LDTC, x = -3, y = y_ldtc_dray_bank + 2 }, 6, 2)
	do
		local x = -7 - height_order_up
		part({ type = pt.FILT, x = x, y = y_ldtc_dray_bank + 2, ctype = 0x10000000 })
		per_core(function(i, y)
			part({ type = pt.FILT, x = x, y = y - 1, ctype = writes[i] or 0x3FFFFFFF })
			dray(x, y, x, y_ldtc_dray_bank + 2, 1, pt.PSCN)
		end)
	end

	-- get ctype from active head
	local get_ctype_x = -10 - width_order_up - height_order_up
	part         ({ type = pt.FILT, x = get_ctype_x    , y = y_ldtc_dray_bank + 4 })
	part_injected({ type = pt.LDTC, x = get_ctype_x + 1, y = y_ldtc_dray_bank + 4, life = -3 - get_ctype_x }, 10, 1)
	per_core(function(i, y)
		part({ type = pt.FILT, x = get_ctype_x, y = y + 2 })
		part({ type = pt.LDTC, x = get_ctype_x, y = y + 1, life = (i - 1) * core_pitch + y_call_sites - y_ldtc_dray_bank - 4 })
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

	local apom_parts_x = 3
	for j = 1, #apom_order do
		apom_order[j] = apom_order[j] + apom_parts_x
	end
	-- float apom'd particles
	per_core(function(i, y)
		for j = #apom_order, 1, -1 do
			part({ type = pt.CRMC, x = apom_order[j], y = y })
			cray(-12 - height_order_up - width_order_up, y, apom_order[j], y, pt.CRMC, 1, pt.PSCN)
		end
	end)
	-- restore apom'd particles
	local restore_y = core_count * core_pitch + 33
	per_core(function(i, y)
		for j = #apom_order, 1, -1 do
			local x = apom_order[j]
			cray(2, y + core_pitch, x, y + core_pitch, pt.CRMC, 1, pt.PSCN)
			cray(x, restore_y + x % 2 * 3, x, y + core_pitch, pt.CRMC, 1, pt.PSCN)
			cray(x, restore_y + x % 2 * 3, x, y             , pt.CRMC, 1, pt.PSCN)
		end
	end)
	for i = 1, height_order_2 do
		part({ type = pt.CRMC, x = -2 - i, y = y_ldtc_dray_bank - 1 })
	end
	for i = 1, width_order do
		part({ type = pt.CRMC, x = -2 - i - height_order_2, y = y_ldtc_dray_bank + 3 })
	end
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

		local stack_x = 1
		local filt_bank_x = 3
		local function change_conductor(conductor)
			part({ type = pt.CONV, x = stack_x, y = y - 2, ctype = conductor, tmp = pt.SPRK })
			part({ type = pt.CONV, x = stack_x, y = y - 2, ctype = pt.SPRK, tmp = conductor })
			part({ type = pt.LSNS, x = stack_x, y = y - 2, tmp = 3, tmp2 = 1 })
		end

		spark({ type = pt.METL, x = stack_x + 1, y = y - 2 })
		part ({ type = pt.FILT, x = stack_x - 1, y = y - 2, ctype = 0x10000003 })
		part ({ type = pt.STOR, x = stack_x - 2, y = y - 2 })
		part ({ type = pt.FILT, x = stack_x - 3, y = y - 2, tmp = 1, ctype = addresses[i] + (writes[i] and 0x10000 or 0) })

		part({ type = pt.FILT, x = filt_bank_x, y = y - 2, ctype = 0x10000003 })
		local filt_offsets = {}
		local add_bit
		do
			local seen = 0
			function add_bit(k)
				part({ type = pt.FILT, x = filt_bank_x + seen + 1, y = y - 2, ctype = bitx.lshift(1, k) })
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
		part({ type = pt.CRAY, x = stack_x, y = y - 2, tmp = width_order + height_order_2    , tmp2 = 3, ctype = pt.SPRK })
		part({ type = pt.CRAY, x = stack_x, y = y - 2, tmp = width_order + height_order_2 - 1, tmp2 = 3, ctype = pt.STOR })
		change_conductor(pt.METL)
		local function handle_bit(address_index, piston_bit, piston_index, last)
			part({ type = pt.LDTC, x = stack_x, y = y - 2, life = filt_bank_x - stack_x + filt_offsets[address_index] })
			part({ type = pt.ARAY, x = stack_x, y = y - 2 })
			part({ type = pt.LDTC, x = stack_x, y = y - 2, life = filt_bank_x - stack_x - 1 })
			change_conductor(pt.PSCN)
			if last then
				part({ type = pt.CRAY, x = stack_x, y = y - 2, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = piston_extend(0) })
			else
				part({ type = pt.CRAY, x = stack_x, y = y - 2, tmp = 2, tmp2 = 2 + piston_index, ctype = pt.PSTN, temp = piston_extend(0) })
			end
			change_conductor(pt.METL)
			part({ type = pt.CRAY, x = stack_x, y = y - 2, tmp = 1, tmp2 = 3 + piston_index, ctype = pt.PSTN, temp = piston_extend(bitx.lshift(1, piston_bit)) })
		end
		for i = 0, width_order - 1 do
			handle_bit(i, i, width_order + height_order_2 - 1 - i, false)
		end
		for i = 0, height_order - 1 do
			handle_bit(i + width_order, i + 1, height_order_2 - 1 - i, false)
		end
		handle_bit(16, 0, 0, true)

		local pistons = width_order + height_order_2
		cray(stack_x - 4 - pistons, y - 2, stack_x - 3 - pistons, y - 2, pt.INSL, pistons, pt.PSCN)
		cray(stack_x - 4 - pistons, y - 2, stack_x - 3 - pistons, y - 2, pt.INSL, pistons, pt.PSCN)
	end)

	return parts
end

return {
	build = build,
}
