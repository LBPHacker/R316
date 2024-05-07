local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local constants = require("r3term.core.constants")

return testbed.module({
	tag = "core.pixel_control",
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
		{ name = "print"   , index = 1, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "position", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "xindex", index = 1, keepalive = 0x2FFE0000, payload = 0x0001FFFF },
		{ name = "yindex", index = 3, keepalive = 0x0FEFFF00, payload = 0x000000FF },
	},
	func = function(inputs)
		local low2p1 = spaghetti.constant(0x3FFFFFFE):lshift(inputs.position:bxor(0x3FFFFFFF)):bxor(0x3FFFFFFF):band(7):assert(1, 6)
		local low2p1_or_none = spaghetti.select(inputs.print:band(1):zeroable(), inputs.position:band(0x10000003):bxor(low2p1), 0x10000000)
		return {
			xindex = low2p1_or_none:bor(spaghetti.lshiftk(inputs.position:bsub(3), 1)):bxor(0x1FFFFFFF),
			yindex = spaghetti.rshiftk(inputs.position, 8):bor(0x10000000):bxor(0x1FFFFFFF),
		}
	end,
	fuzz_inputs = function()
		return {
			print    = bitx.bor(0x00000002, math.random(0, 1)),
			position = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local do_print       = bitx.band(inputs.print  , 1) ~= 0
		local xindex = bitx.band(            inputs.position    , 0xFFFF)
		local yindex = bitx.band(bitx.rshift(inputs.position, 8),   0xFF)
		local xindex_encoded = bitx.lshift(bitx.band(xindex, 0xFFFC), 1)
		if do_print then
			xindex_encoded = bitx.bor(xindex_encoded, bitx.band(xindex, 0x03) + 1)
		end
		return {
			xindex = bit.bxor(0x1FFFFFFF, bitx.bor(0x30000000, xindex_encoded)),
			yindex = bit.bxor(0x1FFFFFFF, bitx.bor(0x10100000, yindex)),
		}
	end,
})
