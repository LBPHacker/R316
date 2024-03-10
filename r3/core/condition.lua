local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.condition",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-7,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 12,
	inputs = {
		{ name = "flags"   , index = 1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "sync_bit", index = 3, keepalive = 0x00010000, payload = 0x00000019, initial = 0x00010000 },
		{ name = "instr"   , index = 5, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
	},
	outputs = {
		{ name = "condition", index = 1, keepalive = 0x00010000, payload = 0x00000001 },
	},
	func = function(inputs)
		local instr_not_jmp  = util.op_is_not_k(inputs.instr, 1)
		local flag_c  = inputs.flags
		local flag_o  = spaghetti.rshiftk(flag_c, 1)
		local flag_z  = spaghetti.rshiftk(flag_o, 1)
		local flag_s  = spaghetti.rshiftk(flag_z, 1)
		local flag_be = flag_c:bor(flag_z) :assert(0x14000000, 0x0000000F)
		local flag_l  = flag_s:bxor(flag_o):assert(0x0A000000, 0x00000007)
		local flag_ng = flag_l:bor(flag_z) :assert(0x0E000000, 0x00000007)
		local flag_only_be = flag_be:bsub(0xFFFE):assert(0x14000000, 0x00000001)
		local flag_only_l  = flag_l :bsub(0xFFFE):assert(0x0A000000, 0x00000001)
		local flag_only_ng = flag_ng:bsub(0xFFFE):assert(0x0E000000, 0x00000001)
		local flag_array = spaghetti.constant(0x02):bor(flag_only_be)
		                              :lshift(0x02):bor(flag_only_l)
		                              :lshift(0x02):bor(flag_only_ng)
		                              :lshift(0x10):bor(inputs.flags):assert(0x30000080, 0x0000007F)
		local instr = spaghetti.rshiftk(inputs.instr, 4)
		for i = 0, 2 do
			local i22 = bitx.lshift(1, bitx.lshift(1, i))
			local shift = instr:bsub(0xFFFE):bor(i22)
			instr = spaghetti.rshiftk(instr, 1)
			shift:assert(bitx.bor(bitx.rshift(0x03000000, i), i22), 1) -- lsb is one of: 1 << (1 << i), 0
			flag_array = flag_array:rshift(shift):never_zero() -- thus flag_array gets rshifted at most 7 bits throughout the loop
		end
		instr:assert(0x00600000, 0x000003FF)
		-- and so at this point it still definitely has some high bits set;
		-- things get a bit weird here though because we bxor with instr,
		-- which could potentially turn the all the remaining keepalives off, so we bor 10000
		flag_array = flag_array:bor(0x00010000):bxor(instr):never_zero()
		instr = spaghetti.rshiftk(instr, 1)
		local have_sync = inputs.sync_bit:bor(instr):assert(0x00310000, 0x000001FF)
		local have_sync_jmp = have_sync:bsub(instr_not_jmp:band(0x1000000F)):assert(0x00310000, 0x000001FF)
		flag_array = flag_array:band(have_sync_jmp):never_zero()
		return {
			condition = flag_array:bor(0x00010000):band(0x00010001),
		}
	end,
	fuzz_inputs = function()
		return {
			flags    = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			sync_bit = bitx.bor(0x00010000, util.any_sync_bit()),
			instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local sync_bit         = bitx.band(inputs.sync_bit, 0x1) ~= 0
		local op               = bitx.band(inputs.instr, 0x000F)
		local flag_array_index = bitx.bxor(bitx.band(bitx.rshift(inputs.instr, 4), 7), 7)
		local invert           = bitx.band(inputs.instr, 0x0080) ~= 0
		local ignore_sync      = bitx.band(inputs.instr, 0x0100) ~= 0
		local flag_c  = bitx.band(inputs.flags, 0x1) ~= 0
		local flag_o  = bitx.band(inputs.flags, 0x2) ~= 0
		local flag_z  = bitx.band(inputs.flags, 0x4) ~= 0
		local flag_s  = bitx.band(inputs.flags, 0x8) ~= 0
		local flag_be = flag_c or flag_z
		local flag_l  = flag_s ~= flag_o
		local flag_ng = flag_l or flag_z
		local flat_t  = true
		local flag_array = bitx.bor(
			flat_t  and 0x80 or 0x00,
			flag_be and 0x40 or 0x00,
			flag_l  and 0x20 or 0x00,
			flag_ng and 0x10 or 0x00,
			flag_s  and 0x08 or 0x00,
			flag_z  and 0x04 or 0x00,
			flag_o  and 0x02 or 0x00,
			flag_c  and 0x01 or 0x00
		)
		local flag_set = bitx.band(bitx.rshift(flag_array, flag_array_index), 1) ~= 0
		local flag_good = flag_set ~= invert
		if not ignore_sync then
			flag_good = flag_good and sync_bit
		end
		flag_good = flag_good and op == 1
		return {
			condition = bitx.bor(0x00010000, flag_good and 1 or 0),
		}
	end,
})
