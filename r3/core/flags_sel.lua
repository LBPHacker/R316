local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module(function(params)
	return {
		tag = "core.flags_sel",
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
			{ name = "instr"    , index = 1, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
			{ name = "flags_new", index = 3, keepalive = 0x10050000, payload = 0x0000000F, initial = 0x10050000 },
			{ name = "flags_old", index = 5, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10050000 },
		},
		outputs = {
			{ name = "flags", index = 1, keepalive = 0x10000000, payload = 0x0000000F },
		},
		func = function(inputs)
			local instr_bits = util.op_is_bits(inputs.instr, 0x8001, 0x800F)
			local flags_not_hlt = instr_bits[1]:bor(instr_bits[2])
			                                   :bor(instr_bits[3])
			                                   :bor(instr_bits[4])
			                                   :bsub(instr_bits[5])
			local flags_not_any = flags_not_hlt
			if params.for_mcore then
				local flags_not_mul = util.op_is_not_k(inputs.instr, 14, 0x0F)
				local flags_not_mullh = util.op_is_not_k(inputs.instr, 8, 0x0E)
				flags_not_any = flags_not_any:band(flags_not_mul):band(flags_not_mullh)
			end
			local flags = spaghetti.select(flags_not_any:band(1):zeroable(), inputs.flags_new, inputs.flags_old)
			return {
				flags = flags:band(0x1000000F),
			}
		end,
		fuzz_inputs = function()
			return {
				instr     = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
				flags_new = bitx.bor(0x10050000, math.random(0x00000000, 0x0000000B)),
				flags_old = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			}
		end,
		fuzz_outputs = function(inputs)
			local keep_flags = bitx.band(inputs.instr, 0x8000) == 0 or
			                   bitx.band(inputs.instr, 0x800F) == 0x8001 or
			                   (params.for_mcore and (bitx.band(inputs.instr, 0x0F) == 14 or
			                                          bitx.band(inputs.instr, 0x0E) == 8))
			local flags_new  = bitx.band(inputs.flags_new, 0x000F)
			local flags_old  = bitx.band(inputs.flags_old, 0x000F)
			return {
				flags = bitx.bor(0x10000000, keep_flags and flags_old or flags_new),
			}
		end,
	}
end)
