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
		{ name = "pc", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "pc", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local inverted  = inputs.pc:bxor(0x3FFFFFFF)
		local incr_mask = spaghetti.lshift(0x3FFFFFFE, inverted):bxor(0x3FFFFFFF)
		local result    = inputs.pc:bxor(incr_mask):bsub(0x00010000)
		return {
			pc = result,
		}
	end,
	fuzz_inputs = function()
		return {
			pc = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pc = bitx.band(inputs.pc, 0xFFFF)
		return {
			pc = bitx.bor(0x10000000, (pc + 1) % 0x10000),
		}
	end,
})
