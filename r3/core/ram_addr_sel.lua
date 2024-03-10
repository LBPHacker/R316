local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.ram_addr_sel",
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
		{ name = "pc"      , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ld_addr" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "st_addr" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_mask", index = 11, keepalive = 0x20000000, payload = 0x0000FFFF, initial = 0x20000000 },
	},
	outputs = {
		{ name = "ram_addr", index = 1, keepalive = 0x10000000, payload = 0x000FFFFF },
	},
	func = function(inputs)
		local instr_not_ld        = util.op_is_not_k(inputs.instr, 2)
		local rewrite_ld_sel_mask = spaghetti.constant(0x3FFFFFFF):lshift(instr_not_ld:bor(0x000010000))
		local write_2             = spaghetti.rshiftk(inputs.state, 2):bsub(0xFFFE)              :assert(0x04000000, 0x00000001)
		local rewrite_st_sel_mask = spaghetti.constant(0x3FFFFFFF):lshift(write_2:bor(0x00010000):assert(0x04010000, 0x00000001))
		local addr_with_ld        = inputs.ld_addr:bxor(inputs.pc:bor(0x00010000)):band(rewrite_ld_sel_mask):bxor(inputs.ld_addr):assert(0x10010000, 0x0000FFFF)
		local addr_with_ld_st     = addr_with_ld:bxor(inputs.st_addr):band(rewrite_st_sel_mask):bxor(addr_with_ld)               :assert(0x10000000, 0x0000FFFF)
		local external_bits  = addr_with_ld_st:bsub(inputs.ram_mask):bor(0x00010000):assert(0x10010000, 0x0000FFFF)
		local external_shift = spaghetti.constant(0x1000FFFF):rshift(external_bits):never_zero()
		local external       = external_shift:bor(2):assert(0x00000002, 0x1FFFFFFD)
		local control_rw = spaghetti.constant(2):rshift(external):never_zero()
		local control    = control_rw:lshift(write_2:bor(4)):never_zero()
		local control_16 = spaghetti.lshiftk(control, 16):never_zero()
		return {
			ram_addr = addr_with_ld_st:bor(control_16),
		}
	end,
	fuzz_inputs = function()
		local state, instr = util.any_state_instr()
		return {
			state    = bitx.bor(0x10000000, state),
			instr    = bitx.bor(0x30000000, instr),
			pc       = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			ld_addr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			st_addr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			ram_mask = bitx.bor(0x20000000, math.random(0x00000000, 0x0000FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local state    = bitx.band(inputs.state   , 0x000F)
		local op       = bitx.band(inputs.instr   , 0x000F)
		local ram_mask = bitx.band(inputs.ram_mask, 0xFFFF)
		local pc       = bitx.band(inputs.pc      , 0xFFFF)
		local ld_addr  = bitx.band(inputs.ld_addr , 0xFFFF)
		local st_addr  = bitx.band(inputs.st_addr , 0xFFFF)
		local ram_addr = pc
		if state == 4 then
			ram_addr = st_addr
		elseif op == 2 then
			ram_addr = ld_addr
		end
		local control = state == 4 and 1 or 4
		if bitx.band(ram_addr, bitx.bxor(ram_mask, 0xFFFF)) ~= 0 then
			control = bitx.lshift(control, 1)
		end
		return {
			ram_addr = bitx.bor(0x10000000, ram_addr, bitx.lshift(control, 16)),
		}
	end,
})
