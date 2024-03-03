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
		{ name = "pri"  , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"  , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flags", index = 5, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x1000000B },
		{ name = "instr", index = 7, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
	},
	outputs = {
		{ name = "res_add"       , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "overflow_carry", index = 3, keepalive = 0x10000000, payload = 0x00000003 },
	},
	func = function(inputs)
		-- TODO: implement an actual adder
		local pri = inputs.pri
		local sec = inputs.sec
		local dummy = inputs.flags:bor(inputs.instr):band(0x3FFF0000)
		return {
			res_add        = pri:bor(sec),
			overflow_carry = pri:bor(sec):bor(dummy):band(0x10000003),
		}
	end,
	fuzz_inputs = function()
		return {
			pri   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			flags = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			instr = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pri = bitx.band(inputs.pri, 0xFFFF)
		local sec = bitx.band(inputs.sec, 0xFFFF)
		return {
			res_add        = bitx.bor(0x10000000, bitx.bor(sec, pri)),
			overflow_carry = bitx.bor(0x10000000, bitx.band(bitx.bor(sec, pri), 3)),
		}
	end,
})
