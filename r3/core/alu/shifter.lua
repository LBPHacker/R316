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
		{ name = "pri", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "res_shl", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_shr", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
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
