local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti     = require("spaghetti")
local bitx          = require("spaghetti.bitx")
local testbed       = require("spaghetti.testbed")
local bus           = require("r3term.core.bus")          .instantiate()
local char_control  = require("r3term.core.char_control") .instantiate()
local char_advance  = require("r3term.core.char_advance") .instantiate()
local pixel_control = require("r3term.core.pixel_control").instantiate()
local color_select  = require("r3term.core.color_select") .instantiate()
local cursor_select = require("r3term.core.cursor_select").instantiate()

local function flow(inputs, component)
	local bus_outputs = component("bus", bus, {
		ram_data      = inputs.ram_data,
		ram_addr      = inputs.ram_addr,
		base_addr     = inputs.base_addr,
		scrollmask    = inputs.scrollmask,
		range_h       = inputs.range_h,
		range_v       = inputs.range_v,
		cursor        = inputs.cursor,
		newline       = inputs.newline,
		color         = inputs.color,
		char0_left    = inputs.char0_left,
		char0_right   = inputs.char0_right,
		ram_data_prev = inputs.ram_data_prev,
		ram_addr_prev = inputs.ram_addr_prev,
		retry         = inputs.retry,
	})
	local char_advance_outputs = component("char_advance", char_advance, {
		print       = bus_outputs.char_print,
		cursor      = inputs.cursor,
		newline     = inputs.newline,
		data_color  = bus_outputs.char_color,
		color       = inputs.color,
		range_h     = inputs.range_h,
		range_v     = inputs.range_v,
		size_h      = inputs.size_h,
		size_v      = inputs.size_v,
		char        = bus_outputs.char_char,
		data_config = bus_outputs.char_config,
		scrollmask  = inputs.scrollmask,
	})
	local char_control_outputs = component("char_control", char_control, {
		print      = char_advance_outputs.print,
		emask      = char_advance_outputs.emask,
		range_s    = char_advance_outputs.range_s,
		char       = char_advance_outputs.char,
		color      = char_advance_outputs.color,
		horizontal = char_advance_outputs.horizontal,
		size_s     = char_advance_outputs.size_s,
	})
	local pixel_control_outputs = component("pixel_control", pixel_control, {
		print    = bus_outputs.pixel_print,
		position = bus_outputs.pixel_position,
	})
	local color_select_outputs = component("color_select", color_select, {
		pixel_print = bus_outputs.pixel_print,
		char_color  = char_advance_outputs.color,
		pixel_color = bus_outputs.pixel_color,
	})
	local cursor_select_outputs = component("cursor_select", cursor_select, {
		char_print     = bus_outputs.char_print,
		advance_cursor = char_advance_outputs.next_cursor,
		bus_cursor     = bus_outputs.next_cursor,
	})
	return {
		next_scrollmask  = bus_outputs.next_scrollmask,
		next_range_h     = bus_outputs.next_range_h,
		next_range_v     = bus_outputs.next_range_v,
		next_cursor      = cursor_select_outputs.cursor,
		retry            = char_advance_outputs.retry,
		next_newline     = bus_outputs.next_newline,
		next_color       = bus_outputs.next_color,
		next_char0_left  = bus_outputs.next_char0_left,
		next_char0_right = bus_outputs.next_char0_right,
		char_color       = color_select_outputs.color,
		char_color_2     = color_select_outputs.color,
		char_hmask       = char_control_outputs.hmask,
		char_vmask       = char_control_outputs.vmask,
		char_hdray       = char_control_outputs.hdray,
		char_vdray       = char_control_outputs.vdray,
		char_cindex      = char_control_outputs.cindex,
		char_dindex      = char_control_outputs.dindex,
		char_rindex_low  = char_control_outputs.rindex_low,
		char_rindex_high = char_control_outputs.rindex_high,
		pixel_xindex     = pixel_control_outputs.xindex,
		pixel_yindex     = pixel_control_outputs.yindex,
		ram_data_prev    = bus_outputs.ram_data_prev,
		ram_addr_prev    = bus_outputs.ram_addr_prev,
	}
end

