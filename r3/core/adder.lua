local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")

return testbed.module({
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 12,
	inputs = {
		{ name = "pri"     , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000DEAD },
		{ name = "sec"     , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BEEF },
		{ name = "carry"   , index = 5, keepalive = 0x00200000, payload = 0x00000001, initial = 0x00200000 },
		{ name = "subtract", index = 7, keepalive = 0x00010000, payload = 0x00000001, initial = 0x00010000 },
	},
	outputs = {
		{ name = "l_add"          , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "overflow_carry" , index = 3, keepalive = 0x10000000, payload = 0x00030000 },
	},
	func = function(inputs)
		local lhs_ka = inputs.pri:bor(0x3FFF0000):assert(0x3FFF0000, 0x0000FFFF)
		local rhs_ka = inputs.sec:bor(0x00010000):assert(0x10010000, 0x0000FFFF)
		local rhs_ka_subtract = rhs_ka:bxor(0x3FFFFFFF):bxor(spaghetti.lshift(0x3FFFFFFF, inputs.subtract))
		local generate = spaghetti.band(lhs_ka, rhs_ka_subtract):assert(0x10010000, 0x0000FFFF)
		local propagate = spaghetti.bxor(lhs_ka, rhs_ka_subtract):assert(0x2FFE0000, 0x0000FFFF)
		local onebit_sums = spaghetti.bxor(lhs_ka, rhs_ka):assert(0x2FFE0000, 0x0000FFFF)
		for i = 1, 4 do
			local bit_i = bitx.lshift(1, i)
			local bit_i_m1 = bitx.lshift(1, i - 1)
			local generate_keepalive = bitx.band(bitx.bor(0x30000000, bitx.lshift(bitx.lshift(1, bit_i) - 1, 16)), 0x3FFFFFFF)
			local propagate_fill = spaghetti.constant(0x3FFF0000, bitx.lshift(1, bit_i_m1) - 1)
			generate = spaghetti.bor(generate, spaghetti.band(propagate, spaghetti.lshiftk(generate, bit_i_m1))):assert(generate_keepalive, 0x0000FFFF)
			propagate = spaghetti.band(propagate, spaghetti.bor(spaghetti.lshiftk(propagate, bit_i_m1), propagate_fill)):assert(0x2FFE0000, 0x0000FFFF)
		end
		generate:assert(0x3FFF0000, 0x0000FFFF)
		propagate:assert(0x2FFE0000, 0x0000FFFF)
		local generate_shifted = spaghetti.lshiftk(generate, 1):assert(0x3FFE0000, 0x0001FFFE)
		local propagate_shifted = spaghetti.bor(spaghetti.lshiftk(propagate, 1), spaghetti.constant(0, 1)):assert(0x1FFC0000, 0x0001FFFF)
		local propagate_conditional = propagate_shifted:band(spaghetti.lshift(0x3FFFFFFF, inputs.carry))
		local carries = spaghetti.bor(generate_shifted, propagate_conditional):assert(0x3FFE0000, 0x0001FFFF)
		local carries_high = carries:band(0x08018000):assert(0x08000000, 0x00018000)
		local overflow_wild = spaghetti.lshiftk(spaghetti.lshiftk(carries_high, 1):bxor(carries_high), 1):assert(0x30000000, 0x00070000)
		local overflow_out = overflow_wild:band(0x10020000):assert(0x10000000, 0x00020000)
		local overflow_carry = overflow_out:bor(carries:band(0x10010000))
		local sum = spaghetti.bxor(onebit_sums, carries):band(0x1000FFFF)
		return {
			l_add          = sum,
			overflow_carry = overflow_carry,
		}
	end,
	fuzz_inputs = function()
		local pri = math.random(0x0000, 0xFFFF)
		local sec = math.random(0x0000, 0xFFFF)
		local carry_in = math.random(0x0, 0x1)
		local subtract_in = math.random(0x0, 0x1)
		return {
			pri      = bitx.bor(0x10000000, pri),
			sec      = bitx.bor(0x10000000, sec),
			carry    = bitx.bor(0x00200000, carry_in),
			subtract = bitx.bor(0x00010000, subtract_in),
		}
	end,
	fuzz_outputs = function(inputs)
		local pri = bitx.band(inputs.pri, 0xFFFF)
		local sec = bitx.band(inputs.sec, 0xFFFF)
		local carry_in = bitx.band(inputs.carry, 0x1)
		local subtract_in = bitx.band(inputs.subtract, 0x1)
		local function to_signed(value)
			if value >= 0x8000 then
				value = value - 0x10000
			end
			return value
		end
		local ssec = to_signed(sec)
		local spri = to_signed(pri)
		local sum, ssum
		if subtract_in == 0 then -- yes, it's inverted
			 sum =  sec - ( pri + carry_in)
			ssum = ssec - (spri + carry_in)
		else
			 sum =  sec + ( pri + carry_in)
			ssum = ssec + (spri + carry_in)
		end
		local carry_out    = ( sum <  0x0000 or  sum > 0xFFFF) and 0x10000 or 0x00000
		local overflow_out = (ssum < -0x8000 or ssum > 0x7FFF) and 0x20000 or 0x00000
		return {
			l_add          = bitx.bor(0x10000000, sum % 0x10000),
			overflow_carry = bitx.bor(bitx.bor(0x10000000, carry_out), overflow_out),
		}
	end,
})
