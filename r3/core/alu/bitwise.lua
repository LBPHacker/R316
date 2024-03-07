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
		{ name = "res_and", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_or" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_xor", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_clr", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		return {
			res_and = inputs.sec:band(inputs.pri),
			res_or  = inputs.sec:bor (inputs.pri),
			res_xor = inputs.sec:bxor(0x30000000):bxor(inputs.pri):bxor(0x20000000),
			res_clr = inputs.sec:bxor(0x30000000):bsub(inputs.pri):bxor(0x30000000),
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
			res_or  = bitx.bor(0x10000000, bitx.bor (sec, pri)),
			res_xor = bitx.bor(0x10000000, bitx.bxor(sec, pri)),
			res_clr = bitx.bor(0x10000000, bitx.band(sec, bitx.bxor(pri, 0xFFFF))),
		}
	end,
})
