local strict = require("spaghetti.strict")
strict.wrap_env()

local plot = require("spaghetti.plot")

local function make_context(parts)
	local pt = plot.pt

	local function sig_magn(x)
		local magn = math.abs(x)
		return x == 0 and 0 or (x / magn), magn
	end

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
		function solid_spark(x, y, x_off, y_off, conductor, no_auto_z)
			local key = xy_key(x + x_off, y + y_off)
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

	local function frame(x1, y1, x2, y2)
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
		for y = 0, 1 do
			for x = 0, 1 do
				add_dmnd(x + x1, y + y1)
				add_dmnd(x + x1, y + y2 - 1)
				add_dmnd(x + x2 - 1, y + y1)
				add_dmnd(x + x2 - 1, y + y2 - 1)
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
		xy_key        = xy_key,
		solid_spark   = solid_spark,
		lsns_taboo    = lsns_taboo,
		lsns_spark    = lsns_spark,
		dray          = dray,
		ldtc          = ldtc,
		cray          = cray,
		aray          = aray,
		frame         = frame,
	}
end

return {
	make_context = make_context,
}
