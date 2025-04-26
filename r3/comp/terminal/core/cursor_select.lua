local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.cursor_select",
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
		{ name = "char_print"    , index = 1, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "advance_cursor", index = 3, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "bus_cursor"    , index = 5, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "cursor", index = 1, keepalive = 0x10000000, payload = 0x000003FF },
	},
	func = function(inputs)
		return {
			cursor = spaghetti.select(inputs.char_print:band(1):zeroable(), inputs.advance_cursor, inputs.bus_cursor),
		}
	end,
	fuzz_inputs = function()
		return {
			char_print     = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			advance_cursor = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			bus_cursor     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local char_print = bitx.band(inputs.char_print, 1) ~= 0
		return {
			cursor = char_print and inputs.advance_cursor or inputs.bus_cursor,
		}
	end,
})
