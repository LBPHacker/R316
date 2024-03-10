local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.stack_high",
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
		{ name = "high_half", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "low_half" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "both_halves", index = 1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "high_half_16", index = 3, keepalive = 0x00000001, payload = 0xFFFF0000 },
	},
	func = function(inputs)
		local high_8 = spaghetti.select(inputs.high_half:band(0x8000):zeroable(), 0x80000001, 1)
		local high_4 = spaghetti.select(inputs.high_half:band(0x4000):zeroable(), 0x40000001, 1)
		local high_half_16    = spaghetti.lshiftk(spaghetti.lshiftk(inputs.high_half:bor(0x00010000), 8):bor(1), 8):bor(high_8):bor(high_4):bsub(0xFFFE)
		local low_half        = inputs.low_half:bxor(1)
		local high_half_2     = spaghetti.lshiftk(inputs.high_half:bor(0x00010000), 2)
		local force_keepalive = spaghetti.select(high_half_2:bor(inputs.low_half):band(0xFFFF):zeroable(), 0x10000000, 0x30000000)
		local both_halves     = high_half_16:bxor(force_keepalive):bxor(low_half):never_zero()
		return {
			both_halves = both_halves,
			high_half_16 = high_half_16:bxor(force_keepalive),
		}
	end,
	fuzz_inputs = function()
		return {
			high_half = bitx.bor(0x10000000, math.random(0x00000000, 0x0000F) * 0x1000),
			low_half  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000F) * 0x1000),
		}
	end,
	fuzz_outputs = function(inputs)
		local high_half   = bitx.band(inputs.high_half, 0xFFFF)
		local low_half    = bitx.band(inputs.low_half , 0xFFFF)
		local both_halves      = bitx.bor(bitx.lshift(          high_half         , 16), low_half)
		local both_halves_safe = bitx.bor(bitx.lshift(bitx.band(high_half, 0x3FFF), 16), low_half)
		if both_halves_safe == 0 then
			both_halves = bitx.bor(both_halves, 0x20000000)
		end
		return {
			both_halves = both_halves,
			high_half_16 = false,
		}
	end,
})
