local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module(function(params)
	local inputs = {
		{ name = "res_xor" , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_and" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_or"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_shl" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_shr" , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_ld"  , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_exh" , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_mov" , index = 17, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_jmp" , index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_st"  , index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_hlt" , index = 23, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_add" , index = 25, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pri_high", index = 27, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"     , index = 29, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_high", index = 31, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr"   , index = 33, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "imm"     , index = 35, keepalive = 0x30000000, payload = 0x0000FFFF, initial = 0x30000000 },
	}
	if params.for_mcore then
		table.insert(inputs, { name = "res_mull", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "res_mulh", index = 37, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
	else
		table.insert(inputs, { name = "flags"   , index =  3, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x1000000B })
	end
	return {
		tag = "core.alu.mux",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 1,
		storage_slots = 40,
		work_slots    = 20,
		inputs = inputs,
		outputs = {
			{ name = "muxed"     , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "muxed_high", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sign_zero" , index = 5, keepalive = 0x00050000, payload = 0x0000000C },
			params.for_mcore and { name = "res_mull", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF } or nil,
		},
		func = function(inputs)
			local res_shx = spaghetti.select(inputs.imm:band(0x8000):zeroable(), inputs.res_shr, inputs.res_shl)
			local sel_01, sel_23, sel_89, sel_AB, sel_CD, sel_EF, sel_03, sel_8B, sel_CF
			if params.for_mcore then
				local res_mull = spaghetti.select(inputs.instr:band(0x8000):zeroable(), inputs.res_mulh, inputs.res_mull)
				local sel_01, sel_23, sel_89, sel_AB, sel_CD, sel_EF = spaghetti.select(
					inputs.instr:band(1):zeroable(),
					inputs.res_jmp , inputs.res_mov,
					inputs.res_exh , inputs.res_ld ,
					inputs.res_or  , inputs.res_xor,
					       res_shx , inputs.res_st ,
					inputs.res_hlt , inputs.res_and,
					inputs.res_mulh,       res_mull
				)
				sel_03, sel_8B, sel_CF = spaghetti.select(
					inputs.instr:band(2):zeroable(),
					sel_23, sel_01,
					sel_AB, sel_89,
					sel_EF, sel_CD
				)
			else
				local sel_01, sel_23, sel_89, sel_AB, sel_CD = spaghetti.select(
					inputs.instr:band(1):zeroable(),
					inputs.res_jmp , inputs.res_mov,
					inputs.res_exh , inputs.res_ld ,
					inputs.res_or  , inputs.res_xor,
					       res_shx , inputs.res_st ,
					inputs.res_hlt , inputs.res_and
				)
				local sel_EF = spaghetti.rshiftk(inputs.flags, 4):bor(0x10000000):band(0x1000FFFF)
				sel_03, sel_8B, sel_CF = spaghetti.select(
					inputs.instr:band(2):zeroable(),
					sel_23, sel_01,
					sel_AB, sel_89,
					sel_EF, sel_CD
				)
			end
			local sel_47 = inputs.res_add
			local sel_07, sel_8F = spaghetti.select(
				inputs.instr:band(4):zeroable(),
				sel_47, sel_03,
				sel_CF, sel_8B
			)
			local muxed = spaghetti.select(
				inputs.instr:band(8):zeroable(),
				sel_8F, sel_07
			)
			local zero      = spaghetti.rshift(0x10000000, muxed):never_zero()
			                     :bor(0x00010000):band(0x00010001):assert(0x00010000, 0x00000001)
			local sign      = spaghetti.rshiftk(muxed, 12):bsub(7):assert(0x00010000, 0x00000008)
			local sign_zero = spaghetti.lshiftk(zero, 2):bor(sign):assert(0x00050000, 0x0000000C)
			local instr_not_exh  = util.op_is_not_k(inputs.instr, 3)
			local instr_not_hlt  = util.op_is_not_k(inputs.instr, 13)
			local muxed_high_hlt = spaghetti.select(instr_not_hlt:band(1):zeroable(), inputs.pri_high, inputs.ram_high)
			local muxed_high     = spaghetti.select(instr_not_exh:band(1):zeroable(), muxed_high_hlt, inputs.sec)
			return {
				muxed      = muxed,
				muxed_high = muxed_high,
				sign_zero  = sign_zero,
				res_mull   = inputs.res_mull,
			}
		end,
		fuzz_inputs = function()
			return {
				res_xor  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_and  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_or   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_shl  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_shr  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_ld   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_exh  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_mov  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_jmp  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_st   = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_hlt  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				res_add  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				pri_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				sec      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				ram_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
				imm      = bitx.bor(0x30000000, math.random(0x00000000, 0x0000FFFF)),
				res_mull = params.for_mcore and bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)) or nil,
				res_mulh = params.for_mcore and bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)) or nil,
				flags    = not params.for_mcore and bitx.bor(0x10000000, math.random(0x0, 0xB), bitx.lshift(math.random(0x0000, 0xFFFF), 4)) or nil,
			}
		end,
		fuzz_outputs = function(inputs)
			local res_shx = bitx.band(inputs.imm, 0x8000) ~= 0 and inputs.res_shr or inputs.res_shl
			local flags_mull = not params.for_mcore and bitx.band(bitx.rshift(inputs.flags, 4), 0xFFFF)
			local res_mull = params.for_mcore and (bitx.band(inputs.instr, 0x8000) ~= 0 and inputs.res_mulh or inputs.res_mull) or flags_mull
			local res_mulh = params.for_mcore and                                           inputs.res_mulh                     or flags_mull
			local select_from = {
				[  0 ] = inputs.res_mov, [  1 ] = inputs.res_jmp, [  2 ] = inputs.res_ld , [  3 ] = inputs.res_exh,
				[  4 ] = inputs.res_add, [  5 ] = inputs.res_add, [  6 ] = inputs.res_add, [  7 ] = inputs.res_add,
				[  8 ] = inputs.res_xor, [  9 ] = inputs.res_or , [ 10 ] = inputs.res_st , [ 11 ] =        res_shx,
				[ 12 ] = inputs.res_and, [ 13 ] = inputs.res_hlt, [ 14 ] =       res_mull, [ 15 ] =       res_mulh,
			}
			local op = bitx.band(inputs.instr, 0xF)
			local muxed = bitx.band(select_from[op], 0xFFFF)
			local sign_zero = bitx.bor(
				muxed == 0                    and 0x0004 or 0x0000,
				bitx.band(muxed, 0x8000) ~= 0 and 0x0008 or 0x0000
			)
			local muxed_high = bitx.band(inputs.pri_high, 0xFFFF)
			if op == 3 then
				muxed_high = bitx.band(inputs.sec, 0xFFFF)
			elseif op == 13 then
				muxed_high = bitx.band(inputs.ram_high, 0xFFFF)
			end
			return {
				muxed      = bitx.bor(0x10000000, muxed),
				muxed_high = bitx.bor(0x10000000, muxed_high),
				sign_zero  = bitx.bor(0x00050000, sign_zero),
				res_mull   = params.for_mcore and inputs.res_mull or nil,
			}
		end,
	}
end)
