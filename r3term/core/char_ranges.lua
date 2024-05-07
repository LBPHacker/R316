local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti     = require("spaghetti")
local bitx          = require("spaghetti.bitx")
local testbed       = require("spaghetti.testbed")
local index_to_bits = require("r3term.core.index_to_bits")

return testbed.module({
	tag = "core.char_ranges",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 50,
	work_slots    = 24,
	inputs = {
		{ name = "dirbits", index = 1, keepalive = 0x10000000, payload = 0x2FFFFFFF, initial = 0x10000000 },
		{ name = "hsizes" , index = 3, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "vsizes" , index = 5, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "hrange" , index = 7, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "vrange" , index = 9, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "prange"         , index =  1, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "prange_bit_low" , index =  3, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true },
		{ name = "prange_bit_high", index =  5, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true },
		{ name = "srange"         , index =  7, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "srange_bit_low" , index =  9, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true },
		{ name = "srange_bit_high", index = 11, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true },
		{ name = "ssizes"         , index = 13, keepalive = 0x10000000, payload = 0x000003FF                    },
	},
	func = function(inputs)
		local ssizes, srange, prange = spaghetti.select(
			inputs.dirbits:band(1):zeroable(),
			inputs.vsizes, inputs.hsizes,
			inputs.vrange, inputs.hrange,
			inputs.hrange, inputs.vrange
		)
		local prange_bits = index_to_bits.instantiate({
			range = prange,
		})
		local srange_bits = index_to_bits.instantiate({
			range = srange,
		})
		return {
			prange          = prange,
			prange_bit_low  = prange_bits.bit_low,
			prange_bit_high = prange_bits.bit_high,
			srange          = srange,
			srange_bit_low  = srange_bits.bit_low,
			srange_bit_high = srange_bits.bit_high,
			ssizes          = ssizes,
		}
	end,
	fuzz_inputs = function()
		return {
			dirbits = bitx.bor(0x10000000, math.random(0x00000000, 0x3FFFFFFF)),
			hsizes  = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			vsizes  = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			hrange  = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			vrange  = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local horiz_scroll = bitx.band(inputs.dirbits, 1) ~= 0
		local prange = horiz_scroll and inputs.hrange or inputs.vrange
		local srange = horiz_scroll and inputs.vrange or inputs.hrange
		local ssizes = horiz_scroll and inputs.vsizes or inputs.hsizes
		local prange_bits, err = index_to_bits.fuzz_outputs({
			range = prange,
		})
		if not prange_bits then
			return nil, "index_to_bits/prange_bits: " .. err
		end
		local srange_bits, err = index_to_bits.fuzz_outputs({
			range = srange,
		})
		if not srange_bits then
			return nil, "index_to_bits/srange_bits: " .. err
		end
		return {
			prange          = prange,
			prange_bit_low  = prange_bits.bit_low,
			prange_bit_high = prange_bits.bit_high,
			srange          = srange,
			srange_bit_low  = srange_bits.bit_low,
			srange_bit_high = srange_bits.bit_high,
			ssizes          = ssizes,
		}
	end,
})
