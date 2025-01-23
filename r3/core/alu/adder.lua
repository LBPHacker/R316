local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	local payload = params.core_type == "m" and 0x07FFFFFF or 0x0000FFFF
	return {
		tag = "core.alu.adder",
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
			{ name = "pri"  , index = 1, keepalive = 0x10000000, payload = payload   , initial = 0x10000000 },
			{ name = "sec"  , index = 3, keepalive = 0x10000000, payload = payload   , initial = 0x10000000 },
			{ name = "flags", index = 5, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x1000000B },
			{ name = "instr", index = 7, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
		},
		outputs = {
			{ name = "res_add"       , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "overflow_carry", index = 3, keepalive = 0x10000000, payload = 0x00000003 },
			params.core_type == "m" and { name = "sum_27", index = 5, keepalive = 0x10000000, payload = 0x07FFFFFF } or nil,
		},
		func = function(inputs)
			local lhs_ka = inputs.pri:bor(0x20000000):assert(0x30000000, payload)
			local rhs_ka = inputs.sec                :assert(0x10000000, payload)
			local instr_2 = spaghetti.rshiftk(inputs.instr, 1)
			local rhs_ka_subtract = rhs_ka:bxor(0x3FFFFFFF):bxor(spaghetti.lshift(0x3FFFFFFF, instr_2:bor(0x10000):bsub(0xFFFE)))
			local generate    = lhs_ka:band(rhs_ka_subtract):assert(0x10000000, payload)
			local propagate   = lhs_ka:bxor(rhs_ka_subtract):assert(0x20000000, payload)
			local onebit_sums = lhs_ka:bxor(rhs_ka)         :assert(0x20000000, payload)
			for i = 0, 3 do
				local bit_i_m1 = bitx.lshift(1, i)
				local propagate_fill     = bitx.lshift(1, bit_i_m1) - 1
				local keepalive = bitx.rshift(0x20000000, bit_i_m1)
				local generate_shifted  = spaghetti.lshiftk(generate :bor(keepalive), bit_i_m1)
				local propagate_shifted = spaghetti.lshiftk(propagate:bor(keepalive), bit_i_m1)
				if i == 2 then
					generate_shifted  = spaghetti.lshiftk(generate :bor(0x01000000), bit_i_m1):bor(0x20000000)
					propagate_shifted = spaghetti.lshiftk(propagate:bor(0x01000000), bit_i_m1):bor(0x20000000)
 				end
				generate  = propagate:band(generate_shifted ):bor(generate)
				propagate = propagate:band(propagate_shifted :bor(propagate_fill))
			end
			generate:assert(0x30000000, payload)
			propagate:assert(0x20000000, payload)
			local carry_in              = inputs.flags:band(0x1000FFFF):band(inputs.instr):bsub(0xFFFE):assert(0x10000000, 0x00000001)
			local propagate_conditional = propagate:band(spaghetti.lshift(0x3FFFFFFF, carry_in))       :assert(0x20000000, payload)
			local carries_no_in         = generate:bor(propagate_conditional)                          :assert(0x30000000, payload)
			local outputs = {}
			if params.core_type == "m" then
				local generate_27 = propagate:band(spaghetti.lshiftk(generate:bor(0x1000), 16):bor(0x20000000)):bor(generate)
				local carries_27 = spaghetti.lshiftk(generate_27, 1)
				outputs.sum_27 = onebit_sums:bxor(carries_27:bor(0x10000000)):assert(0x10000000, 0x0FFFFFFF):force(0x10000000, 0x07FFFFFF)
				carries_no_in = carries_no_in:band(0x1000FFFF):assert(0x10000000, 0x0000FFFF)
			end
			local carries    = spaghetti.lshiftk(carries_no_in, 1):bor(carry_in):assert(0x30000000, 0x0001FFFF)
			local carries_15 = spaghetti.rshiftk(carries, 15)                   :assert(0x00006000, 0x00000003)
			local carry      = spaghetti.rshiftk(carries, 16)                   :bor(0x00010000):bsub(0xFFFE)
			local overflow   = carries_15:bxor(carry)                           :bor(0x00010000):bsub(0xFFFE)
			outputs.overflow_carry = spaghetti.lshiftk(overflow, 1):bor(carry):bor(0x10000000):band(0x1000000F)
			outputs.res_add        = onebit_sums:bxor(carries):band(0x1000FFFF)
			return outputs
		end,
		fuzz_inputs = function(inputs)
			local instr = math.random(0x00000000, 0x0001FFFF)
			local pri = math.random(0x0000, payload)
			local sec = math.random(0x0000, payload)
			if bitx.band(instr, 0x000E) == 0x000E then
				pri = math.random(0x0000, payload)
				sec = math.random(0x0000, payload - pri)
			end
			return {
				pri   = bitx.bor(0x10000000, pri),
				sec   = bitx.bor(0x10000000, sec),
				flags = bitx.bor(0x10000000, math.random(0x0, 0xB), bitx.lshift(math.random(0x0000, 0xFFFF), 4)),
				instr = bitx.bor(0x30000000, instr),
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
			local outputs = {
				res_add        = bitx.bor(0x10000000, sum % 0x10000),
				overflow_carry = bitx.bor(bitx.bor(0x10000000, carry_out), overflow_out),
			}
			if params.core_type == "m" then
				local pri_27 = bitx.band(inputs.pri, 0x7FFFFFF)
				local sec_27 = bitx.band(inputs.sec, 0x7FFFFFF)
				local sum_27 = pri_27 + sec_27
				local check_27 = bitx.band(inputs.instr, 0x000E) == 0x000E
				outputs.sum_27 = check_27 and bitx.bor(0x10000000, sum_27) or false
			end
			return outputs
		end,
	}
end)
