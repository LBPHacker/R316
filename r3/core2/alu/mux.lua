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
	work_slots    = 12,
	inputs = {
		{ name = "res_xor", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_clr", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_and", index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_or" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_shl", index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_shr", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_ld" , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_exh", index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_mov", index = 17, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_jmp", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_st" , index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_hlt", index = 23, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "res_add", index = 25, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr"  , index = 27, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "muxed"    , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "sign_zero", index = 3, keepalive = 0x00050000, payload = 0x0000000C },
	},
	func = function(inputs)
		local function select_op_bit(v0, v1, i)
			local shifted = inputs.instr
			if i ~= 0 then
				shifted = spaghetti.rshiftk(shifted, i)
			end
			local select_mask = spaghetti.lshift(0x3FFFFFFF, shifted:bor(0x00010000):band(0x00010001))
			return spaghetti.bxor(0x20000000, v0):bxor(v1):band(select_mask):bxor(v0)
		end
		local sel_01 = select_op_bit(inputs.res_mov, inputs.res_jmp, 0):assert(0x30000000, 0x0000FFFF)
		local sel_23 = select_op_bit(inputs.res_ld , inputs.res_exh, 0):assert(0x30000000, 0x0000FFFF)
		local sel_89 = select_op_bit(inputs.res_shl, inputs.res_shr, 0):assert(0x30000000, 0x0000FFFF)
		local sel_AB = select_op_bit(inputs.res_st , inputs.res_hlt, 0):assert(0x30000000, 0x0000FFFF)
		local sel_CD = select_op_bit(inputs.res_and, inputs.res_or , 0):assert(0x30000000, 0x0000FFFF)
		local sel_EF = select_op_bit(inputs.res_xor, inputs.res_clr, 0):assert(0x30000000, 0x0000FFFF)
		local sel_03 = select_op_bit(sel_01, sel_23, 1):assert(0x10000000, 0x0000FFFF)
		local sel_47 = inputs.res_add
		local sel_8B = select_op_bit(sel_89, sel_AB, 1):assert(0x10000000, 0x0000FFFF)
		local sel_CF = select_op_bit(sel_CD, sel_EF, 1):assert(0x10000000, 0x0000FFFF)
		local sel_07 = select_op_bit(sel_03, sel_47, 2):assert(0x30000000, 0x0000FFFF)
		local sel_8F = select_op_bit(sel_8B, sel_CF, 2):assert(0x30000000, 0x0000FFFF)
		local muxed  = select_op_bit(sel_07, sel_8F, 3):assert(0x10000000, 0x0000FFFF)
		local zero      = spaghetti.rshift(0x10000000, muxed):never_zero()
		                     :bor(0x00010000):band(0x00010001):assert(0x00010000, 0x00000001)
		local sign      = spaghetti.rshiftk(muxed, 12):bsub(7):assert(0x00010000, 0x00000008)
		local sign_zero = spaghetti.lshiftk(zero, 2):bor(sign):assert(0x00050000, 0x0000000C)
		return {
			muxed     = muxed,
			sign_zero = sign_zero,
		}
	end,
	fuzz_inputs = function()
		return {
			res_xor = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_clr = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_and = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_or  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_shl = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_shr = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_ld  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_exh = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_mov = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_jmp = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_st  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_hlt = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			res_add = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			instr   = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
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
		return {
			muxed     = bitx.bor(0x10000000, muxed),
			sign_zero = bitx.bor(0x00050000, sign_zero),
		}
	end,
})