return testbed.module({
	tag = "core",
	opt_params = {
		thread_count        = 8,
		round_length        = 10000,
		rounds_per_exchange = 10,
		seed                = { 0x12345678, 0x87654321 },
		work_slot_overhead_penalty = 100,
		schedule = {
			durations    = { 1000000, 2000000, 6000000,        },
			temperatures = {      10,       2,       1,    0.5 },
		},
	},
	stacks        = 2,
	storage_slots = 84,
	work_slots    = 20,
	voids         = {},
	clobbers      = {},
	inputs = {
		{ name = "ram_data"     , index = 69, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram_addr"     , index = 66, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x10000000 },
		{ name = "base_addr"    , index = 24, keepalive = 0x00020000, payload = 0x0000FF80,                    initial = 0x00020000 },
		{ name = "scrollmask"   , index =  8, keepalive = 0x20000000, payload = 0x1FFFFFFF,                    initial = 0x20000000 },
		{ name = "range_h"      , index =  1, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "range_v"      , index =  2, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "cursor"       , index =  3, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "newline"      , index =  4, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "color"        , index =  6, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "char0_left"   , index = 79, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "char0_right"  , index = 76, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "size_h"       , index = 20, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "size_v"       , index = 22, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "ram_data_prev", index =  9, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram_addr_prev", index = 10, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x10000000 },
		{ name = "retry"        , index = 71, keepalive = 0x00000002, payload = 0x00000001,                    initial = 0x00000002 },
	},
	outputs = {
		{ name = "next_scrollmask" , index =   8, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "next_range_h"    , index =   1, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_range_v"    , index =   2, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_cursor"     , index =   3, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_newline"    , index =   4, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_color"      , index =   6, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_char0_left" , index =  79, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "next_char0_right", index =  76, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "retry"           , index =  71, keepalive = 0x00000002, payload = 0x00000001                    },
		{ name = "char_hmask"      , index = -20, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "char_vmask"      , index = -17, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "char_hdray"      , index = -19, keepalive = 0x10000004, payload = 0x00000001                    },
		{ name = "char_vdray"      , index = -18, keepalive = 0x10000004, payload = 0x00000001                    },
		{ name = "char_cindex"     , index =  56, keepalive = 0x0FFFFFE0, payload = 0x0000001F                    },
		{ name = "char_dindex"     , index =  36, keepalive = 0x0FFFFFE0, payload = 0x0000001F                    },
		{ name = "char_color"      , index =  -7, keepalive = 0x10000000, payload = 0x00FFFFFF                    },
		{ name = "char_color_2"    , index =   7, keepalive = 0x10000000, payload = 0x00FFFFFF                    },
		{ name = "char_rindex_low" , index =  -4, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "char_rindex_high", index =  -3, keepalive = 0x10000001, payload = 0x00000006                    },
		{ name = "pixel_xindex"    , index = -12, keepalive = 0x2FFE0000, payload = 0x0001FFFF                    },
		{ name = "pixel_yindex"    , index = -14, keepalive = 0x0FEFFF00, payload = 0x000000FF                    },
		{ name = "ram_data_prev"   , index =   9, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "ram_addr_prev"   , index =  10, keepalive = 0x10000000, payload = 0x000FFFFF,                   },
	},
	func = function(inputs)
		return flow(inputs, function(name, mod, instance_inputs)
			return mod.component(instance_inputs)
		end)
	end,
	fuzz_inputs = function()
		return {
			ram_data    = testbed.any(),
			char0_left  = testbed.any(),
			char0_right = testbed.any(),
			ram_addr    = bitx.bor(0x10000000, bitx.bor(math.random(0x00000000, 0x0000FFFF), bitx.band(0xF0000, bitx.lshift(0x10000, math.random(0, 4))))),
			base_addr   = bitx.bor(0x00020000, bitx.lshift(math.random(0x00000000, 0x000001FF), 7)),
			scrollmask  = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
			range_h     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			range_v     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			cursor      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			newline     = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			color       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			size_h      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			size_v      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
		}
	end,
	fuzz_outputs = function(inputs)
		return flow(inputs, function(name, mod, instance_inputs)
			local outputs, err = mod.fuzz_outputs(instance_inputs)
			if not outputs then
				return nil, ("%s: %s"):format(name, err)
			end
			return outputs
		end)
	end,
})
