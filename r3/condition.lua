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
	work_slots    = 20,
	inputs = {
		{ name = "corestate", index = 1, keepalive = 0x10000000, payload = 0x007FFFFF, initial = 0x10000000 },
		{ name = "op_bits"  , index = 3, keepalive = 0x10000000, payload = 0x01F00000, initial = 0x10000000 },
	},
	outputs = {
		{ name = "condition", index = 1, keepalive = 0x00010000, payload = 0x00000001 },
	},
	func = function(inputs, params)
		local sync_value = params.sync_value
		local flags = spaghetti.rshiftk(inputs.corestate, 16):assert(0x00001000, 0x0000007F):bsub(0x00F0)
		local flag_be = spaghetti.rshiftk(flags, 2):bor(flags)                       :bsub(0x000E)
		local flag_l  = spaghetti.rshiftk(flags, 3):bxor(spaghetti.rshiftk(flags, 1)):bsub(0x000E)
		local flag_ng = spaghetti.rshiftk(flags, 2):bor(flag_l)                      :bsub(0x000E)
		local extended = flags
			:lshift(0x2):bor(spaghetti.constant(0, 1))
			:lshift(0x2):bor(flag_ng)
			:lshift(0x2):bor(flag_be)
			:lshift(0x2):bor(flag_l)
			:assert(0x00013A00, 0x000000FF)
		local op_bits = spaghetti.rshiftk(inputs.op_bits, 20)
		for i = 0, 2 do
			local i22 = bitx.lshift(1, bitx.lshift(1, i))
			local shift = spaghetti.rshiftk(op_bits, i):bor(0x00010000):band(0x00010001):bor(i22)
			shift:assert(bitx.bor(0x10000, i22), 1) -- lsb is one of: 1 << (1 << i), 0
			extended = extended:rshift(shift):never_zero()
		end
		local inv = spaghetti.rshiftk(op_bits, 3):bor(0x00010000):band(0x00010001)
		local sync = spaghetti.rshiftk(op_bits, 4):bor(0x00010000):band(0x00010001)
		if sync_value then
			sync = 0x00010001
		end
		local extended_pinv = extended:bxor(inv):never_zero()
		local condition = extended_pinv:bor(0x00010000):band(sync)
		return {
			condition = condition,
		}
	end,
	fuzz = function(params)
		local sync_value = params.sync_value
		local old_corestate =
			math.random(0x00000000, 0x0000FFFF) +
			math.random(0x00000000, 0x0000000B) * 0x10000 +
			math.random(0x00000000, 0x00000007) * 0x100000
		local op_bits = math.random(0x0, 0x1F)
		local flag_c = bitx.band(old_corestate, 0x10000) ~= 0
		local flag_o = bitx.band(old_corestate, 0x20000) ~= 0
		local flag_z = bitx.band(old_corestate, 0x40000) ~= 0
		local flag_s = bitx.band(old_corestate, 0x80000) ~= 0
		local flag_be = flag_c or flag_z
		local flag_l  = flag_s ~= flag_o
		local flag_ng = flag_l or flag_z
		local flat_t  = true
		local extended = bitx.bor(
			flag_c  and 0x10 or 0x00,
			flag_o  and 0x20 or 0x00,
			flag_z  and 0x40 or 0x00,
			flag_s  and 0x80 or 0x00,
			flag_l  and 0x01 or 0x00,
			flag_be and 0x02 or 0x00,
			flag_ng and 0x04 or 0x00,
			flat_t  and 0x08 or 0x00
		)
		local inv = bitx.band(bitx.rshift(op_bits, 3), 1)
		local condition = bitx.bxor(bitx.band(bitx.rshift(extended, bitx.bxor(bitx.band(op_bits, 7), 7)), 1), inv)
		if not sync_value then
			local sync = bitx.band(bitx.rshift(op_bits, 4), 1)
			condition = bitx.band(condition, sync)
		end
		return {
			inputs = {
				corestate = bitx.bor(0x10000000, old_corestate),
				op_bits   = bitx.bor(0x10000000, bitx.lshift(op_bits, 20)),
			},
			outputs = {
				condition = bitx.bor(0x00010000, condition),
			},
		}
	end,
})
