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
	storage_slots = 60,
	work_slots    = 20,
	inputs = {
		{ name = "l_xor"  , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD1 },
		{ name = "l_clr"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD2 },
		{ name = "l_and"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD3 },
		{ name = "l_or"   , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD4 },
		{ name = "l_shl"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD5 },
		{ name = "l_shr"  , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD6 },
		{ name = "l_ld"   , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD7 },
		{ name = "l_exh"  , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD8 },
		{ name = "l_mov"  , index = 17, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BAD9 },
		{ name = "l_jmp"  , index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BADA },
		{ name = "l_st"   , index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BADB },
		{ name = "l_hlt"  , index = 23, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BADC },
		{ name = "l_add"  , index = 25, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BADD },
		{ name = "op_bits", index = 27, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
	},
	outputs = {
		{ name = "muxed"    , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "sign_zero", index = 3, keepalive = 0x10000000, payload = 0x000C0000 },
	},
	func = function(inputs)
		local function select_op_bit(v0, v1, i)
			local shifted = inputs.op_bits
			if i ~= 0 then
				shifted = spaghetti.rshiftk(shifted, i)
			end
			local select_mask = spaghetti.lshift(0x3FFFFFFF, shifted:bor(0x00010000):band(0x00010001))
			return spaghetti.bxor(0x20000000, v0):bxor(v1):band(select_mask):bxor(v0)
		end
		local sel_01 = select_op_bit(inputs.l_mov, inputs.l_jmp, 0):assert(0x30000000, 0x0000FFFF)
		local sel_23 = select_op_bit(inputs.l_ld , inputs.l_exh, 0):assert(0x30000000, 0x0000FFFF)
		local sel_89 = select_op_bit(inputs.l_shl, inputs.l_shr, 0):assert(0x30000000, 0x0000FFFF)
		local sel_AB = select_op_bit(inputs.l_st , inputs.l_hlt, 0):assert(0x30000000, 0x0000FFFF)
		local sel_CD = select_op_bit(inputs.l_and, inputs.l_or , 0):assert(0x30000000, 0x0000FFFF)
		local sel_EF = select_op_bit(inputs.l_xor, inputs.l_clr, 0):assert(0x30000000, 0x0000FFFF)
		local sel_03 = select_op_bit(sel_01, sel_23, 1):assert(0x10000000, 0x0000FFFF)
		local sel_47 = inputs.l_add
		local sel_8B = select_op_bit(sel_89, sel_AB, 1):assert(0x10000000, 0x0000FFFF)
		local sel_CF = select_op_bit(sel_CD, sel_EF, 1):assert(0x10000000, 0x0000FFFF)
		local sel_07 = select_op_bit(sel_03, sel_47, 2):assert(0x30000000, 0x0000FFFF)
		local sel_8F = select_op_bit(sel_8B, sel_CF, 2):assert(0x30000000, 0x0000FFFF)
		local muxed = select_op_bit(sel_07, sel_8F, 3):assert(0x10000000, 0x0000FFFF)
		local zero_inv = spaghetti.lshift(0x3FFFFFFF, muxed) -- zero_inv bit 15 is clear iff muxed is zero
		local zero = spaghetti.rshiftk(zero_inv, 15):bxor(1):band(0x00002001):assert(0x00002000, 0x00000001)
		local sign = spaghetti.rshiftk(muxed, 14):bsub(1):assert(0x00004000, 0x00000002)
		local sign_zero = spaghetti.lshiftk(zero:bor(sign):bor(0x0400):band(0x0403), 18)
		return {
			muxed     = muxed,
			sign_zero = sign_zero,
		}
	end,
	fuzz_inputs = function()
		local l_xor   = math.random(0x0000, 0xFFFF)
		local l_clr   = math.random(0x0000, 0xFFFF)
		local l_and   = math.random(0x0000, 0xFFFF)
		local l_or    = math.random(0x0000, 0xFFFF)
		local l_shl   = math.random(0x0000, 0xFFFF)
		local l_shr   = math.random(0x0000, 0xFFFF)
		local l_ld    = math.random(0x0000, 0xFFFF)
		local l_exh   = math.random(0x0000, 0xFFFF)
		local l_mov   = math.random(0x0000, 0xFFFF)
		local l_jmp   = math.random(0x0000, 0xFFFF)
		local l_st    = math.random(0x0000, 0xFFFF)
		local l_hlt   = math.random(0x0000, 0xFFFF)
		local l_add   = math.random(0x0000, 0xFFFF)
		local op_bits = math.random(0x0, 0xF)
		return {
			l_xor   = bitx.bor(0x10000000, l_xor),
			l_clr   = bitx.bor(0x10000000, l_clr),
			l_and   = bitx.bor(0x10000000, l_and),
			l_or    = bitx.bor(0x10000000, l_or ),
			l_shl   = bitx.bor(0x10000000, l_shl),
			l_shr   = bitx.bor(0x10000000, l_shr),
			l_ld    = bitx.bor(0x10000000, l_ld ),
			l_exh   = bitx.bor(0x10000000, l_exh),
			l_mov   = bitx.bor(0x10000000, l_mov),
			l_jmp   = bitx.bor(0x10000000, l_jmp),
			l_st    = bitx.bor(0x10000000, l_st ),
			l_hlt   = bitx.bor(0x10000000, l_hlt),
			l_add   = bitx.bor(0x10000000, l_add),
			op_bits = bitx.bor(0x10000000, op_bits),
		}
	end,
	fuzz_outputs = function(inputs)
		local select_from = {
			[  0 ] = inputs.l_mov, [  1 ] = inputs.l_jmp, [  2 ] = inputs.l_ld , [  3 ] = inputs.l_exh,
			[  4 ] = inputs.l_add, [  5 ] = inputs.l_add, [  6 ] = inputs.l_add, [  7 ] = inputs.l_add,
			[  8 ] = inputs.l_shl, [  9 ] = inputs.l_shr, [ 10 ] = inputs.l_st , [ 11 ] = inputs.l_hlt,
			[ 12 ] = inputs.l_and, [ 13 ] = inputs.l_or , [ 14 ] = inputs.l_xor, [ 15 ] = inputs.l_clr,
		}
		local op_bits = bitx.band(inputs.op_bits, 0xF)
		local muxed = bitx.band(select_from[op_bits], 0xFFFF)
		local sign_zero = bitx.bor(
			muxed == 0                    and 0x00040000 or 0x00000000,
			bitx.band(muxed, 0x8000) ~= 0 and 0x00080000 or 0x00000000
		)
		return {
			muxed     = bitx.bor(0x10000000, muxed),
			sign_zero = bitx.bor(0x10000000, sign_zero),
		}
	end,
})
