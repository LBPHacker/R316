local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.color_select",
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
		{ name = "pixel_print", index = 1, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "char_color" , index = 3, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "pixel_color", index = 5, keepalive = 0x10100000, payload = 0x00EFFFF0, initial = 0x10000000 },
	},
	outputs = {
		{ name = "color", index = 1, keepalive = 0x10000000, payload = 0x00FFFFFF },
	},
	func = function(inputs)
		return {
			color = spaghetti.select(inputs.pixel_print:band(1):zeroable(), inputs.pixel_color, inputs.char_color),
		}
	end,
	fuzz_inputs = function()
		return {
			pixel_print = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			char_color  = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			pixel_color = bitx.bor(0x10000000, bitx.lshift(math.random(0x00000000, 0x000FFFFF), 4)),
		}
	end,
	fuzz_outputs = function(inputs)
		local pixel_print = bitx.band(inputs.pixel_print, 1) ~= 0
		return {
			color = pixel_print and inputs.pixel_color or inputs.char_color,
		}
	end,
})
