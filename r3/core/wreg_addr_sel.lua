local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

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
		{ name = "instr", index = 1, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "wreg_addr", index = 1, keepalive = 0x10000000, payload = 0x0000001F },
	},
	func = function(inputs)
		local addr           = spaghetti.rshiftk(inputs.instr, 9):bor(0x10000000):band(0x1000001F)
		local instr_not_st   = util.op_is_not_k(inputs.instr, 10)
		local st_addr_0_mask = spaghetti.constant(0x3FFFFFFF):lshift(instr_not_st:bor(0x20)):assert(0x3FFFFFE0, 0x0000001F)
		local wreg_addr      = addr:band(st_addr_0_mask)
		return {
			wreg_addr = wreg_addr,
		}
	end,
	fuzz_inputs = function()
		return {
			instr = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local addr = bitx.band(bitx.rshift(inputs.instr, 9), 0x001F)
		local op   = bitx.band(            inputs.instr    , 0x000F)
		return {
			wreg_addr = bitx.bor(0x10000000, op == 10 and 0 or addr),
		}
	end,
})
