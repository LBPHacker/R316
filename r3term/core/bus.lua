local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "core.bus",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 50,
	work_slots    = 12,
	inputs = {
		{ name = "ram_data"   , index =  1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram_addr"   , index =  3, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x10000000 },
		{ name = "base_addr"  , index =  5, keepalive = 0x00020000, payload = 0x0000FF80,                    initial = 0x00020000 },
		{ name = "scrollmask" , index =  7, keepalive = 0x20000000, payload = 0x1FFFFFFF,                    initial = 0x20000000 },
		{ name = "range_h"    , index =  9, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "range_v"    , index = 11, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "cursor"     , index = 13, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "newline"    , index = 15, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "color"      , index = 17, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "char0_left" , index = 19, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "char0_right", index = 21, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
	},
	outputs = {
		{ name = "next_scrollmask" , index =  7, keepalive = 0x20000000, payload = 0x1FFFFFFF,                   },
		{ name = "next_range_h"    , index =  9, keepalive = 0x10000000, payload = 0x000003FF,                   },
		{ name = "next_range_v"    , index = 11, keepalive = 0x10000000, payload = 0x000003FF,                   },
		{ name = "next_cursor"     , index = 13, keepalive = 0x10000000, payload = 0x000003FF,                   },
		{ name = "next_newline"    , index = 15, keepalive = 0x10000000, payload = 0x000000FF,                   },
		{ name = "next_color"      , index = 17, keepalive = 0x10000000, payload = 0x000000FF,                   },
		{ name = "next_char0_left" , index = 19, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "next_char0_right", index = 21, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "pixel_print"     , index = 23, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "pixel_position"  , index = 25, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "pixel_color"     , index = 35, keepalive = 0x10100000, payload = 0x00EFFFF0                    },
		{ name = "char_print"      , index = 27, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "char_color"      , index = 29, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "char_char"       , index = 31, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "char_config"     , index = 33, keepalive = 0x10000000, payload = 0x000FFFFF                    },
	},
	func = function(inputs)
		local ram_data = inputs.ram_data:bor(0x10000000):band(0x3FFFFFFF)
		local addressed = inputs.ram_addr:bxor(inputs.base_addr)
		local registers = addressed:bsub(0x08):bsub(0x10):bxor(0x40)
		local prints    = addressed:bsub(0x10):bsub(0x0F)
		local next_char0_left  = spaghetti.select(registers                      :bsub(0x10000000):zeroable(), inputs.char0_left , inputs.ram_data):never_zero()
		local next_char0_right = spaghetti.select(registers:bxor(0x01)           :bsub(0x10000000):zeroable(), inputs.char0_right, inputs.ram_data):never_zero()
		local next_range_h     = spaghetti.select(registers           :bxor(0x02):bsub(0x10000000):zeroable(), inputs.range_h    , ram_data:band(0x100003FF))
		local next_range_v     = spaghetti.select(registers           :bxor(0x03):bsub(0x10000000):zeroable(), inputs.range_v    , ram_data:band(0x100003FF))
		local next_cursor      = spaghetti.select(registers           :bxor(0x04):bsub(0x10000000):zeroable(), inputs.cursor     , ram_data:band(0x100003FF))
		local next_newline     = spaghetti.select(registers:bxor(0x01):bxor(0x04):bsub(0x10000000):zeroable(), inputs.newline    , ram_data:band(0x100000FF))
		local next_color       = spaghetti.select(registers:bxor(0x02):bxor(0x04):bsub(0x10000000):zeroable(), inputs.color      , ram_data:band(0x100000FF))
		local next_scrollmask  = spaghetti.select(registers           :bxor(0x07):bsub(0x10000000):zeroable(), inputs.scrollmask , inputs.ram_data:bor(0x20000000):band(0x3FFFFFFF))
		local pixel_print      = spaghetti.select(prints   :bxor(0x40):bxor(0x20):bsub(0x10000000):zeroable(), 2, 3)
		local char_print       = spaghetti.select(prints              :bsub(0x20):bsub(0x10000000):zeroable(), 2, 3)
		return {
			next_scrollmask  = next_scrollmask,
			next_range_h     = next_range_h,
			next_range_v     = next_range_v,
			next_cursor      = next_cursor,
			next_newline     = next_newline,
			next_color       = next_color,
			next_char0_left  = next_char0_left,
			next_char0_right = next_char0_right,
			pixel_print      = pixel_print,
			pixel_position   = ram_data:band(0x1000FFFF),
			pixel_color      = spaghetti.lshiftk(inputs.ram_addr:bor(0x10000), 4):bor(0x10000000),
			char_print       = char_print,
			char_color       = spaghetti.rshiftk(ram_data, 8):bor(0x10000000):band(0x100000FF),
			char_char        = ram_data:band(0x100000FF),
			char_config      = inputs.ram_addr,
		}
	end,
	fuzz_inputs = function()
		local ram_addr = bitx.bor(0x10000000, bitx.bor(math.random(0x00000000, 0x0000FFFF), bitx.band(0xF0000, bitx.lshift(0x10000, math.random(0, 4)))))
		local target_addr = math.random(0x0000, 0xFFFF)
		if math.random(1, 2) == 1 then
			target_addr = bitx.band(ram_addr, 0xFFFF)
		end
		local base_addr = bitx.bor(0x00020000, bitx.band(target_addr, 0xFF80))
		return {
			ram_data    = testbed.any(),
			ram_addr    = ram_addr,
			base_addr   = base_addr,
			scrollmask  = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
			range_h     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			range_v     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			cursor      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			newline     = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			color       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			char0_left  = testbed.any(),
			char0_right = testbed.any(),
		}
	end,
	fuzz_outputs = function(inputs)
		local address          = bitx.band(inputs.ram_addr, 0x7F)
		local addressed        = bitx.band(inputs.ram_addr, 0xFFF80) == inputs.base_addr
		local next_scrollmask  = bitx.band(inputs.scrollmask , 0x1FFFFFFF)
		local next_range_h     = bitx.band(inputs.range_h    , 0x000003FF)
		local next_range_v     = bitx.band(inputs.range_v    , 0x000003FF)
		local next_cursor      = bitx.band(inputs.cursor     , 0x000003FF)
		local next_newline     = bitx.band(inputs.newline    , 0x000000FF)
		local next_color       = bitx.band(inputs.color      , 0x000000FF)
		local next_char0_left  =           inputs.char0_left
		local next_char0_right =           inputs.char0_right
		local pixel_print = 0
		local char_print = 0
		if addressed then
			if bitx.band(address, 0x40) == 0x00 then
				char_print = 1
			elseif bitx.band(address, 0x67) == 0x40 then
				next_char0_left = inputs.ram_data
			elseif bitx.band(address, 0x67) == 0x41 then
				next_char0_right = inputs.ram_data
			elseif bitx.band(address, 0x67) == 0x42 then
				next_range_h = bitx.band(inputs.ram_data, 0x3FF)
			elseif bitx.band(address, 0x67) == 0x43 then
				next_range_v = bitx.band(inputs.ram_data, 0x3FF)
			elseif bitx.band(address, 0x67) == 0x44 then
				next_cursor = bitx.band(inputs.ram_data, 0x3FF)
			elseif bitx.band(address, 0x67) == 0x45 then
				next_newline = bitx.band(inputs.ram_data, 0xFF)
			elseif bitx.band(address, 0x67) == 0x46 then
				next_color = bitx.band(inputs.ram_data, 0xFF)
			elseif bitx.band(address, 0x67) == 0x47 then
				next_scrollmask = bitx.band(inputs.ram_data, 0x1FFFFFFF)
			elseif bitx.band(address, 0x60) == 0x60 then
				pixel_print = 1
			end
		end
		return {
			next_scrollmask  = bitx.bor(0x20000000, next_scrollmask ),
			next_range_h     = bitx.bor(0x10000000, next_range_h    ),
			next_range_v     = bitx.bor(0x10000000, next_range_v    ),
			next_cursor      = bitx.bor(0x10000000, next_cursor     ),
			next_newline     = bitx.bor(0x10000000, next_newline    ),
			next_color       = bitx.bor(0x10000000, next_color      ),
			next_char0_left  = next_char0_left,
			next_char0_right = next_char0_right,
			pixel_print      = bitx.bor(0x00000002, pixel_print),
			pixel_position   = bitx.bor(0x10000000, bitx.band(inputs.ram_data, 0xFFFF)),
			pixel_color      = bitx.bor(0x10100000, bitx.lshift(inputs.ram_addr, 4)),
			char_print       = bitx.bor(0x00000002, char_print),
			char_color       = bitx.bor(0x10000000, bitx.band(bitx.rshift(inputs.ram_data, 8), 0xFF)),
			char_char        = bitx.bor(0x10000000, bitx.band(inputs.ram_data, 0xFF)),
			char_config      = inputs.ram_addr,
		}
	end,
})
