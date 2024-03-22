local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "test",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
		seed          = { 0x09CD4599, 0x1D4A7066 },
	},
	stacks      = 1,
	unclobbered = {   9,  10,  12,  13,  14,  15,
	                -12, -13, -14, -15, -16, -17 },
	compute_operands = { 3, 5, 7, -3, -5, -8, -10 },
	compute_results  = { 4, 6, 8, -4, -6, -9, -11 },
	inputs = {
		{ name = "pri", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec", index = -7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "res_and", index =  11, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		return {
			res_and = inputs.sec:band(inputs.pri),
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
		return {
			res_and = bitx.bor(0x10000000, bitx.band(sec, pri)),
		}
	end,
})
