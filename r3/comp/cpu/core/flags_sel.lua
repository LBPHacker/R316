local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.comp.cpu.core.util")

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
			{ name = "flags_new", index = 3, keepalive = 0x10050000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "flags_old", index = 5, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
			params.core_type == "m" and { name = "res_mull", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 } or nil,
		},
		outputs = {
			{ name = "flags", index = 1, keepalive = 0x10000000, payload = 0x000FFFFF },
		},
		func = function(inputs)
			local use_new_flags = inputs.instr
			local instr_not_mul
			if params.core_type == "m" then
				instr_not_mul = util.op_is_not_k(inputs.instr, 14, 0xE)
				use_new_flags = use_new_flags:band(spaghetti.lshiftk(instr_not_mul:bor(0x4000), 15))
			end
			local flags_out = spaghetti.select(use_new_flags:band(0x8000):zeroable(), inputs.flags_new, inputs.flags_old):band(0x1000000F)
			if params.core_type == "m" then
				local shift_by = instr_not_mul:bxor(0x10001):assert(0x1E010000, 0x0000001)
				flags_out = flags_out:bor(spaghetti.lshiftk(inputs.res_mull:band(spaghetti.constant(0x3FFFFFFF):lshift(shift_by)):bor(0x01000000), 4))
			else
				-- subtle: s cores can potentially execute mull too, but its encoding already disables updating flags
				flags_out:force(0x10000000, 0x000FFFFF)
			end
			return {
				flags = flags_out,
			}
		end,
		fuzz_inputs = function()
			return {
				instr     = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
				flags_new = bitx.bor(0x10000000, math.random(0x0, 0xB), bitx.lshift(math.random(0x0000, 0xFFFF), 4)),
				flags_old = bitx.bor(0x10000000, math.random(0x0, 0xB), bitx.lshift(math.random(0x0000, 0xFFFF), 4)),
				res_mull  = params.core_type == "m" and bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)) or nil,
			}
		end,
		fuzz_outputs = function(inputs)
			local do_mul = bitx.band(inputs.instr, 0xE) == 14
			local keep_flags = bitx.band(inputs.instr, 0x8000) == 0 or (params.core_type == "m" and do_mul)
			local flags_new  = bitx.band(inputs.flags_new, 0xF)
			local flags_old  = bitx.band(inputs.flags_old, 0xF)
			local flags_out  = bitx.band(keep_flags and flags_old or flags_new, 0x000F)
			if params.core_type == "m" and do_mul then
				flags_out = bitx.bor(flags_out, bitx.lshift(bitx.band(inputs.res_mull, 0xFFFF), 4))
			end
			return {
				flags = bitx.bor(0x10000000, flags_out),
			}
		end,
	}
end)
