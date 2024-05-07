local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti     = require("spaghetti")
local bitx          = require("spaghetti.bitx")
local testbed       = require("spaghetti.testbed")
local bus           = require("r3term.core.bus")
local char_control  = require("r3term.core.char_control")
local char_ranges   = require("r3term.core.char_ranges")
local char_advance  = require("r3term.core.char_advance")
local pixel_control = require("r3term.core.pixel_control")

local function flow(inputs, instantiate)
	local bus_outputs = instantiate("bus", bus, {
		ram_data    = inputs.ram_data,
		ram_addr    = inputs.ram_addr,
		base_addr   = inputs.base_addr,
		dirbits     = inputs.dirbits,
		scrollmask  = inputs.scrollmask,
		hrange      = inputs.hrange,
		vrange      = inputs.vrange,
		cursor      = inputs.cursor,
		newline     = inputs.newline,
		color       = inputs.color,
		char0_left  = inputs.char0_left,
		char0_right = inputs.char0_right,
	})
	local char_ranges_outputs = instantiate("char_ranges", char_ranges, {
		dirbits = inputs.dirbits,
		hsizes  = inputs.hsizes,
		vsizes  = inputs.vsizes,
		hrange  = inputs.hrange,
		vrange  = inputs.vrange,
	})
	local char_control_outputs = instantiate("char_control", char_control, {
		print           = bus_outputs.char_print,
		dirbits         = inputs.dirbits,
		prange_bit_low  = char_ranges_outputs.prange_bit_low,
		prange_bit_high = char_ranges_outputs.prange_bit_high,
		ssizes          = char_ranges_outputs.ssizes,
		srange          = char_ranges_outputs.srange,
		scrollmask      = inputs.scrollmask,
	})
	local char_advance_outputs = instantiate("char_advance", char_advance, {
		print           = bus_outputs.char_print,
		cursor          = bus_outputs.next_cursor,
		newline         = inputs.newline,
		prange          = char_ranges_outputs.prange,
		prange_bit_low  = char_ranges_outputs.prange_bit_low,
		prange_bit_high = char_ranges_outputs.prange_bit_high,
		srange          = char_ranges_outputs.srange,
		srange_bit_low  = char_ranges_outputs.srange_bit_low,
		srange_bit_high = char_ranges_outputs.srange_bit_high,
		char            = bus_outputs.char_char,
		smart           = bus_outputs.char_smart,
		dirbits         = inputs.dirbits,
	})
	local pixel_control_outputs = instantiate("pixel_control", pixel_control, {
		print    = bus_outputs.pixel_print,
		position = bus_outputs.pixel_position,
	})
	return {
		next_dirbits     = bus_outputs.next_dirbits,
		next_scrollmask  = bus_outputs.next_scrollmask,
		next_hrange      = bus_outputs.next_hrange,
		next_vrange      = bus_outputs.next_vrange,
		next_cursor      = char_advance_outputs.next_cursor,
		next_newline     = bus_outputs.next_newline,
		next_color       = bus_outputs.next_color,
		next_char0_left  = bus_outputs.next_char0_left,
		next_char0_right = bus_outputs.next_char0_right,
		char_hmask       = char_control_outputs.hmask,
		char_vmask       = char_control_outputs.vmask,
		char_hdray       = char_control_outputs.hdray,
		char_vdray       = char_control_outputs.vdray,
		char_cindex      = char_control_outputs.cindex,
		char_dindex      = char_control_outputs.dindex,
		pixel_xindex     = pixel_control_outputs.xindex,
		pixel_yindex     = pixel_control_outputs.yindex,
	}
end

return testbed.module({
	tag = "core",
	opt_params = {
		thread_count        = 8,
		round_length        = 10000,
		rounds_per_exchange = 10,
		seed                = { 0x12345678, 0x87654321 },
		schedule = {
			durations    = { 1000000, 2000000, 6000000,        },
			temperatures = {      10,       2,       1,    0.5 },
		},
	},
	stacks        = 2,
	storage_slots = 85,
	work_slots    = 20,
	voids         = {},
	clobbers      = {},
	inputs = {
		{ name = "ram_data"   , index =  1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram_addr"   , index =  3, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x10000000 },
		{ name = "base_addr"  , index =  5, keepalive = 0x00020000, payload = 0x0000FFC0,                    initial = 0x00020000 },
		{ name = "scrollmask" , index = 13, keepalive = 0x20000000, payload = 0x1FFFFFFF,                    initial = 0x20000000 },
		{ name = "hrange"     , index = 15, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "vrange"     , index = 17, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "cursor"     , index = 19, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "newline"    , index = 21, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "dirbits"    , index = 23, keepalive = 0x10000000, payload = 0x2FFFFFFF,                    initial = 0x10000000 },
		{ name = "color"      , index = 25, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "char0_left" , index = 27, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "char0_right", index = 29, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "hsizes"     , index =  7, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "vsizes"     , index =  9, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
	},
	outputs = {
		{ name = "next_scrollmask" , index = 13, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "next_hrange"     , index = 15, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_vrange"     , index = 17, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_cursor"     , index = 19, keepalive = 0x10000000, payload = 0x000003FF                    },
		{ name = "next_newline"    , index = 21, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_dirbits"    , index = 23, keepalive = 0x10000000, payload = 0x2FFFFFFF                    },
		{ name = "next_color"      , index = 25, keepalive = 0x10000000, payload = 0x000000FF                    },
		{ name = "next_char0_left" , index = 27, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "next_char0_right", index = 29, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "char_hmask"      , index =  1, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "char_vmask"      , index =  3, keepalive = 0x20000000, payload = 0x1FFFFFFF                    },
		{ name = "char_hdray"      , index =  5, keepalive = 0x10000002, payload = 0x00000001                    },
		{ name = "char_vdray"      , index =  7, keepalive = 0x10000002, payload = 0x00000001                    },
		{ name = "char_cindex"     , index =  9, keepalive = 0x0FFFFFE0, payload = 0x0000001F                    },
		{ name = "char_dindex"     , index = 11, keepalive = 0x0FFFFFE0, payload = 0x0000001F                    },
		{ name = "pixel_xindex"    , index = 31, keepalive = 0x2FFE0000, payload = 0x0001FFFF                    },
		{ name = "pixel_yindex"    , index = 33, keepalive = 0x0FEFFF00, payload = 0x000000FF                    },
	},
	func = function(inputs)
		return flow(inputs, function(name, mod, instance_inputs)
			return mod.instantiate(instance_inputs)
		end)
	end,
	fuzz_inputs = function()
		return {
			ram_data    = testbed.any(),
			char0_left  = testbed.any(),
			char0_right = testbed.any(),
			ram_addr    = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
			base_addr   = bitx.bor(0x00020000, bitx.lshift(math.random(0x00000000, 0x000003FF), 6)),
			scrollmask  = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
			hrange      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			vrange      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			cursor      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			newline     = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			dirbits     = bitx.bor(0x10000000, math.random(0x00000000, 0x3FFFFFFF)),
			color       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			hsizes      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			vsizes      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
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
