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
		{ name = "shifted_left" , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "shifted_right", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local left  = inputs.pri_in
		local right = inputs.pri_in
		for i = 0, 3 do
			local right_flip = spaghetti.rshiftk(right, bitx.lshift(1, i)):bxor(right):bor(0x30000000):band(0x3000FFFF)
			local left_flip  = spaghetti.lshiftk(left:bor(0x3FFF0000), bitx.lshift(1, i)):bxor(left):bor(0x30000000):band(0x3000FFFF)
			local flip_mask = spaghetti.lshift(0x3FFFFFFF, spaghetti.rshiftk(inputs.sec_in, i):bor(0x00010000):band(0x00010001))
			right = right_flip:band(flip_mask):bxor(right)
			left  =  left_flip:band(flip_mask):bxor(left)
		end
		return {
			shifted_left  = left,
			shifted_right = right,
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
				shifted_left  = bitx.bor(0x10000000, bitx.band(bitx.lshift(pri, amount), 0x0000FFFF)),
				shifted_right = bitx.bor(0x10000000, bitx.band(bitx.rshift(pri, amount), 0x0000FFFF)),
			},
		}
	end,
})
