local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.alu.shifter",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
		seed          = { 0xDEADBEEF, 0xCAFEBABE },
	},
	stacks        = 1,
	unclobbered = {  11, 12,  13,  14,  15,  16,  17, 22, 23, 24, 25, 26, 27,
	                -12, -14, -15, -16, -17, -22, -23, -24, -25, -26, -27 },
	compute_operands = { 3, 5, 7,  9, 18, 20, -3, -5, -8, -10, -18, -20 },
	compute_results  = { 4, 6, 8, 10, 19, 21, -4, -6, -9, -11, -19, -21 },
	inputs = {
		{ name = "pri", index = -7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec", index = -13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "res_shl", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_shr", index = 13, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local shift_total = spaghetti.constant(0x8000)
		for i = 0, 3 do
			local i22 = bitx.lshift(1, bitx.lshift(1, i))
			local shift = spaghetti.rshiftk(inputs.sec, i):bsub(0xFFFE):bor(i22)
			shift_total = shift_total:rshift(shift):never_zero()
		end
		local keepalive_shifted = spaghetti.constant(0x10000000):rshift(shift_total):never_zero()
		local right = inputs.pri:rshift(shift_total):never_zero()
		                        :bxor(0x30000000)
		                        :bxor(keepalive_shifted)
		                        :bxor(0x20000000):force(0x10000000, 0x0000FFFF)
		local left = inputs.pri:bor(keepalive_shifted)
		                       :lshift(shift_total):never_zero()
		                       :band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
		return {
			res_shl = left,
			res_shr = right,
		}
	end,
	fuzz_inputs = function()
		return {
			pri = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pri = bitx.band(inputs.pri, 0xFFFF)
		local sec = bitx.band(inputs.sec, 0xFFFF)
		local amount = bitx.band(sec, 0x000F)
		return {
			res_shl = bitx.bor(0x10000000, bitx.band(bitx.lshift(pri, amount), 0x0000FFFF)),
			res_shr = bitx.bor(0x10000000, bitx.band(bitx.rshift(pri, amount), 0x0000FFFF)),
		}
	end,
})
