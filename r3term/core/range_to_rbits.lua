local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local constants = require("r3term.core.constants")

assert(constants.max_size == 29)
local mask_mask = bitx.lshift(1, constants.max_size) - 1
return testbed.module({
	tag = "core.range_to_rbits",
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
		{ name = "range", index = 1, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "bit_low" , index = 1, keepalive = 0x00000000, payload = mask_mask, never_zero = true },
		{ name = "bit_high", index = 3, keepalive = 0x00000000, payload = mask_mask, never_zero = true },
	},
	func = function(inputs)
		local range_above28 = inputs.range:band(spaghetti.rshiftk(inputs.range, 1):bor(0x10000000))
		                                  :band(spaghetti.rshiftk(inputs.range, 2):bor(0x10000000)):assert(0x10000000, 0x000000FF)
		local range_above28_bits = range_above28:bsub(0x40):bsub(0x20):bsub(0x10):bsub(0x08):bsub(0x03):assert(0x10000000, 0x00000084)
		local range_clear = spaghetti.rshiftk(range_above28_bits, 1):bor(spaghetti.rshiftk(range_above28_bits, 2)):assert(0x0C000000, 0x00000063)
		local range_max28_inv = inputs.range:bsub(range_clear):bxor(0x000003FF):assert(0x10000000, 0x000003FF)
		local shift_total = {
			[ 0 ] = spaghetti.constant(1),
			[ 1 ] = spaghetti.constant(1),
		}
		for i = 0, 4 do
			local i22 = bitx.lshift(1, bitx.lshift(1, i))
			for j = 0, 1 do
				local shift = spaghetti.rshiftk(range_max28_inv, i + j * 5):bsub(0xFFFE):bor(i22)
				shift_total[j] = shift_total[j]:lshift(shift):never_zero()
			end
		end
		return {
			bit_low  = shift_total[0]:force(0x00000000, mask_mask),
			bit_high = shift_total[1]:force(0x00000000, mask_mask),
		}
	end,
	fuzz_inputs = function()
		return {
			range = bitx.bor(0x10000000, math.random(0x0000, 0x03FF))
		}
	end,
	fuzz_outputs = function(inputs)
		return {
			bit_low  = bitx.lshift(1, math.min(bitx.band(            inputs.range    , 0x1F), constants.max_size - 1)),
			bit_high = bitx.lshift(1, math.min(bitx.band(bitx.rshift(inputs.range, 5), 0x1F), constants.max_size - 1)),
		}
	end,
})
