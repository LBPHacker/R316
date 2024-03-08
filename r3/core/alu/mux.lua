local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local util      = require("r3.core.util")

return testbed.module({
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
	inputs = {
		{ name = "res_xor" , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_clr" , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
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
	},
	outputs = {
		{ name = "muxed"     , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "muxed_high", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "sign_zero" , index = 5, keepalive = 0x00050000, payload = 0x0000000C },
	},
	func = function(inputs)
		local sel_01, sel_23, sel_89, sel_AB, sel_CD, sel_EF = spaghetti.select(
			spaghetti.rshiftk(inputs.instr, 0):band(1):zeroable(),
			inputs.res_jmp, inputs.res_mov,
			inputs.res_exh, inputs.res_ld ,
			inputs.res_shr, inputs.res_shl,
			inputs.res_hlt, inputs.res_st ,
			inputs.res_or , inputs.res_and,
			inputs.res_clr, inputs.res_xor
		)
		local sel_03, sel_8B, sel_CF = spaghetti.select(
			spaghetti.rshiftk(inputs.instr, 1):band(1):zeroable(),
			sel_23, sel_01,
			sel_AB, sel_89,
			sel_EF, sel_CD
		)
		local sel_47 = inputs.res_add
		local sel_07, sel_8F = spaghetti.select(
			spaghetti.rshiftk(inputs.instr, 2):band(1):zeroable(),
			sel_47, sel_03,
			sel_CF, sel_8B
		)
		local muxed = spaghetti.select(
			spaghetti.rshiftk(inputs.instr, 3):band(1):zeroable(),
			sel_8F, sel_07
		)
		local zero      = spaghetti.rshift(0x10000000, muxed):never_zero()
		                     :bor(0x00010000):band(0x00010001):assert(0x00010000, 0x00000001)
		local sign      = spaghetti.rshiftk(muxed, 12):bsub(7):assert(0x00010000, 0x00000008)
		local sign_zero = spaghetti.lshiftk(zero, 2):bor(sign):assert(0x00050000, 0x0000000C)
		local instr_not_exh  = util.op_is_not_k(inputs.instr,  3)
		local instr_not_hlt  = util.op_is_not_k(inputs.instr, 11)
		local muxed_high_hlt = spaghetti.select(instr_not_hlt:band(1):zeroable(), inputs.pri_high, inputs.ram_high)
		local muxed_high     = spaghetti.select(instr_not_exh:band(1):zeroable(), muxed_high_hlt, inputs.sec)
		return {
			muxed      = muxed,
			muxed_high = muxed_high,
			sign_zero  = sign_zero,
		}
	end,
	fuzz_inputs = function()
		return {
			res_xor  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_clr  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
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
		}
	end,
	fuzz_outputs = function(inputs)
		local select_from = {
			[  0 ] = inputs.res_mov, [  1 ] = inputs.res_jmp, [  2 ] = inputs.res_ld , [  3 ] = inputs.res_exh,
			[  4 ] = inputs.res_add, [  5 ] = inputs.res_add, [  6 ] = inputs.res_add, [  7 ] = inputs.res_add,
			[  8 ] = inputs.res_shl, [  9 ] = inputs.res_shr, [ 10 ] = inputs.res_st , [ 11 ] = inputs.res_hlt,
			[ 12 ] = inputs.res_and, [ 13 ] = inputs.res_or , [ 14 ] = inputs.res_xor, [ 15 ] = inputs.res_clr,
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
		elseif op == 11 then
			muxed_high = bitx.band(inputs.ram_high, 0xFFFF)
		end
		return {
			muxed      = bitx.bor(0x10000000, muxed),
			muxed_high = bitx.bor(0x10000000, muxed_high),
			sign_zero  = bitx.bor(0x00050000, sign_zero),
		}
	end,
})
