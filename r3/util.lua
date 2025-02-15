local strict = require("spaghetti.strict")
strict.wrap_env()

local plot = require("spaghetti.plot")
local bitx = require("spaghetti.bitx")
local misc = require("spaghetti.misc")

local audited_pairs = pairs

local function ilog2floor(n)
	local l = 0
	while n > 1 do
		n = bitx.rshift(n, 1)
		l = l + 1
	end
	return l
end

local function ilog2ceil(n)
	local l = ilog2floor(n)
	if bitx.lshift(1, l) < n then
		l = l + 1
	end
	return l
end

local function make_context(parts, debug_stacks)
	local pt = plot.pt

	local function sig_magn(x)
		local magn = math.abs(x)
		return x == 0 and 0 or (x / magn), magn
	end

	local function mutate(p, m)
		local q = {}
		for key, value in audited_pairs(p) do
			q[key] = value
		end
		for key, value in audited_pairs(m) do
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
		if debug_stacks then
			m.user_stack = misc.user_stack()
		end
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

	local solid_spark
	do
		local map = {}
		function solid_spark(x, y, x_off, y_off, conductor, no_auto_z)
			local key = plot.xy_key(x + x_off, y + y_off)
			if map[key] then
				if not (map[key].x == x and map[key].y == y and map[key].conductor == conductor) then
					error("spark conflict", 2)
				end
			else
				part ({ type = pt.CONV  , x = x        , y = y        , tmp = pt.SPRK, ctype = conductor, z = (not no_auto_z) and 10000000 or nil })
				part ({ type = pt.CONV  , x = x        , y = y        , tmp = conductor, ctype = pt.SPRK, z = (not no_auto_z) and 10000001 or nil })
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
			local key = plot.xy_key(x, y)
			if not dmnds[key] then
				dmnds[key] = part({ type = pt.DMND, x = x, y = y })
			end
			return dmnds[key]
		end
	end

	local lsns_spark
	do
		local lmap = {}
		local function lsns(p)
			local key = plot.xy_key(p.x, p.y)
			if not lmap[key] then
				lmap[key] = true
				part(mutate(p, { type = pt.LSNS, tmp = 3 }))
			end
		end
		local fmap = {}
		local function filt(p, life)
			local key = plot.xy_key(p.x, p.y)
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

	local function dray(x, y, x_to, y_to, count, conductor, z, no_auto_z)
		assert(x and y and x_to and y_to and count)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local dist = magn - count - 1
		if dist < 0 then
			error("bad distance", 2)
		end
		local q = part({ type = pt.DRAY, x = x, y = y, tmp = count, tmp2 = dist, z = z })
		if conductor ~= false then
			assert(conductor)
			solid_spark(x, y, -dx_sig, -dy_sig, conductor, no_auto_z)
		end
		return q
	end

	local function dray_log(x, y, x_to, y_to, count, conductor)
		assert(x and y and x_to and y_to and count)
		if conductor ~= false then
			assert(conductor)
		end
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		local order = 0
		local dist = math.max(dx_magn, dy_magn)
		local step = dist - 1
		while count > 0 do
			local max_take = bitx.lshift(step, order)
			local take = math.min(max_take, count)
			local x_to = x + dx_sig * dist
			local y_to = y + dy_sig * dist
			dray(x, y, x_to, y_to, take, conductor)
			count = count - take
			dist = dist + take
			order = order + 1
		end
	end

	local function ldtc(x, y, x_to, y_to, z, tmp)
		assert(x and y and x_to and y_to)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.LDTC, x = x, y = y, life = magn - 1, z = z, tmp = tmp })
		return q
	end

	local function cray(x, y, x_to, y_to, ptype, count, conductor, z, life)
		assert(x and y and x_to and y_to and ptype and count)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local magn = math.max(dx_magn, dy_magn)
		local q = part({ type = pt.CRAY, x = x, y = y, ctype = ptype, tmp = count, tmp2 = magn - 1, z = z, life = life })
		if conductor ~= false then
			assert(conductor)
			solid_spark(x, y, -dx_sig, -dy_sig, conductor)
		end
		return q
	end

	local function pos_sort(pos)
		table.sort(pos, function(a, b)
			if a.y ~= b.y then return a.y < b.y end
			if a.x ~= b.x then return a.x < b.x end
			return false
		end)
		return pos
	end

	local function spark_row(x, y, x_to, y_to, conductor, count, life, dist)
		dist = dist or 3
		assert(x and y and x_to and y_to and count and life)
		local dx_sig, dx_magn = sig_magn(x_to - x)
		local dy_sig, dy_magn = sig_magn(y_to - y)
		if not (dx_magn == dy_magn or dx_magn == 0 or dy_magn == 0) then
			error("bad offset", 2)
		end
		local pos = pos_sort({
			{ x = x - dist * dx_sig, y = y - dist * dy_sig },
			{ x = x                , y = y                 },
		})
		cray(pos[1].x, pos[1].y, x_to, y_to, conductor, count, pt.PSCN)
		cray(pos[1].x, pos[1].y, x_to, y_to, conductor, count, pt.PSCN)
		cray(pos[2].x, pos[2].y, x_to, y_to, pt.SPRK, count, pt.INWR, nil, life)
	end

	local function aray(x, y, x_off, y_off, conductor, z, life, no_auto_z)
		assert(x and y and x_off and y_off)
		local q = part({ type = pt.ARAY, x = x, y = y, z = z, life = life })
		if conductor ~= false then
			assert(conductor)
			solid_spark(x, y, x_off, y_off, conductor, no_auto_z)
		end
		return q
	end

	local function frame(x1, y1, x2, y2, bevel_begin, bevel_end)
		bevel_begin = bevel_begin or -2
		bevel_end = bevel_end or 0
		local parts_by_pos = {}
		for _, part in ipairs(parts) do
			parts_by_pos[plot.xy_key(part.x, part.y)] = part
			if not part.dcolour then
				part.dcolour = 0xFF3F3F3F
			end
		end
		local function add_dmnd(x, y)
			local key = plot.xy_key(x, y)
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
		for x = x1 + 1, x2 - 1 do
			add_dmnd(x, y1)
			add_dmnd(x, y1 - 1)
			add_dmnd(x, y2)
			add_dmnd(x, y2 + 1)
		end
		for y = y1 + 1, y2 - 1 do
			add_dmnd(x1, y)
			add_dmnd(x1 - 1, y)
			add_dmnd(x2, y)
			add_dmnd(x2 + 1, y)
		end
		for y = -1, 1 do
			for x = -1, 1 do
				if x + y >= bevel_begin and x + y <= bevel_end then
					add_dmnd(x1 - x, y1 - y)
					add_dmnd(x1 - x, y2 + y)
					add_dmnd(x2 + x, y1 - y)
					add_dmnd(x2 + x, y2 + y)
				end
			end
		end
		return parts_by_pos
	end

	return {
		sig_magn      = sig_magn,
		mutate        = mutate,
		piston_extend = piston_extend,
		part          = part,
		spark         = spark,
		solid_spark   = solid_spark,
		lsns_taboo    = lsns_taboo,
		lsns_spark    = lsns_spark,
		dray          = dray,
		dray_log      = dray_log,
		ldtc          = ldtc,
		cray          = cray,
		aray          = aray,
		spark_row     = spark_row,
		frame         = frame,
	}
