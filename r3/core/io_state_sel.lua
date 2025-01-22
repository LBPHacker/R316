local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module(function(params)
	return {
		tag = "core.io_state_sel",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 1,
		storage_slots = 40,
		work_slots    = 26,
		inputs = {
			{ name = "state"          , index =  1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000001 },
			{ name = "pc"             , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "flags"          , index =  5, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x1000000B },
			{ name = "curr_instr"     , index =  7, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x1000CAFE },
			{ name = "curr_imm"       , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000CAFE },
			{ name = "io_state"       , index = 11, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "next_state"     , index = 13, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "next_pc"        , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "next_flags"     , index = 17, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
			{ name = "next_curr_instr", index = 19, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x10000000 },
			{ name = "next_curr_imm"  , index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "next_ram_addr"  , index = 23, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
			{ name = "next_wreg_addr" , index = 25, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
			{ name = "next_ram_data"  , index = 27, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x10000000, never_zero = true },
			{ name = "ram_addr"       , index = 29, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
			{ name = "ram_data"       , index = 31, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x10000000, never_zero = true },
			not params.for_mcore and { name = "instr", index = 33, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 } or nil,
			not params.for_mcore and { name = "imm"  , index = 35, keepalive = 0x30000000, payload = 0x0000FFFF, initial = 0x30000000 } or nil,
		},
		outputs = {
			{ name = "state"     , index =  1, keepalive = 0x10000000, payload = 0x0000000F },
			{ name = "pc"        , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "flags"     , index =  5, keepalive = 0x10000000, payload = 0x000FFFFF },
			{ name = "curr_instr", index =  7, keepalive = 0x10000000, payload = 0x0001FFFF },
			{ name = "curr_imm"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "ram_addr"  , index = 11, keepalive = 0x10000000, payload = 0x000FFFFF },
			{ name = "wreg_addr" , index = 13, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "ram_data"  , index = 15, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		},
		func = function(inputs)
			local keep_old = inputs.io_state
			if not params.for_mcore then
				local instr_not_mul = util.op_is_not_k(inputs.instr, 14, 0xE)
				local instr_not_mul_e = util.op_is_not_k(inputs.instr, 14)
				local instr_not_mull = instr_not_mul_e:bor(spaghetti.rshiftk(inputs.instr:bsub(0x10000), 15)):bsub(0xFFFE):assert(0x3E000000, 0x00010001)
				local prev_differs =      inputs.curr_instr:bxor(inputs.instr):bsub(0x8000):bsub(1)
				                     :bor(inputs.curr_imm  :bxor(inputs.imm  )                     )
				local not_mull_or_differs = instr_not_mull:bor(prev_differs):assert(0x3E000000, 0x0001FFFF)
				local prev_dest = spaghetti.rshiftk(inputs.curr_instr, 9)
				local prev_src1 = spaghetti.rshiftk(inputs.curr_instr, 4)
				local prev_src2 =                   inputs.curr_imm
				local clobber_src1 = prev_dest:bxor(prev_src1):bor(0x20):assert(0x01080020, 0x00001FDF)
				local clobber_src2 = prev_dest:bxor(prev_src2):bor(0x20):assert(0x10080020, 0x0000FFDF)
				local no_imm = spaghetti.rshiftk(inputs.instr:bsub(0x10000), 14):bsub(2):assert(0x0000C000, 0x000000001)
				local clobber_src2_no_imm = clobber_src2:bor(no_imm):assert(0x1008C020, 0x00003FDF)
				local clobber =      spaghetti.constant(0x20):rshift(clobber_src1)       :never_zero()
				                :bor(spaghetti.constant(0x20):rshift(clobber_src2_no_imm):never_zero()):never_zero():bor(0x10000):band(0x10001)
				local cannot_fuse = not_mull_or_differs:bor(clobber):assert(0x3E010000, 0x0000FFFF)
				local shift_by = instr_not_mul:bor(0x10000):bxor(1):assert(0x1E010000, 0x00000001)
				keep_old = keep_old:bsub(0xFFFE):bor(cannot_fuse:band(spaghetti.constant(0x3FFFFFFF):lshift(shift_by))):band(0xFFFF)
			else
				keep_old = keep_old:band(1)
			end
			local state, curr_instr, curr_imm, pc, flags, ram_addr, ram_data, wreg_addr = spaghetti.select(
				keep_old:zeroable(),
				inputs.state     , inputs.next_state,
				inputs.curr_instr, inputs.next_curr_instr,
				inputs.curr_imm  , inputs.next_curr_imm,
				inputs.pc        , inputs.next_pc,
				inputs.flags     , inputs.next_flags,
				inputs.ram_addr  , inputs.next_ram_addr,
				inputs.ram_data  , inputs.next_ram_data,
				0x10000000       , inputs.next_wreg_addr
			)
			ram_data:never_zero()
			return {
				state      = state,
				curr_instr = curr_instr,
				curr_imm   = curr_imm,
				pc         = pc,
				flags      = flags,
				ram_addr   = ram_addr,
				ram_data   = ram_data,
				wreg_addr  = wreg_addr,
			}
		end,
		fuzz_inputs = function()
			local curr_instr = math.random(0x00000000, 0x0001FFFF)
			local curr_imm   = math.random(0x00000000, 0x0000FFFF)
			local instr      = math.random(0x00000000, 0x0001FFFF)
			local imm        = math.random(0x00000000, 0x0000FFFF)
			if not params.for_mcore and math.random(1, 10) == 1 then
				imm = curr_imm
				curr_instr = bitx.bor(bitx.band(curr_instr, 0xFFFFFFF1), 0x0000000E)
				instr = bitx.band(curr_instr, 0xFFFF7FFE)
			end
			return {
				state           = bitx.bor(0x10000000, util.any_state()),
				pc              = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
				flags           = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
				curr_instr      = bitx.bor(0x10000000, curr_instr),
				curr_imm        = bitx.bor(0x10000000, curr_imm),
				io_state        = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000F)),
				next_state      = bitx.bor(0x10000000, util.any_state()),
				next_pc         = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
				next_flags      = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
				next_curr_instr = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
				next_curr_imm   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
				next_ram_addr   = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
				next_wreg_addr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000001F)),
				ram_addr        = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
				instr           = not params.for_mcore and bitx.bor(0x30000000, instr),
				imm             = not params.for_mcore and bitx.bor(0x30000000, imm),
				ram_data        = testbed.any(),
				next_ram_data   = testbed.any(),
			}
		end,
		fuzz_outputs = function(inputs)
			local keep_old = bitx.band(inputs.io_state, 1) ~= 0
			if not params.for_mcore then
				if bitx.band(inputs.instr, 0xE) == 14 then
					local prev_is_mul = bitx.band(bitx.bxor(inputs.curr_instr, inputs.instr), 0x7FFE) == 0 and
					                    bitx.band(bitx.bxor(inputs.curr_imm  , inputs.imm  ), 0xFFFF) == 0
					local this_is_mull = bitx.band(inputs.instr, 0x800F) == 0x000E
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
					keep_old = keep_old or not can_do_mull
				end
			end
			return {
				state      = keep_old and inputs.state      or inputs.next_state,
				curr_instr = keep_old and inputs.curr_instr or inputs.next_curr_instr,
				curr_imm   = keep_old and inputs.curr_imm   or inputs.next_curr_imm,
				pc         = keep_old and inputs.pc         or inputs.next_pc,
				flags      = keep_old and inputs.flags      or inputs.next_flags,
				ram_data   = keep_old and inputs.ram_data   or inputs.next_ram_data,
				ram_addr   = keep_old and inputs.ram_addr   or inputs.next_ram_addr,
				wreg_addr  = keep_old and 0x10000000        or inputs.next_wreg_addr,
			}
		end,
	}
end)
