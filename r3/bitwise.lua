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
		{ name = "pri_in", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000DEAD },
		{ name = "sec_in", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BEEF },
	},
	outputs = {
		{ name = "l_and", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "l_or" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "l_xor", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "l_clr", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		return {
			l_and = inputs.sec_in:band(inputs.pri_in),
			l_or  = inputs.sec_in:bor (inputs.pri_in),
			l_xor = inputs.sec_in:bxor(0x30000000):bxor(inputs.pri_in):bxor(0x20000000),
			l_clr = inputs.sec_in:bxor(0x30000000):bsub(inputs.pri_in):bxor(0x30000000),
		}
	end,
	fuzz = function()
		local pri = math.random(0x0000, 0xFFFF)
		local sec = math.random(0x0000, 0xFFFF)
		return {
			inputs = {
				pri_in = bitx.bor(0x10000000, pri),
				sec_in = bitx.bor(0x10000000, sec),
			},
			outputs = {
				l_and = bitx.bor(0x10000000, bitx.band(sec, pri)),
				l_or  = bitx.bor(0x10000000, bitx.bor (sec, pri)),
				l_xor = bitx.bor(0x10000000, bitx.bxor(sec, pri)),
				l_clr = bitx.bor(0x10000000, bitx.band(sec, bitx.bxor(pri, 0xFFFF))),
			},
		}
	end,
})