end

local function wrap_build(build)
	return function(...)
		return misc.user_wrap(function(...)
			return build(...)
		end, ...)
	end
end

local function aftersimdraw_user_stacks(tx, ty, x, y, parts, module_dir)
	local parts_by_pos = {}
	for _, part in ipairs(parts) do
		if part.user_stack then
			local key = plot.xy_key(part.x, part.y)
			if not parts_by_pos[key] then
				parts_by_pos[key] = {}
			end
			table.insert(parts_by_pos[key], part)
		end
	end
	return function()
		local mx, my = sim.adjustCoords(ui.mousePosition())
		local key = plot.xy_key(mx - x, my - y)
		local stack = parts_by_pos[key]
		if stack then
			local line_count = 0
			local function put_line(str)
				local w, h = gfx.textSize(str)
				gfx.fillRect(tx - 5, ty + line_count * 12 - 2, w + 10, h + 2, 0, 0, 0, 192)
				gfx.drawText(tx, ty + line_count * 12, str)
				line_count = line_count + 1
			end
			for j = 1, math.min(#stack, 10) do
				local part = stack[j]
				put_line(("- particle #%i: %s"):format(j, elem.property(part.type, "Name")))
				for i = 1, #part.user_stack do
					local source = part.user_stack[i].source
					local line = part.user_stack[i].currentline
					local first, last = source:find("@" .. module_dir .. "/", 1, true)
					if first then
						source = source:sub(last + 1)
					end
					put_line(("  - %s:%i"):format(source, line))
				end
			end
		end
	end
end

return {
	make_context = make_context,
	wrap_build   = wrap_build,
	ilog2floor   = ilog2floor,
	ilog2ceil    = ilog2ceil,
	aftersimdraw_user_stacks = aftersimdraw_user_stacks,
}
