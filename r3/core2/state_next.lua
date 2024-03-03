local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core2.util")

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
		{ name = "state"   , index = 1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "instr"   , index = 3, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "sync_bit", index = 5, keepalive = 0x00010000, payload = 0x00000007, initial = 0x00010000 },
	},
	outputs = {
		{ name = "state", index = 1, keepalive = 0x10000000, payload = 0x0000000F },
	},
	func = function(inputs)
		local instr_not_ld  = util.op_is_not_k(inputs.instr,  2)
		local instr_not_st  = util.op_is_not_k(inputs.instr, 10)
		local instr_not_hlt = util.op_is_not_k(inputs.instr, 11)
		local normal_shift = spaghetti.constant(2):bor(instr_not_ld)
		                                :lshift(2):bor(instr_not_st)
		                                :lshift(2):bor(instr_not_hlt):bxor(7):assert(0x3E000008, 0x00070007)
		local from_normal  = inputs.state:bsub(0xFFFE):bor(0x10000)
		                                 :lshift(8)
		                                 :rshift(normal_shift):never_zero()
		local from_read_2  = inputs.state:rshift(2):bsub(0xFFFE)
		local from_write_2 = inputs.state:rshift(4):bsub(0xFFFE)
		local halt_bit     = spaghetti.rshiftk(inputs.sync_bit, 1):bor(0x10000):bsub(0xFFFE):assert(0x00010000, 0x00000001)
		local start_bit    = spaghetti.rshiftk(inputs.sync_bit, 2):bor(0x10000):bsub(0xFFFE):assert(0x00010000, 0x00000001)
		local start_shift  = spaghetti.constant(8):bor(start_bit)                           :assert(0x00010008, 0x00000001)
		local from_halt    = inputs.state:rshift(8):bsub(0xFFFE):lshift(start_shift):never_zero()
		local state = from_normal:bor(from_read_2 )
		                         :bor(from_write_2)
		                         :bor(from_halt   ):assert(0x0C000000, 0x120F000F)
		local to_halt = state:bor(0x10000):band(halt_bit):assert(0x00010000, 0x00000001)
		local state_with_halt = state:bxor(to_halt):bxor(spaghetti.lshiftk(to_halt, 3))
		return {
			state = state_with_halt:bor(0x10000000):band(0x1000000F),
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
			if bitx.band(inputs.sync_bit, 0x00000004) ~= 0 then
				state_next = 1
			else
				state_next = 8
			end
		else
			return nil, "invalid state"
		end
		if state_next == 1 and bitx.band(inputs.sync_bit, 0x00000002) ~= 0 then
			state_next = 8
		end
		return {
			state = bitx.bor(0x10000000, state_next),
		}
	end,
})
