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
		{ name = "corestate", index = 1, keepalive = 0x10000000, payload = 0x0070FFFF, initial = 0x10000000 },
		{ name = "sec_in"   , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000DEAD },
		{ name = "op_bits"  , index = 5, keepalive = 0x10000000, payload = 0x000F0000, initial = 0x10000000 },
		{ name = "condition", index = 7, keepalive = 0x00010000, payload = 0x00000001, initial = 0x00010000 },
	},
	outputs = {
		{ name = "corestate", index = 1, keepalive = 0x10000000, payload = 0x0070FFFF },
		{ name = "l_jmp"    , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local function op_is_k_mask_inv(k)
			local op_bits_16 = spaghetti.rshiftk(inputs.op_bits, 16):assert(0x00001000, 0x0000000F)
			local op_test = op_bits_16:bxor(k):assert(0x00001000, 0x0000000F) -- lsb is one of: 12, 3, 2, 1, 0
			local mask_8 = spaghetti.constant(0x3FFFFFFF):lshift(op_test):lshift(op_test) -- shifted up 24, 6, 4, 2, or 0 bits
			local mask = mask_8:rshift(0x100):bor(0x3FFF0000)
			return mask
		end
		local function op_is_k_mask(k)
			return op_is_k_mask_inv(k):bxor(0x0000FFFF)
		end
		local ip = inputs.corestate:band(0x1000FFFF)
		local ip_inv = ip:bxor(0x0000FFFF):assert(0x10000000, 0x0000FFFF)
		local ip_inv_findsub = ip_inv:bor(0x00010000):assert(0x10010000, 0x0000FFFF)
		local ip_inv_sub = spaghetti.lshift(0x3FFFFFFE, ip_inv_findsub):assert(0x3FFE0000, 0x0001FFFE)
		local ip_inc_wild = ip_inv:bxor(ip_inv_sub):assert(0x2FFE0000, 0x0001FFFF)
		local ip_inc = ip_inc_wild:bor(0x10000000):band(0x1000FFFF)
		local condition_mask = spaghetti.lshift(0x3FFFFFFF, inputs.condition)
		local jmp_mask = op_is_k_mask(1) -- either 0x3FFF0000 or 0x3FFFFFFF
		local next_ip = spaghetti.bxor(0x20000000, ip_inc):bxor(inputs.sec_in):band(condition_mask):band(jmp_mask):bxor(ip_inc)
		local ld_mask_inv = op_is_k_mask_inv(2) -- either 0x3FFF0000 or 0x3FFFFFFF
		local st_mask_inv = op_is_k_mask_inv(10) -- either 0x3FFF0000 or 0x3FFFFFFF
		local hlt_mask_inv = op_is_k_mask_inv(11) -- either 0x3FFF0000 or 0x3FFFFFFF
		local corestate = spaghetti.constant(0x20000000)
			:bor(spaghetti.lshift(0x10,  ld_mask_inv):never_zero())
			:bor(spaghetti.lshift(0x20,  st_mask_inv):never_zero())
			:bor(spaghetti.lshift(0x40, hlt_mask_inv):never_zero())
			:band(0x3FFF0000):force(0x20000000, 0x00700000)
			:bxor(next_ip)
		return {
			corestate = corestate,
			l_jmp     = ip_inc,
		}
	end,
	fuzz = function()
		local old_state_ld  = math.random(0x0, 0x1)
		local old_state_st  = math.random(0x0, 0x1)
		local old_state_hlt = math.random(0x0, 0x1)
		local ip = math.random(0x0000, 0xFFFF)
		local sec = math.random(0x0000, 0xFFFF)
		local op_bits = math.random(0x0, 0xF)
		local condition = math.random(0x0, 0x1)
		local ip_inc = (ip + 1) % 0x10000
		local next_ip = (op_bits == 1 and condition == 1) and sec or ip_inc
		local new_state_ld  = op_bits ==  2 and 0x100000 or 0x000000
		local new_state_st  = op_bits == 10 and 0x200000 or 0x000000
		local new_state_hlt = op_bits == 11 and 0x400000 or 0x000000
		return {
			inputs = {
				corestate = bitx.bor(0x10000000, bitx.bor(
					bitx.bor(
						bitx.bor(
							ip,
							bitx.lshift(old_state_ld, 20)
						),
						bitx.lshift(old_state_st, 21)
					),
					bitx.lshift(old_state_hlt, 22)
				)),
				sec_in    = bitx.bor(0x10000000, sec),
				op_bits   = bitx.bor(0x10000000, bitx.lshift(op_bits, 16)),
				condition = bitx.bor(0x00010000, condition),
			},
			outputs = {
				corestate = bitx.bor(0x10000000, bitx.bor(
					new_state_st,
					bitx.bor(
						new_state_ld,
						bitx.bor(
							new_state_hlt,
							next_ip
						)
					)
				)),
				l_jmp     = bitx.bor(0x10000000, ip_inc),
			},
		}
	end,
})
