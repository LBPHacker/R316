local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti      = require("spaghetti")
local bitx           = require("spaghetti.bitx")
local testbed        = require("spaghetti.testbed")
local range_to_rbits = require("r3term.core.range_to_rbits")
local rbits_to_mask  = require("r3term.core.rbits_to_mask")
local constants = require("r3term.core.constants")

assert(constants.max_size == 29)
return testbed.module({
	tag = "core.char_advance",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 2,
	storage_slots = 70,
	work_slots    = 30,
	inputs = {
		{ name = "print"      , index =  1, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "cursor"     , index =  3, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "newline"    , index =  5, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "data_color" , index =  7, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "color"      , index =  9, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "range_h"    , index = 11, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "range_v"    , index = 13, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "size_h"     , index = 23, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "size_v"     , index = 25, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "char"       , index = 15, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "data_config", index = 19, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
		{ name = "scrollmask" , index = 21, keepalive = 0x20000000, payload = 0x1FFFFFFF, initial = 0x20000000 },
	},
	outputs = {
		{ name = "next_cursor", index =  1, keepalive = 0x10000000, payload = 0x000003FF },
		{ name = "print"      , index =  3, keepalive = 0x00000002, payload = 0x00000001 },
		{ name = "emask"      , index =  5, keepalive = 0x20000000, payload = 0x1FFFFFFF },
		{ name = "range_s"    , index =  7, keepalive = 0x10000000, payload = 0x000003FF },
		{ name = "size_s"     , index = 17, keepalive = 0x10000000, payload = 0x000003FF },
		{ name = "char"       , index =  9, keepalive = 0x10000000, payload = 0x000000FF },
		{ name = "color"      , index = 11, keepalive = 0x10000000, payload = 0x000000FF },
		{ name = "horizontal" , index = 13, keepalive = 0x00000002, payload = 0x00000001 },
		{ name = "retry"      , index = 15, keepalive = 0x00000002, payload = 0x00000001 },
	},
	func = function(inputs)
		local smart            =                   inputs.data_config    :bor(2):band(3)
		local horiz            = spaghetti.rshiftk(inputs.data_config, 2)
		local scroll           = spaghetti.rshiftk(inputs.data_config, 4):bor(2):band(3)
		local allow_newline    = spaghetti.rshiftk(inputs.data_config, 5):bor(2):band(3)
		local horiz_shift      = horiz:bsub(0xFFFE):bor(0x20):assert(0x04000020, 0x00030001)
		local horiz_shift_inv  = horiz_shift:bxor(1)
		local newline          = spaghetti.select(inputs.newline:bxor(inputs.char):zeroable(), 2, allow_newline)
		local range_p, range_s, size_s = spaghetti.select(
			horiz:band(1):zeroable(),
			inputs.range_h, inputs.range_v,
			inputs.range_v, inputs.range_h,
			inputs.size_v, inputs.size_h
		)
		local cursor_p = inputs.cursor:rshift(horiz_shift)    :never_zero():bor(0x10000000):band(0x1000001F)
		local cursor_s = inputs.cursor:rshift(horiz_shift_inv):never_zero():bor(0x10000000):band(0x1000001F)
		local range_p_bits = range_to_rbits.instantiate({
			range = range_p,
		})
		local range_s_bits = range_to_rbits.instantiate({
			range = range_s,
		})
		local flip_p = spaghetti.select(range_p_bits.bit_high:rshift(range_p_bits.bit_low):zeroable(), 0x3F, 0x20)
		local flip_s = spaghetti.select(range_s_bits.bit_high:rshift(range_s_bits.bit_low):zeroable(), 0x3F, 0x20)
		local low_p  = range_p                                      :band(0x1000001F)
		local high_p = spaghetti.rshiftk(range_p, 5):bor(0x10000000):band(0x1000001F)
		local low_s  = range_s                                      :band(0x1000001F)
		local high_s = spaghetti.rshiftk(range_s, 5):bor(0x10000000):band(0x1000001F)
		local function apply_incr(cursor, flip)
			cursor = cursor:bxor(flip)
			cursor = spaghetti.constant(0x3FFFFFFE):lshift(cursor):bxor(0x3FFFFFFF):bxor(cursor)
			cursor = cursor:bxor(flip)
			return cursor:bsub(0x20):assert(0x10000000, 0x0000001F)
		end
		local eot_p = spaghetti.select(cursor_p:bxor(apply_incr(high_p, flip_p)):zeroable(), 2, 3)
		local eot_s = spaghetti.select(cursor_s:bxor(           high_s         ):zeroable(), 2, 3)
		local wrap_p = eot_p:bor(newline)
		local cursor_s2 = spaghetti.select(scroll:band(1):zeroable(), high_s, low_s)
		local cursor_s1 = spaghetti.select(eot_s:band(1):zeroable(), cursor_s2, apply_incr(cursor_s, flip_s))
		local cursor_p1, cursor_s3 = spaghetti.select(wrap_p:band(1):zeroable(), low_p, cursor_p, cursor_s1, cursor_s)
		local retry = wrap_p:band(eot_s):band(smart):band(scroll):band(newline:bxor(1))
		local cursor_p2 = spaghetti.select(newline:bor(retry):band(1):zeroable(), cursor_p1, apply_incr(cursor_p1, flip_p))
		local entire_range = smart:bxor(1):bor(wrap_p:band(eot_s):band(smart):band(scroll))
		local range_s_out, emask_range = spaghetti.select(
			entire_range:band(1):zeroable(),
			range_s, cursor_s3:bor(spaghetti.lshiftk(cursor_s3:bor(0x00000200), 5)):band(0x100003FF),
			range_p, cursor_p1:bor(spaghetti.lshiftk(cursor_p1:bor(0x00000200), 5)):band(0x100003FF)
		)
		local char = spaghetti.select(
			wrap_p:band(eot_s):band(scroll):band(1):zeroable(),
			inputs.newline, inputs.char
		)
		local next_cursor =      cursor_p2:bor(0x10000):lshift(horiz_shift)    :never_zero()
		                    :bor(cursor_s3:bor(0x10000):lshift(horiz_shift_inv):never_zero()):never_zero()
		                    :bor(0x10000000):band(0x100003FF)
		local next_cursor2 = spaghetti.select(
			inputs.print:band(smart):band(1):zeroable(),
			next_cursor, inputs.cursor
		)
		local emask_bits = range_to_rbits.instantiate({
			range = emask_range,
		})
		local emask = rbits_to_mask.instantiate({
			bit_low  = emask_bits.bit_low,
			bit_high = emask_bits.bit_high,
		})
		local color = spaghetti.select(inputs.data_config:band(2):zeroable(), inputs.data_color, inputs.color)
		return {
			next_cursor = next_cursor2,
			emask       = spaghetti.select(inputs.data_config:band(8):zeroable(), inputs.scrollmask, emask.mask),
			retry       = retry:band(inputs.print),
			print       = inputs.print:band(wrap_p:band(eot_s):band(smart):band(scroll:bxor(1)):band(newline):bxor(1)),
			char        = char,
			range_s     = range_s_out,
			size_s      = size_s,
			color       = spaghetti.select(inputs.print:band(1):zeroable(), color, 0x10000000),
			horizontal  = horiz:bor(2):band(3),
		}
	end,
	fuzz_inputs = function()
		local range_h = math.random(0x00000000, 0x000003FF)
		local range_v = math.random(0x00000000, 0x000003FF)
		local cursor = math.random(0x00000000, 0x000003FF)
		if math.random(1, 2) == 1 then
			local replace_with, horiz
			local kind = math.random(1, 4)
			if kind == 1 then
				replace_with, horiz = bitx.rshift(bitx.band(range_v, 0x1F), 5), false
			elseif kind == 2 then
				replace_with, horiz = bitx.band(range_v, 0x1F), false
			elseif kind == 3 then
				replace_with, horiz = bitx.rshift(bitx.band(range_h, 0x1F), 5), true
			elseif kind == 4 then
				replace_with, horiz = bitx.band(range_h, 0x1F), true
			end
			local shift = horiz and 0 or 5
			cursor = bitx.bor(bitx.band(cursor, bitx.lshift(0x1F, 5 - shift)), bitx.lshift(replace_with, shift))
		end
		local newline = math.random(0x00000000, 0x000000FF)
		local char = math.random(0x00000000, 0x000000FF)
		if math.random(1, 8) == 1 then
			char = newline
		end
		return {
			print       = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			char        = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			newline     = bitx.bor(0x10000000, newline),
			range_h     = bitx.bor(0x10000000, range_h),
			range_v     = bitx.bor(0x10000000, range_v),
			size_h      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			size_v      = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			cursor      = bitx.bor(0x10000000, cursor),
			data_config = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
			data_color  = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			color       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			scrollmask  = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local do_print     = bitx.band(inputs.print, 1) ~= 0
		local char         = bitx.band(inputs.char, 0xFF)
		local newline_char = bitx.band(inputs.newline, 0xFF)
		local range_h      = bitx.band(inputs.range_h, 0x3FF)
		local range_v      = bitx.band(inputs.range_v, 0x3FF)
		local size_h       = bitx.band(inputs.size_h, 0x3FF)
		local size_v       = bitx.band(inputs.size_v, 0x3FF)
		local cursor_x     = bitx.band(            inputs.cursor    , 0x1F)
		local cursor_y     = bitx.band(bitx.rshift(inputs.cursor, 5), 0x1F)
		local smart        = bitx.band(inputs.data_config,  1) ~= 0
		local usecolor     = bitx.band(inputs.data_config,  2) ~= 0
		local horizontal   = bitx.band(inputs.data_config,  4) ~= 0
		local scrollmask   = bitx.band(inputs.data_config,  8) ~= 0
		local scroll       = bitx.band(inputs.data_config, 16) ~= 0
		local newlinea     = bitx.band(inputs.data_config, 32) ~= 0
		local color        = inputs.data_color
		if not usecolor then
			color = inputs.color
		end
		local function horiz_select(primary_if_horiz, secondary_if_horiz)
			if horizontal then
				return primary_if_horiz, secondary_if_horiz
			end
			return secondary_if_horiz, primary_if_horiz
		end
		local function range_first(range)
			return bitx.band(range, 0x1F)
		end
		local function range_last(range)
			return bitx.band(bitx.rshift(range, 5), 0x1F)
		end
		local function range_direction(range)
			return math.min(range_first(range), constants.max_size - 1) > math.min(range_last(range), constants.max_size - 1) and -1 or 1
		end
		local function range_after_last(range)
			return bitx.band(range_last(range) + range_direction(range), 0x1F)
		end
		local function range_to_mask(range)
			local rbits, err = range_to_rbits.fuzz_outputs({
				range = bitx.bor(0x10000000, range),
			})
			if not rbits then
				return nil, "range_to_rbits: " .. err
			end
			local mask, err = rbits_to_mask.fuzz_outputs({
				bit_low  = rbits.bit_low,
				bit_high = rbits.bit_high,
			})
			if not mask then
				return nil, "rbits_to_mask: " .. err
			end
			return mask.mask
		end
		local range_p, range_s = horiz_select(range_h, range_v)
		local _, size_s = horiz_select(size_h, size_v)
		local cursor_p, cursor_s = horiz_select(cursor_x, cursor_y)

		local eot_p = cursor_p == range_after_last(range_p)
		local newline = newlinea and char == newline_char
		local wrap_p = eot_p or newline
		if wrap_p then
			cursor_p = range_first(range_p)
		end
		local set_cursor = do_print and smart
		local retry = false
		local entire_range = not smart
		if wrap_p then
			local old_cursor_s = cursor_s
			cursor_s = bitx.band(cursor_s + range_direction(range_s), 0x1F)
			if old_cursor_s == range_last(range_s) then
				if scroll then
					cursor_s = range_last(range_s)
					char = newline_char
					if smart then
						entire_range = true
						if not newline and do_print then
							retry = true
						end
					end
				else
					cursor_s = range_first(range_s)
					if newline and smart then
						do_print = false
					end
				end
			end
		end
		local range_s_out = entire_range and range_s or bitx.bor(cursor_s, bitx.lshift(cursor_s, 5))
		local emask_range = entire_range and range_p or bitx.bor(cursor_p, bitx.lshift(cursor_p, 5))
		if not newline and not retry then
			cursor_p = bitx.band(cursor_p + range_direction(range_p), 0x1F)
		end

		local emask, emask_err = range_to_mask(emask_range)
		if not emask then
			return nil, emask_err
		end
		if scrollmask then
			emask = inputs.scrollmask
		end
		local next_cursor_x, next_cursor_y = horiz_select(cursor_p, cursor_s)
		local next_cursor = bitx.bor(bitx.lshift(next_cursor_y, 5), next_cursor_x)
		return {
			next_cursor = bitx.bor(0x10000000, set_cursor and next_cursor or inputs.cursor),
			emask       = bitx.bor(0x20000000, emask),
			range_s     = bitx.bor(0x10000000, range_s_out),
			size_s      = bitx.bor(0x10000000, size_s),
			char        = bitx.bor(0x10000000, char),
			color       = bitx.bor(0x10000000, color),
			print       = bitx.bor(0x00000002, do_print   and 1 or 0),
			horizontal  = bitx.bor(0x00000002, horizontal and 1 or 0),
			retry       = bitx.bor(0x00000002, retry      and 1 or 0),
		}
	end,
})
