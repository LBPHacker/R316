local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.unstack_high",
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
		{ name = "both_halves", index = 1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
	},
	outputs = {
		{ name = "high_half", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "low_half" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local high_at_8 = spaghetti.rshiftk(inputs.both_halves:bor(0x100):bsub(0xFF), 8)
		local high_at_0 = spaghetti.rshiftk(high_at_8:bor(0x30000000):bsub(0xFF), 8)
		local high_half = high_at_0:bor(0x10000000):band(0x1000FFFF)
		local low_half  = inputs.both_halves:bor(0x10000000):band(0x1000FFFF)
		return {
			high_half = high_half,
			low_half  = low_half,
		}
	end,
	fuzz_inputs = function()
		return {
			both_halves = testbed.any(),
		}
	end,
	fuzz_outputs = function(inputs)
		return {
			high_half = bitx.bor(0x10000000, bitx.rshift(inputs.both_halves, 16)),
			low_half  = bitx.bor(0x10000000, bitx.band(inputs.both_halves, 0xFFFF)),
		}
	end,
})
