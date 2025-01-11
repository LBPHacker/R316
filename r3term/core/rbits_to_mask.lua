local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local constants = require("r3term.core.constants")

assert(constants.max_size == 29)
local mask_mask = bitx.lshift(1, constants.max_size) - 1
return testbed.module({
	tag = "core.rbits_to_mask",
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
		{ name = "bit_low" , index = 1, keepalive = 0x00000000, payload = mask_mask, never_zero = true, initial = 0x00000001 },
		{ name = "bit_high", index = 3, keepalive = 0x00000000, payload = mask_mask, never_zero = true, initial = 0x00000001 },
	},
	outputs = {
		{ name = "mask", index = 1, keepalive = 0x20000000, payload = mask_mask },
	},
	func = function(inputs)
		local maskl = spaghetti.constant(0x3FFFFFFE):lshift(inputs.bit_low):assert(0x20000000, 0x1FFFFFFE)
		                             :bxor(0x1FFFFFFF):bxor(inputs.bit_low):assert(0x20000000, mask_mask)
		local maskh = spaghetti.constant(0x3FFFFFFE):lshift(inputs.bit_high):assert(0x20000000, 0x1FFFFFFE)
		                             :bxor(0x1FFFFFFF):bxor(inputs.bit_high):assert(0x20000000, mask_mask)
		local maskhl = maskh:bsub(0x10000000)
		local maskll = maskl:bor(0x10000000)
		local maskxl = maskhl:bxor(maskll):band(0x1000FFFF):bor(0x20000000):bsub(0x10000000):assert(0x20000000, 0x0000FFFF)
		local maskhh = spaghetti.rshiftk(maskh, 16)
		local masklh = spaghetti.rshiftk(maskl, 16):bor(0x20000000)
		local maskxh = spaghetti.lshiftk(maskhh:bxor(masklh):bor(0x00002000):assert(0x20002000, 0x00001FFF), 16):assert(0x20000000, 0x1FFF0000)
		local maskx = maskxh:bor(maskxl):assert(0x20000000, mask_mask)
		local mask = inputs.bit_low:bor(inputs.bit_high):never_zero():bor(maskx)
		return {
			mask = mask,
		}
	end,
	fuzz_inputs = function()
		return {
			bit_low  = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			bit_high = bitx.lshift(1, math.random(0, constants.max_size - 1)),
		}
	end,
	fuzz_outputs = function(inputs)
		local maskl = bitx.band(inputs.bit_low , mask_mask) - 1
		local maskh = bitx.band(inputs.bit_high, mask_mask) - 1
		local mask = bitx.bor(bitx.bor(bitx.bxor(maskl, maskh), inputs.bit_low), inputs.bit_high)
		return {
			mask = bitx.bor(0x20000000, mask),
		}
	end,
})
