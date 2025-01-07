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
		{ name = "base_addr"  , index =  5, keepalive = 0x00020000, payload = 0x0000FFC0,                    initial = 0x00020000 },
		{ name = "dirbits"    , index = 11, keepalive = 0x10000000, payload = 0x2FFFFFFF,                    initial = 0x10000000 },
		{ name = "scrollmask" , index = 13, keepalive = 0x20000000, payload = 0x1FFFFFFF,                    initial = 0x20000000 },
		{ name = "hrange"     , index = 15, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "vrange"     , index = 17, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "cursor"     , index = 19, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "newline"    , index = 21, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "color"      , index = 25, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "char0_left" , index = 27, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "char0_right", index = 29, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
	},
	outputs = {
		{ name = "pixel_print"     , index =  1, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "pixel_position"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "char_print"      , index =  5, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "char_color"      , index =  7, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "char_char"       , index =  9, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_dirbits"    , index = 11, keepalive = 0x10000000, payload = 0x2FFFFFFF                    },
		{ name = "next_scrollmask" , index = 13, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "next_hrange"     , index = 15, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_vrange"     , index = 17, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_cursor"     , index = 19, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_newline"    , index = 21, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_color"      , index = 25, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_char0_left" , index = 27, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "next_char0_right", index = 29, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "pixel_color"     , index = 31, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "char_smart"      , index = 33, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "char_rindex_high", index = 37, keepalive = 0x10000001, payload = 0x000000FE                    },
	},
	func = function(inputs)
		local function pack_data_if_needed(shift_to, mask)
			local value = inputs.ram_data
			if not packed then
				value = bitx.bor(bitx.band(value, 0xFFFF), bitx.rshift(value, 16 - shift_to))
			end
			return bitx.band(value, mask)
		end
		local packed_shift = spaghetti.select(inputs.ram_addr:bsub(0x10):bsub(0x03):band(0x3F):zeroable(), 0x100, 0x800):never_zero()
		local packed_needs_shift = spaghetti.select(inputs.ram_addr:band(0x10):zeroable(), 1, packed_shift):never_zero()
		local ram_data = inputs.ram_data:bor(0x20000000):band(0x3FFFFFFF)
		local packed = ram_data:bor(ram_data:rshift(packed_needs_shift):never_zero()):bor(0x10000000)
		local addressed = inputs.ram_addr:bxor(inputs.base_addr)
		local next_cursor      = spaghetti.select(addressed:bsub(0x10)                      :bsub(0x10000000):zeroable(), inputs.cursor     , packed:band(0x100003FF))
		local next_hrange      = spaghetti.select(addressed:bsub(0x10):bxor(0x01)           :bsub(0x10000000):zeroable(), inputs.hrange     , packed:band(0x100003FF))
		local next_vrange      = spaghetti.select(addressed:bsub(0x10):bxor(0x02)           :bsub(0x10000000):zeroable(), inputs.vrange     , packed:band(0x100003FF))
		local next_dirbits     = spaghetti.select(addressed:bsub(0x10):bxor(0x04)           :bsub(0x10000000):zeroable(), inputs.dirbits    , packed                 )
		local next_newline     = spaghetti.select(addressed:bsub(0x10):bxor(0x04):bxor(0x01):bsub(0x10000000):zeroable(), inputs.newline    , packed:band(0x100000FF))
		local next_color       = spaghetti.select(addressed:bsub(0x10):bxor(0x07)           :bsub(0x10000000):zeroable(), inputs.color      , packed:band(0x100000FF))
		local next_scrollmask  = spaghetti.select(addressed:bsub(0x10):bxor(0x08)           :bsub(0x10000000):zeroable(), inputs.scrollmask , ram_data               )
		local next_char0_left  = spaghetti.select(addressed           :bxor(0x03)           :bsub(0x10000000):zeroable(), inputs.char0_left , inputs.ram_data):never_zero()
		local next_char0_right = spaghetti.select(addressed:bxor(0x10):bxor(0x03)           :bsub(0x10000000):zeroable(), inputs.char0_right, inputs.ram_data):never_zero()
		local pixel_print      = spaghetti.select(addressed:bxor(0x20):bsub(0x10):bsub(0x0F):bsub(0x10000000):zeroable(), 2, 3)
		local char_print       = spaghetti.select(addressed:bsub(0x10):bxor(0x08):bxor(0x04):bsub(0x03):bsub(0x10000000):zeroable(), 2, 3)
		return {
			pixel_print      = pixel_print,
			pixel_position   = packed:band(0x1000FFFF),
			pixel_color      = inputs.ram_addr:band(0x1000000F),
			char_print       = char_print,
			char_smart       = inputs.ram_addr:bor(2):band(3),
			char_char        = packed:band(0x100000FF),
			char_rindex_high = spaghetti.rshiftk(packed, 5):bor(0x10000000):bor(1):band(0x100000FF),
			char_color       = spaghetti.select(inputs.ram_addr:band(2):zeroable(), spaghetti.rshiftk(packed, 8):bor(0x10000000):band(0x100000FF), inputs.color),
			next_cursor      = next_cursor,
			next_hrange      = next_hrange,
			next_vrange      = next_vrange,
			next_dirbits     = next_dirbits,
			next_newline     = next_newline,
			next_color       = next_color,
			next_scrollmask  = next_scrollmask,
			next_char0_left  = next_char0_left,
			next_char0_right = next_char0_right,
		}
	end,
	fuzz_inputs = function()
		local ram_addr = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF))
		local target_addr = math.random(0x0000, 0xFFFF)
		if math.random(1, 2) == 1 then
			target_addr = bitx.band(ram_addr, 0xFFFF)
		end
		local base_addr = bitx.bor(0x00020000, bitx.band(target_addr, 0xFFC0))
		return {
			ram_data    = testbed.any(),
			ram_addr    = ram_addr,
			base_addr   = base_addr,
			dirbits     = bitx.bor(0x10000000, math.random(0x00000000, 0x3FFFFFFF)),
			scrollmask  = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
			hrange      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			vrange      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			cursor      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			newline     = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			color       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			char0_left  = testbed.any(),
			char0_right = testbed.any(),
		}
	end,
	fuzz_outputs = function(inputs)
		local next_scrollmask  = bitx.band(inputs.scrollmask, 0x1FFFFFFF)
		local next_dirbits     = bitx.band(inputs.dirbits, 0x000F)
		local next_hrange      = bitx.band(inputs.hrange , 0x03FF)
		local next_vrange      = bitx.band(inputs.vrange , 0x03FF)
		local next_cursor      = bitx.band(inputs.cursor , 0x03FF)
		local next_newline     = bitx.band(inputs.newline, 0x00FF)
		local next_color       = bitx.band(inputs.color  , 0x00FF)
		local next_char0_left  = inputs.char0_left
		local next_char0_right = inputs.char0_right
		local pixel_print = 0
		local char_print = 0
		local addressed  = bitx.band(inputs.ram_addr, 0x000FFFC0) == inputs.base_addr
		local packed     = bitx.band(inputs.ram_addr, 0x10) ~= 0
		local plot_pixel = bitx.band(inputs.ram_addr, 0x20) ~= 0
		local register   = bitx.band(inputs.ram_addr, 0x0F)
		local function pack_data_if_needed(shift_to, mask)
			local value = inputs.ram_data
			if not packed then
				value = bitx.bor(bitx.band(value, 0xFFFF), bitx.rshift(value, 16 - shift_to))
			end
			return bitx.band(value, mask)
		end
		if addressed then
			if plot_pixel then
				pixel_print = 1
			elseif register == 0 then
				next_cursor = pack_data_if_needed(5, 0x3FF)
			elseif register == 1 then
				next_hrange = pack_data_if_needed(5, 0x3FF)
			elseif register == 2 then
				next_vrange = pack_data_if_needed(5, 0x3FF)
			elseif register == 3 then
				if bitx.band(inputs.ram_addr, 0x10) ~= 0 then
					next_char0_right = inputs.ram_data
				else
					next_char0_left = inputs.ram_data
				end
			elseif register == 4 then
				next_dirbits = pack_data_if_needed(8, 0xF)
			elseif register == 5 then
				next_newline = pack_data_if_needed(8, 0xFF)
			elseif register == 7 then
				next_color = pack_data_if_needed(8, 0xFF)
			elseif register == 8 then
				next_scrollmask = bitx.band(inputs.ram_data, 0x1FFFFFFF)
			elseif register >= 12 and register <= 15 then
				char_print = 1
			end
		end
		local char_char_and_color = pack_data_if_needed(8, 0xFFFF)
		local char_color
		if bitx.band(register, 2) ~= 0 then
			char_color = bitx.rshift(char_char_and_color, 8)
		else
			char_color = bitx.band(inputs.color, 0xFF)
		end
		local char_smart = bitx.band(inputs.ram_addr, 0x01)
		local char_char = bitx.band(char_char_and_color, 0xFF)
		local pixel_position = pack_data_if_needed(8, 0xFFFF)
		local pixel_color = bitx.band(inputs.ram_addr, 0x0F)
		return {
			pixel_print      = bitx.bor(0x00000002, pixel_print),
			pixel_position   = pixel_print == 1 and bitx.bor(0x10000000, pixel_position) or false,
			pixel_color      = pixel_print == 1 and bitx.bor(0x10000000, pixel_color   ) or false,
			char_print       = bitx.bor(0x00000002, char_print),
			char_color       = char_print == 1 and bitx.bor(0x10000000, char_color) or false,
			char_char        = char_print == 1 and bitx.bor(0x10000000, char_char ) or false,
			char_rindex_high = char_print == 1 and { value = bitx.bor(0x10000001, bitx.band(bitx.rshift(char_char, 5), 6)), mask = 0x10000007 } or false,
			char_smart       = char_print == 1 and bitx.bor(0x00000002, char_smart) or false,
			next_dirbits     = { value = bitx.bor(0x10000000, next_dirbits), mask = 0x1000000F },
			next_scrollmask  = bitx.bor(0x20000000, next_scrollmask),
			next_hrange      = bitx.bor(0x10000000, next_hrange),
			next_vrange      = bitx.bor(0x10000000, next_vrange),
			next_cursor      = bitx.bor(0x10000000, next_cursor),
			next_newline     = bitx.bor(0x10000000, next_newline),
			next_color       = bitx.bor(0x10000000, next_color),
			next_char0_left  = next_char0_left,
			next_char0_right = next_char0_right,
		}
	end,
})
