local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.alu.adder",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		seed          = { 0xDEADBEEF, 0xCAFEBABE },
	},
	stacks        = 1,
	probe_length  = 3,
	unclobbered = {  11, 12,  13,  14,  15,  16,  17, 22, 23, 24, 25, 26, 27,
	                -12, -14, -15, -16, -17, -22, -23, -24, -25, -26, -27 },
	compute_operands = { 3, 7,  9, 18, 20, -3, -5, -8, -10, -18, -20, -28, -30, -32, -34, -36 },
	compute_results  = { 4, 8, 10, 19, 21, -4, -6, -9, -11, -19, -21, -29, -31, -33, -35, -37 },
	inputs = {
		{ name = "pri"  , index =   6, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"  , index = -13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flags", index =   5, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x1000000B },
		{ name = "instr", index =  -7, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
	},
	outputs = {
		{ name = "res_add"       , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "overflow_carry", index = 13, keepalive = 0x10000000, payload = 0x00000003 },
	},
	func = function(inputs)
		local lhs_ka = inputs.pri:bor(0x3FFF0000):assert(0x3FFF0000, 0x0000FFFF)
		local rhs_ka = inputs.sec:bor(0x00010000):assert(0x10010000, 0x0000FFFF)
		local instr_2 = spaghetti.rshiftk(inputs.instr, 1)
		local rhs_ka_subtract = rhs_ka:bxor(0x3FFFFFFF):bxor(spaghetti.lshift(0x3FFFFFFF, instr_2:bor(0x10000):bsub(0xFFFE)))
		local generate    = lhs_ka:band(rhs_ka_subtract):assert(0x10010000, 0x0000FFFF)
		local propagate   = lhs_ka:bxor(rhs_ka_subtract):assert(0x2FFE0000, 0x0000FFFF)
		local onebit_sums = lhs_ka:bxor(rhs_ka)         :assert(0x2FFE0000, 0x0000FFFF)
		for i = 0, 3 do
			local bit_i = bitx.lshift(1, i + 1)
			local bit_i_m1 = bitx.lshift(1, i)
			local generate_keepalive = bitx.band(bitx.bor(0x30000000, bitx.lshift(bitx.lshift(1, bit_i) - 1, 16)), 0x3FFFFFFF)
			local propagate_fill     = bitx.lshift(1, bit_i_m1) - 1
			generate  = generate:bor(propagate:band(spaghetti.lshiftk(generate, bit_i_m1))):assert(generate_keepalive, 0x0000FFFF)
			propagate = propagate:band(spaghetti.lshiftk(propagate, bit_i_m1):bor(propagate_fill):bor(0x3FFF0000)):assert(0x2FFE0000, 0x0000FFFF)
		end
		generate:assert(0x3FFF0000, 0x0000FFFF)
		propagate:assert(0x2FFE0000, 0x0000FFFF)
		local carry_in              = inputs.flags:band(inputs.instr):bsub(0xFFFE)          :assert(0x10000000, 0x00000001)
		local propagate_conditional = propagate:band(spaghetti.lshift(0x3FFFFFFF, carry_in)):assert(0x20000000, 0x0FFEFFFF)
		local carries_no_in         = generate:bor(propagate_conditional)                   :assert(0x3FFF0000, 0x0000FFFF)
		local carries               = spaghetti.lshiftk(carries_no_in, 1):bor(carry_in)     :assert(0x3FFE0000, 0x0001FFFF)
		local carries_15            = spaghetti.rshiftk(carries, 15)                        :assert(0x00007FFC, 0x00000003)
		local carry      = spaghetti.rshiftk(carries, 16)                   :bor(0x00010000):bsub(0xFFFE)
		local overflow   = carries_15:bxor(carry)                           :bor(0x00010000):bsub(0xFFFE)
		local overflow_carry = spaghetti.lshiftk(overflow, 1):bor(carry):bor(0x10000000):band(0x1000000F)
		local sum            = onebit_sums:bxor(carries):band(0x1000FFFF)
		return {
			res_add        = sum,
			overflow_carry = overflow_carry,
		}
	end,
	fuzz_inputs = function(inputs)
		return {
			pri   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			flags = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			instr = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pri         = bitx.band(inputs.pri  , 0xFFFF)
		local sec         = bitx.band(inputs.sec  , 0xFFFF)
		local carry_in    = bitx.band(inputs.flags, 0x0001, inputs.instr)
		local subtract_in = bitx.band(inputs.instr, 0x0002)
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
		local carry_out    = ( sum <  0x0000 or  sum > 0xFFFF) and 1 or 0
		local overflow_out = (ssum < -0x8000 or ssum > 0x7FFF) and 2 or 0
		return {
			res_add        = bitx.bor(0x10000000, sum % 0x10000),
			overflow_carry = bitx.bor(bitx.bor(0x10000000, carry_out), overflow_out),
		}
	end,
})
