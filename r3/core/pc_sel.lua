local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.pc_sel",
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
		{ name = "pc"       , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_incr"  , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_jump"  , index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "state"    , index = 7, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "condition", index = 9, keepalive = 0x00010000, payload = 0x00000001, initial = 0x00010000 },
	},
	outputs = {
		{ name = "pc", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local state_1 = spaghetti.rshiftk(inputs.state, 1)
		local state_2 = spaghetti.rshiftk(state_1     , 1)
		local state_3 = spaghetti.rshiftk(state_2     , 1)
		local keep_pc = state_1:bor(state_2):bor(state_3)
		local sel_1 = spaghetti.select(inputs.condition:band(1):zeroable(), inputs.pc_jump, inputs.pc_incr)
		local sel_2 = spaghetti.select(keep_pc:band(1):zeroable(), inputs.pc, sel_1)
		return {
			pc = sel_2,
		}
	end,
	fuzz_inputs = function()
		return {
			pc        = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			pc_incr   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			pc_jump   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			state     = bitx.bor(0x10000000, util.any_state()),
			condition = bitx.bor(0x00010000, math.random(0x00000000, 0x00000001)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pc        = bitx.band(inputs.pc       , 0xFFFF)
		local pc_incr   = bitx.band(inputs.pc_incr  , 0xFFFF)
		local pc_jump   = bitx.band(inputs.pc_jump  , 0xFFFF)
		local state     = bitx.band(inputs.state    , 0x000F)
		local condition = bitx.band(inputs.condition, 0x0001)
		local pc_out = condition == 1 and pc_jump or pc_incr
		if bit.band(state, 0xE) ~= 0 then
			-- bit 1: read_2
			-- bit 2: write_2
			-- bit 3: halt
			pc_out = pc
		end
		return {
			pc = bitx.bor(0x10000000, pc_out),
		}
	end,
})
