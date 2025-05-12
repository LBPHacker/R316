local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.alu.csmult",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 2,
	storage_slots = 60,
	work_slots    = 24,
	inputs = {
		{ name = "pri"   , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"   , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr" , index = 5, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
	},
	outputs = {
		{ name = "carries"  , index = 1, keepalive = 0x10000000, payload = 0x0FFFFFFE }, -- bit 27 is ignored by downstream components
		{ name = "sums_high", index = 3, keepalive = 0x10000000, payload = 0x0FFFFFFF }, -- bit 27 is ignored by downstream components
		{ name = "sums_low" , index = 5, keepalive = 0x10000000, payload = 0x0000001F },
	},
	func = function(inputs)
		-- see csmult.txt for some very terse explanation of the Wallace tree used here
		local partial = {}
		local sec_neg = spaghetti.select(inputs.instr:band(0x8000):zeroable(), inputs.sec:bxor(0x8000), inputs.sec)
		local diff = spaghetti.constant(0x3F000000):bxor(inputs.sec):assert(0x2F000000, 0x0000FFFF)
		for i = 0, 15 do
			local present = inputs.pri:bxor(0xFFFF)
			if bitx.band(i, 0xC) ~= 0 then
				present = spaghetti.rshiftk(present, bitx.band(i, 0xC))
			end
			if bitx.band(i, 0x3) ~= 0 then
				present = spaghetti.rshiftk(present, bitx.band(i, 0x3))
			end
			local shift_by = present:bor(0x10000):band(0x10001):assert(0x00010000, 0x00000001)
			local mask = spaghetti.constant(0x3FFFFFFF):lshift(shift_by):assert(0x3FFF0000, 0x0000FFFF)
			partial[i] = sec_neg:bxor(diff:band(mask)):assert(0x3F000000, 0x0000FFFF)
		end
		do
			local p0_15_incr = partial[0]:bxor(0x8000):bor(spaghetti.lshiftk(partial[0], 1):bsub(0xFFFF))
			local p_0, p_15 = spaghetti.select(
				inputs.instr:band(0x0001):zeroable(),
				p0_15_incr, partial[0]:bxor(0x10000),
				partial[15], partial[15]:bxor(0xFFFF)
			)
			partial[0], partial[15] = spaghetti.select(
				inputs.instr:band(0x8000):zeroable(),
				p_0, partial[0],
				p_15:bxor(0x10000), partial[15]
			)
		end
		for i = 0, 15 do
			partial[i]:label("p_" .. i)
		end
		local function full_adder(label, x, y, z, sk, sp, ck, cp)
			local function try(x, y, z)
				if bitx.bxor(x.keepalive_, y.keepalive_) == 0 or
				   bitx.band(x.keepalive_, y.keepalive_) == 0 then
					return
				end
				local xy = bitx.bxor(x.keepalive_, y.keepalive_)
				if bitx.bxor(z.keepalive_, xy) == 0 or
				   bitx.band(z.keepalive_, xy) == 0 then
					return
				end
				local xy = x:bxor(y)
				return {
					s = xy:bxor(z),
					c = xy:band(z):bor(x:band(y)),
				}
			end
			local result = assert(try(x, y, z) or
			                      try(y, z, x) or
			                      try(z, x, y))
			return result.s:assert(sk, sp):label("s_" .. label),
			       result.c:assert(ck, cp):label("c_" .. label)
		end
		local s_1a, c_1a = full_adder("1a", partial[ 0]   , partial[ 1]:lshift(2), partial[ 2]:lshift(4), 0x3D000000, 0x0003FFFF, 0x3E000000, 0x0001FFFE)
		local s_1b, c_1b = full_adder("1b", partial[ 3]   , partial[ 4]:lshift(2), partial[ 5]:lshift(4), 0x3D000000, 0x0003FFFF, 0x3E000000, 0x0001FFFE)
		local s_1c, c_1c = full_adder("1c", partial[ 6]   , partial[ 7]:lshift(2), partial[ 8]:lshift(4), 0x3D000000, 0x0003FFFF, 0x3E000000, 0x0001FFFE)
		local s_1d, c_1d = full_adder("1d", partial[ 9]   , partial[10]:lshift(2), partial[11]:lshift(4), 0x3D000000, 0x0003FFFF, 0x3E000000, 0x0001FFFE)
		local s_1e, c_1e = full_adder("1e", partial[12]   , partial[13]:lshift(2), partial[14]:lshift(4), 0x3D000000, 0x0003FFFF, 0x3E000000, 0x0001FFFE)
		local s_2a, c_2a = full_adder("2a", c_1a:lshift(2), s_1a:bxor(0x01000000), s_1b:lshift(8)       , 0x28000000, 0x001FFFFF, 0x3C000000, 0x0003FFFC)
		local s_2b, c_2b = full_adder("2b", c_1b          , s_1c:lshift(4)       , c_1c:lshift(8)       , 0x3A000000, 0x000FFFFE, 0x34000000, 0x000FFFFC)
		local s_2c, c_2c = full_adder("2c", c_1d:lshift(2), s_1d:bxor(0x01000000), s_1e:lshift(8)       , 0x28000000, 0x001FFFFF, 0x3C000000, 0x0003FFFC)
		local s_3a, c_3a = full_adder("3a", s_2a          , c_2a:lshift(2)       , s_2b:lshift(0x10)    , 0x30000000, 0x00FFFFFF, 0x28000000, 0x001FFFF8)
		local s_3b, c_3b = full_adder("3b", s_2c          , c_2c:lshift(2)       , c_1e:lshift(0x10)    , 0x30000000, 0x001FFFFF, 0x28000000, 0x001FFFF8)
		local c_2b_adjusted = c_2b:bxor(0x00200000):lshift(0x20):bxor(0x20000000)
		local s_4a, c_4a = full_adder("4a", s_3a          , c_3a:lshift(2)       , c_2b_adjusted        , 0x04000000, 0x01FFFFFF, 0x30000000, 0x00FFFFF0)
		local p_15_adjusted = partial[15]:bxor(0x00200000):lshift(0x40):bxor(0x20000000)
		local s_4b, c_4b = full_adder("4b", s_3b          , c_3b:lshift(2)       , p_15_adjusted        , 0x08000000, 0x007FFFFF, 0x30000000, 0x003FFFF0)
		local c_4b_adjusted = c_4b:bxor(0x01000000):lshift(0x20):bxor(0x10000000)
		local c_4a_adjusted = c_4a:bxor(0x20000000):rshift(0x10):bxor(0x30000000):bxor(0x01000000)
		local s_4b_adjusted = s_4b:bxor(0x01000000):lshift(0x10)
		local s_5a, c_5a = full_adder("5a", s_4b_adjusted , c_4b_adjusted        , c_4a_adjusted        , 0x10000000, 0x07FFFFFF, 0x30000000, 0x07FFFFF0)
		local s_4a_adjusted = s_4a:rshift(0x20):bxor(0x30000000):bxor(0x00200000)
		local c_5a_adjusted = c_5a:lshift(2):bxor(0x10000000)
		local s_6a, c_6a = full_adder("6a", c_5a_adjusted , s_4a_adjusted        , s_5a                 , 0x10000000, 0x0FFFFFFF, 0x30000000, 0x07FFFFFF)
		return {
			carries   = c_6a:lshift(2):bxor(0x30000000),
			sums_high = s_6a,
			sums_low  = s_4a:bor(0x10000000):band(0x1000001F),
		}
	end,
	fuzz_inputs = function()
		return {
			pri    = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec    = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			instr  = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
		}
	end,
	fuzz_outputs_implicit = function(inputs, outputs)
		local pri    = bitx.band(inputs.pri, 0xFFFF)
		local sec    = bitx.band(inputs.sec, 0xFFFF)
		local signed = bitx.band(inputs.instr, 0x8000) ~= 0
		local mixed  = bitx.band(inputs.instr, 0x0001) ~= 0
		if signed then
			if not mixed then
				if pri >= 0x8000 then
					pri = pri - 0x10000
				end
			end
			if sec >= 0x8000 then
				sec = sec - 0x10000
			end
		end
		local carries   = bitx.band(outputs.carries  , 0x07FFFFFF)
		local sums_high = bitx.band(outputs.sums_high, 0x07FFFFFF)
		local sums_low  = bitx.band(outputs.sums_low , 0x0000001F)
		local sums = sums_low + bitx.lshift(sums_high, 5)
		local prod = sums + bitx.lshift(carries, 5)
		if bitx.bxor(prod, pri * sec) ~= 0 then
			return nil, "mismatch"
		end
		return true
	end,
})
