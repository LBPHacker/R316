local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module(function(params)
	local s_or_f = ("sf"):find(params.core_type, 1, true)

	return {
		tag = "core.instr_sel",
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
			{ name = "state"     , index = 1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "ram_instr" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "ram_imm"   , index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "curr_instr", index = 7, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x10000000 },
			{ name = "curr_imm"  , index = 9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "instr", index = 1, keepalive = 0x30000000, payload = 0x0001FFFF },
			{ name = "imm"  , index = 3, keepalive = 0x30000000, payload = 0x0000FFFF },
			{ name = "state", index = 5, keepalive = 0x10000000, payload = 0x0000000F },
		},
		func = function(inputs)
			local sel_instr, sel_imm = spaghetti.select(inputs.curr_instr:band(0x00010000):zeroable(), inputs.curr_instr, inputs.ram_instr, inputs.curr_imm, inputs.ram_imm)
			local stall
			if params.core_type == "s" then
				local instr_not_mul = util.op_is_not_k(sel_instr, 14, 0xE)
				local instr_not_mul_e = util.op_is_not_k(sel_instr, 14)
				local instr_not_mull = instr_not_mul_e:bor(spaghetti.rshiftk(sel_instr, 15)):bsub(0xFFFE):assert(0x1E000000, 0x00010001)
				local prev_differs =      inputs.curr_instr:bxor(sel_instr:bor(0x20000000)):bsub(0xBE01)
				                     :bor(inputs.curr_imm  :bxor(sel_imm  :bor(0x20000000))             )
				local not_mull_or_differs_or_memop = instr_not_mull:bor(prev_differs):assert(0x3E000000, 0x0001FFFF)
				local prev_dest = spaghetti.rshiftk(inputs.curr_instr, 9)
				local prev_src1 = spaghetti.rshiftk(inputs.curr_instr, 4)
				local prev_src2 =                   inputs.curr_imm
				local clobber_src1 = prev_dest:bxor(prev_src1):bor(0x20):assert(0x01080020, 0x00001FDF)
				local clobber_src2 = prev_dest:bxor(prev_src2):bor(0x20):assert(0x10080020, 0x0000FFDF)
				local no_imm = spaghetti.rshiftk(sel_instr:bsub(0x10000), 14):bsub(2):assert(0x00004000, 0x000000001)
				local clobber_src2_no_imm = clobber_src2:bor(no_imm):assert(0x10084020, 0x0000BFDF)
				local clobber =      spaghetti.constant(0x20):rshift(clobber_src1)       :never_zero()
				                :bor(spaghetti.constant(0x20):rshift(clobber_src2_no_imm):never_zero()):never_zero():bor(0x10000):band(0x10001)
				local cannot_fuse = not_mull_or_differs_or_memop:bor(clobber):assert(0x3E010000, 0x0000FFFF)
				local shift_by = instr_not_mul:bor(0x10000):bxor(1):assert(0x0E010000, 0x00000001)
				stall = cannot_fuse:band(spaghetti.constant(0x3FFFFFFF):lshift(shift_by)):band(0xFFFF)
			elseif params.core_type == "f" then
				local instr_not_mul = util.op_is_not_k(sel_instr, 14, 0xE)
				stall = instr_not_mul:bxor(1):band(1)
			end
			local state = inputs.state
			if stall then
				state = spaghetti.select(stall:zeroable(), state:bor(8), state)
			end
			local sel_instr_hlt = spaghetti.select(state:band(8):zeroable(), 0x10000000, sel_instr)
			return {
				instr = sel_instr_hlt:bor(0x20000000), -- TODO: change from 30000000 to 10000000 everywhere
				imm   = sel_imm:bor(0x20000000),
				state = state
			}
		end,
		fuzz_inputs = function()
			local curr_instr = math.random(0x00000000, 0x0001FFFF)
			local curr_imm   = math.random(0x00000000, 0x0000FFFF)
			local instr      = math.random(0x00000000, 0x0000FFFF)
			local imm        = math.random(0x00000000, 0x0000FFFF)
			if params.core_type == "s" and math.random(1, 10) == 1 then
				imm = curr_imm
				curr_instr = bitx.bor(bitx.band(curr_instr, 0xFFFFFFF1), 0x0000000E)
				instr = bitx.bor(bitx.band(curr_instr, 0xFFFE41FE), bitx.lshift(math.random(0x00, 0x1F), 4))
			end
			return {
				state      = bitx.bor(0x10000000, util.any_state()),
				curr_instr = bitx.bor(0x10000000, curr_instr),
				curr_imm   = bitx.bor(0x10000000, curr_imm),
				ram_instr  = bitx.bor(0x10000000, instr),
				ram_imm    = bitx.bor(0x10000000, imm),
			}
		end,
		fuzz_outputs = function(inputs)
			local use_curr = bitx.band(inputs.curr_instr, 0x10000) ~= 0
			local instr = use_curr and inputs.curr_instr or inputs.ram_instr
			local imm   = use_curr and inputs.curr_imm   or inputs.ram_imm
			local stall = false
			if bitx.band(instr, 0xE) == 14 then
				if params.core_type == "s" then
					local prev_is_mul = bitx.band(bitx.bxor(inputs.curr_instr, instr), 0x41FE) == 0 and
					                    bitx.band(bitx.bxor(inputs.curr_imm  , imm  ), 0xFFFF) == 0
					-- subtle: it's fine to check ram_instr rather than outputs.instr because
					-- these can only differ if the instruction comes from curr_instr, in which case
					-- the previous instruction was an st anyway and ram_instr is 0xFFFFFFFF
					local this_is_mull = bitx.band(instr, 0x800F) == 0x000E
					local can_do_mull = prev_is_mul and this_is_mull
					local prev_dest = bitx.band(bitx.rshift(inputs.curr_instr, 9), 0x1F)
					local prev_src1 = bitx.band(bitx.rshift(inputs.curr_instr, 4), 0x1F)
					local prev_src2 = bitx.band(            inputs.curr_imm      , 0x1F)
					if prev_dest == prev_src1 then
						can_do_mull = false
					end
					if bitx.band(inputs.curr_instr, 0x4000) == 0x0000 and prev_dest == prev_src2 then
						can_do_mull = false
					end
					stall = not can_do_mull
				elseif params.core_type == "f" then
					stall = true
				end
			end
			local state = stall and bitx.bor(inputs.state, 8) or inputs.state
			if bitx.band(state, 8) ~= 0 then
				instr = 0x10000000
			end
			return {
				instr = bitx.bor(0x20000000, instr),
				imm   = bitx.bor(0x20000000, imm),
				state = bitx.bor(0x10000000, state),
			}
		end,
	}
end)
