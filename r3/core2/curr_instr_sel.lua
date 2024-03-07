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
		{ name = "ram_high", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_low" , index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "st_addr" , index = 9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "curr_instr", index = 1, keepalive = 0x10000000, payload = 0x0001FFFF },
		{ name = "curr_imm"  , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local instr_not_ld = util.op_is_not_k(inputs.instr,  2)
		local instr_not_st = util.op_is_not_k(inputs.instr, 10)
		local curr_instr_valid = spaghetti.rshiftk(inputs.state, 2):bor(instr_not_ld:band(instr_not_st):bxor(1)):assert(0x3E000000, 0x00010003)
		local ld_instr         = inputs.instr:bxor(9)                           :assert(0x30000000, 0x0001FFFF) -- turns 2 (ld) into 11 (hlt)
		local st_instr         = spaghetti.rshiftk(inputs.instr, 5):bsub(0xFE0F):assert(0x01800000, 0x000001F0)
		local st_imm           = inputs.st_addr:bor(0x00010000)
		local ld_sel_mask      = spaghetti.constant(0x3FFFFFFF):lshift(instr_not_ld:bor(0x00010000))
		local st_sel_mask      = spaghetti.constant(0x3FFFFFFF):lshift(instr_not_st:bor(0x00010000))
		local curr_instr_ld    = ld_instr:bxor(inputs.ram_high):band(ld_sel_mask):bxor(ld_instr):assert(0x10000000, 0x0001FFFF)
		local curr_instr_ld_st = st_instr:bxor(curr_instr_ld  ):band(st_sel_mask):bxor(st_instr):assert(0x10000000, 0x0001FFFF)
		local curr_instr_valid_sane = spaghetti.lshiftk(curr_instr_valid:bsub(0xFFFE):bor(0x1000), 16):assert(0x10000000, 0x00010000)
		local curr_instr            = curr_instr_ld_st:band(0x1000FFFF):bor(curr_instr_valid_sane)
		local curr_imm              = st_imm:bxor(inputs.ram_low):band(st_sel_mask):bxor(st_imm)
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
		}
	end,
	fuzz_outputs = function(inputs)
		local state = bitx.band(inputs.state, 0x000F)
		local op    = bitx.band(inputs.instr, 0x000F)
		local st_addr = bitx.band(inputs.st_addr, 0xFFFF)
		local curr_instr_valid = (op == 2 or op == 10 or bitx.band(state, 4) ~= 0) and 0x00010000 or 0x00000000
		local curr_instr = inputs.ram_high
		local curr_imm   = bitx.band(inputs.ram_low, 0xFFFF)
		if op == 2 then
			curr_instr = bitx.bor(bitx.band(inputs.instr, 0xFFF0), 0x000B)
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
})
