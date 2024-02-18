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
		{ name = "pri_in", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000DEAD },
		{ name = "sec_in", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000BEEF },
	},
	outputs = {
		{ name = "l_shl", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "l_shr", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local left  = inputs.pri_in
		local right = inputs.pri_in
		local amount = inputs.sec_in
		local function apply_shifts(i)
			local i22 = bitx.lshift(1, bitx.lshift(1, i))
			local shift = spaghetti.rshiftk(amount, i):bxor(0x00010001):band(0x00010001):bor(i22)
			shift:assert(bitx.bor(0x10000, i22), 1) -- lsb is one of: 1 << (1 << i), 0
			right = right:rshift(shift):never_zero()
			left  = left :lshift(shift):never_zero()
		end
		left = left:bor(0x00010000)
		apply_shifts(3)
		left = left:bor(0x00010000)
		right = right:bor(0x10000000):band(0x1000FFFF)
		apply_shifts(0)
		apply_shifts(1)
		apply_shifts(2)
		right = right:bor(0x10000000):band(0x1000FFFF)
		left  = left :bor(0x10000000):band(0x1000FFFF)
		return {
			l_shl = left,
			l_shr = right,
		}
	end,
	fuzz = function()
		local pri = math.random(0x0000, 0xFFFF)
		local sec = math.random(0x0000, 0xFFFF)
		local amount = bitx.band(sec, 0x000F)
		return {
			inputs = {
				pri_in = bitx.bor(0x10000000, pri),
				sec_in = bitx.bor(0x10000000, sec),
			},
			outputs = {
				l_shl = bitx.bor(0x10000000, bitx.band(bitx.lshift(pri, amount), 0x0000FFFF)),
				l_shr = bitx.bor(0x10000000, bitx.band(bitx.rshift(pri, amount), 0x0000FFFF)),
			},
		}
	end,
})
