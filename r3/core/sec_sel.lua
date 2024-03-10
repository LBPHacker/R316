local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")

return testbed.module({
	tag = "core.sec_sel",
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
		{ name = "instr"  , index = 1, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "imm"    , index = 3, keepalive = 0x30000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec_reg", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "sec", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local sec = spaghetti.select(inputs.instr:band(0x4000):zeroable(), inputs.imm:bxor(0x20000000), inputs.sec_reg)
		return {
			sec = sec,
		}
	end,
	fuzz_inputs = function()
		return {
			instr   = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
			imm     = bitx.bor(0x30000000, math.random(0x00000000, 0x0000FFFF)),
			sec_reg = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local imm     = bitx.band(inputs.imm    , 0xFFFF)
		local sec_reg = bitx.band(inputs.sec_reg, 0xFFFF)
		local sec     = bitx.band(inputs.instr, 0x4000) ~= 0 and imm or sec_reg
		return {
			sec = bitx.bor(0x10000000, sec),
		}
	end,
})
