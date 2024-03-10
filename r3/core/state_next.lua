local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.state_next",
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
		{ name = "state"   , index = 1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "instr"   , index = 3, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "sync_bit", index = 5, keepalive = 0x00010000, payload = 0x00000019, initial = 0x00010000 },
	},
	outputs = {
		{ name = "state", index = 1, keepalive = 0x10000000, payload = 0x0000000F },
	},
	func = function(inputs)
		local instr_not_ld  = util.op_is_not_k(inputs.instr,  2)
		local instr_not_st  = util.op_is_not_k(inputs.instr, 10)
		local instr_not_hlt = util.op_is_not_k(inputs.instr, 11)
		local normal        = inputs.state:bsub(0xFFFE):bor(0x00001000)
		local normal_ld     = normal:bsub(instr_not_ld ):assert(0x00001000, 0x00000001)
		local normal_st     = normal:bsub(instr_not_st ):assert(0x00001000, 0x00000001)
		local normal_hlt    = normal:bsub(instr_not_hlt):assert(0x00001000, 0x00000001)
		local keep_halt     = spaghetti.rshiftk(inputs.state:bsub(inputs.sync_bit), 3)
		local normal_shift  = spaghetti.constant(2):bor(normal_ld)
		                                 :lshift(2):bor(normal_st)
		                                 :lshift(2):bor(normal_hlt):bor(keep_halt):assert(0x02007008, 0x00000007)
		local wo_ehalt    = spaghetti.constant(8):rshift(normal_shift):never_zero()
		local ehalt_shift = wo_ehalt:bor(0x1000):band(spaghetti.rshiftk(inputs.sync_bit, 4)):bor(8)
		local state = wo_ehalt:lshift(8):never_zero()
		                      :rshift(ehalt_shift):never_zero()
		                      :bor(0x10000000):force(0x10000000, 0x0000000F) -- spaghetti insists that this can be 7F
		return {
			state = state,
		}
	end,
	fuzz_inputs = function()
		return {
			state    = bitx.bor(0x10000000, util.any_state()),
			instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
			sync_bit = bitx.bor(0x00010000, util.any_sync_bit()),
		}
	end,
	fuzz_outputs = function(inputs)
		local state = bitx.band(inputs.state, 0x000F)
		local op    = bitx.band(inputs.instr, 0x000F)
		local state_next
		if state == 1 then
			if op == 2 then
				state_next = 2
			elseif op == 10 then
				state_next = 4
			elseif op == 11 then
				state_next = 8
			else
				state_next = 1
			end
		elseif state == 2 then
			state_next = 1
		elseif state == 4 then
			state_next = 1
		elseif state == 8 then
			if bitx.band(inputs.sync_bit, 0x0008) ~= 0 then
				state_next = 1
			else
				state_next = 8
			end
		else
			return nil, "invalid state"
		end
		if state_next == 1 and bitx.band(inputs.sync_bit, 0x0010) ~= 0 then
			state_next = 8
		end
		return {
			state = bitx.bor(0x10000000, state_next),
		}
	end,
})
