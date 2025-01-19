local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module(function(params)
	return {
		tag = "core.curr_instr_sel",
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
			{ name = "state"   , index =  1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "instr"   , index =  3, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
			{ name = "ram_high", index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "ram_low" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "st_addr" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			params.for_mcore and { name = "res_mulh", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 } or nil,
		},
		outputs = {
			{ name = "curr_instr", index = 1, keepalive = 0x10000000, payload = 0x0001FFFF },
			{ name = "curr_imm"  , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local instr_not_ld  = util.op_is_not_k(inputs.instr,  2, 0x0F)
			local instr_not_st  = util.op_is_not_k(inputs.instr, 10, 0x0F)
			local instr_not_mul = util.op_is_not_k(inputs.instr, 14, 0x0F)
			local instr_not_any = instr_not_ld:band(instr_not_st)
			if params.for_mcore then
				instr_not_any = instr_not_any:band(instr_not_mul)
			end
			local curr_instr_valid = spaghetti.rshiftk(inputs.state, 2):bor(instr_not_any:bxor(1)):assert(0x3E000000, 0x00010003)
			local ld_instr         = inputs.instr:bor(0x8000):bxor(3)               :assert(0x30008000, 0x00017FFF) -- turns 2 (ld) into 1 with flags enabled (hlt)
			local st_instr         = spaghetti.rshiftk(inputs.instr, 5):bsub(0xFE0F):bor(0x10000000):assert(0x11800000, 0x000001F0)
			local mul_instr        = inputs.instr:bor(0x4000):bsub(0x8000):bxor(0x200):bsub(0xF)
			local curr_instr_ld    = spaghetti.select(instr_not_ld:band(1):zeroable(), inputs.ram_high, ld_instr):assert(0x10000000, 0x2001FFFF)
			local curr_instr_ld_st, curr_imm_ld_st = spaghetti.select(instr_not_st:band(1):zeroable(), curr_instr_ld, st_instr, inputs.ram_low, inputs.st_addr)
			local curr_instr_ld_st_mul, curr_imm
			if params.for_mcore then
				curr_instr_ld_st_mul, curr_imm = spaghetti.select(instr_not_mul:band(1):zeroable(), curr_instr_ld_st, mul_instr, curr_imm_ld_st, inputs.res_mulh)
			else
				curr_instr_ld_st_mul, curr_imm = curr_instr_ld_st, curr_imm_ld_st
			end
			curr_instr_ld_st_mul:assert(0x10000000, 0x2181FFFF)
			local curr_instr_valid_sane = spaghetti.lshiftk(curr_instr_valid:bsub(0xFFFE):bor(0x1000), 16):assert(0x10000000, 0x00010000)
			local curr_instr       = curr_instr_ld_st_mul:band(0x1000FFFF):bor(curr_instr_valid_sane)
			return {
				curr_instr = curr_instr,
				curr_imm   = curr_imm,
			}
		end,
		fuzz_inputs = function()
			local state, instr = util.any_state_instr()
			return {
				state    = bitx.bor(0x10000000, state),
				instr    = bitx.bor(0x30000000, instr),
				ram_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				ram_low  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				st_addr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
				res_mulh = params.for_mcore and bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)) or nil,
			}
		end,
		fuzz_outputs = function(inputs)
			local state    = bitx.band(inputs.state, 0x000F)
			local op       = bitx.band(inputs.instr, 0x000F)
			local st_addr  = bitx.band(inputs.st_addr, 0xFFFF)
			local curr_instr_valid = (op == 2 or op == 10 or (params.for_mcore and op == 14) or bitx.band(state, 4) ~= 0) and 0x00010000 or 0x00000000
			local curr_instr = inputs.ram_high
			local curr_imm   = bitx.band(inputs.ram_low, 0xFFFF)
			if op == 2 then
				curr_instr = bitx.bor(bitx.band(inputs.instr, 0x7FF0), 0x8001)
			elseif params.for_mcore and op == 14 then
				curr_instr = bitx.bxor(bitx.bor(bitx.band(inputs.instr, 0x3FF0), 0x4000), 0x0200)
				curr_imm   = bitx.band(inputs.res_mulh, 0xFFFF)
			elseif op == 10 then
				local wreg_addr = bitx.band(bitx.rshift(inputs.instr, 9), 0x001F)
				curr_instr = bitx.lshift(wreg_addr, 4)
				curr_imm   = st_addr
			end
			return {
				curr_instr = bitx.bor(0x10000000, curr_instr, curr_instr_valid),
				curr_imm   = bitx.bor(0x10000000, curr_imm),
			}
		end,
	}
end)
