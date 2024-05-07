local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
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
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 12,
	inputs = {
		{ name = "print"          , index =  1, keepalive = 0x00000002, payload = 0x00000001,                    initial = 0x00000002 },
		{ name = "cursor"         , index =  3, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "newline"        , index =  5, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "prange"         , index =  9, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "prange_bit_low" , index = 11, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "prange_bit_high", index = 13, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "srange"         , index = 15, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "srange_bit_low" , index = 17, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "srange_bit_high", index = 19, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "char"           , index = 21, keepalive = 0x10000000, payload = 0x000000FF,                    initial = 0x10000000 },
		{ name = "smart"          , index = 23, keepalive = 0x00000002, payload = 0x00000001,                    initial = 0x00000002 },
		{ name = "dirbits"        , index = 25, keepalive = 0x10000000, payload = 0x2FFFFFFF,                    initial = 0x10000000 },
	},
	outputs = {
		{ name = "next_cursor", index = 1, keepalive = 0x10000000, payload = 0x000003FF },
	},
	func = function(inputs)
		local horiz_shift = inputs.dirbits:bsub(0xFFFE):bor(0x20):assert(0x10000020, 0x2FFF0001)
		local horiz_shift_inv = horiz_shift:bxor(1)
		local newline = spaghetti.select(inputs.newline:bxor(inputs.char):zeroable(), 2, 3)
		local wrap     = spaghetti.rshiftk(inputs.dirbits, 3):bor(2):band(3)
		local flip_p   = spaghetti.select(inputs.prange_bit_high:rshift(inputs.prange_bit_low):zeroable(), 0x3F, 0x20)
		local flip_s   = spaghetti.select(inputs.srange_bit_high:rshift(inputs.srange_bit_low):zeroable(), 0x3F, 0x20)
		local cursor_p = inputs.cursor:rshift(horiz_shift)    :never_zero():bor(0x10000000):band(0x1000001F)
		local cursor_s = inputs.cursor:rshift(horiz_shift_inv):never_zero():bor(0x10000000):band(0x1000001F)
		local low_p    = inputs.prange                                                     :band(0x1000001F)
		local high_p   = spaghetti.rshiftk(inputs.prange, 5)               :bor(0x10000000):band(0x1000001F)
		local low_s    = inputs.srange                                                     :band(0x1000001F)
		local high_s   = spaghetti.rshiftk(inputs.srange, 5)               :bor(0x10000000):band(0x1000001F)
		local function apply_incr(cursor, flip)
			cursor = cursor:bxor(flip)
			cursor = spaghetti.constant(0x3FFFFFFE):lshift(cursor):bxor(0x3FFFFFFF):bxor(cursor)
			cursor = cursor:bxor(flip)
			return cursor:bsub(0x20):assert(0x10000000, 0x0000001F)
		end
		local eot_p     = spaghetti.select(cursor_p:bxor(high_p):zeroable(), 2, 3)
		local cursor_p1 = apply_incr(cursor_p, flip_p)
		local cursor_s1 = apply_incr(cursor_s, flip_s)
		local home_p    = eot_p:bor(newline)
		local cursor_p2 = spaghetti.select(home_p:band(1):zeroable(), low_p, cursor_p1):assert(0x10000000, 0x0000001F)
		local cursor_s2 = spaghetti.select(cursor_s:bxor(high_s):zeroable(), cursor_s1, low_s)
		local use_s2    = home_p:band(wrap)
		local cursor_s3 = spaghetti.select(use_s2:band(1):zeroable(), cursor_s2, cursor_s):assert(0x10000000, 0x0000001F)
		local next_cursor =      cursor_p2:bor(0x10000):lshift(horiz_shift)    :never_zero()
		                    :bor(cursor_s3:bor(0x10000):lshift(horiz_shift_inv):never_zero()):never_zero()
		                    :bor(0x10000000):band(0x100003FF)
		return {
			next_cursor = spaghetti.select(inputs.smart:band(inputs.print):band(1):zeroable(), next_cursor, inputs.cursor),
		}
	end,
	fuzz_inputs = function()
		local dirbits = bitx.band(math.random(0x00000000, 0x3FFFFFFF), 0x2FFFFFFF)
		local prange  = math.random(0x00000000, 0x000003FF)
		local srange  = math.random(0x00000000, 0x000003FF)
		local cursor  = math.random(0x00000000, 0x000003FF)
		if math.random(1, 2) == 1 then
			local horiz = bitx.band(dirbits, 1) ~= 0
			local replace_with
			local kind = math.random(1, 4)
			if kind == 1 then
				replace_with = bitx.rshift(bitx.band(srange, 0x1F), 5)
				horiz = not horiz
			elseif kind == 2 then
				replace_with = bitx.band(srange, 0x1F)
				horiz = not horiz
			elseif kind == 3 then
				replace_with = bitx.rshift(bitx.band(prange, 0x1F), 5)
			elseif kind == 4 then
				replace_with = bitx.band(prange, 0x1F)
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
			prange_bit_low  = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			prange_bit_high = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			srange_bit_low  = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			srange_bit_high = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			print           = bitx.bor(0x10000000, math.random(0x00000000, 0x00000001)),
			cursor          = bitx.bor(0x10000000, cursor),
			newline         = bitx.bor(0x10000000, newline),
			prange          = bitx.bor(0x10000000, prange),
			srange          = bitx.bor(0x10000000, srange),
			char            = bitx.bor(0x10000000, char),
			smart           = bitx.bor(0x10000000, math.random(0x00000000, 0x00000001)),
			dirbits         = bitx.bor(0x10000000, dirbits),
		}
	end,
	fuzz_outputs = function(inputs)
		local newline  = bitx.band(inputs.newline, 0xFF)
		local char     = bitx.band(inputs.char   , 0xFF)
		local do_print = bitx.band(inputs.print  , 1) ~= 0
		local horiz    = bitx.band(inputs.dirbits, 1) ~= 0
		-- local scroll   = bitx.band(inputs.dirbits, 4) ~= 0 -- TODO
		local scroll   = false
		local wrap     = bitx.band(inputs.dirbits, 8) ~= 0
		local smart    = bitx.band(inputs.smart  , 1) ~= 0
		local incr_p   = (inputs.prange_bit_low > inputs.prange_bit_high) and -1 or 1
		local incr_s   = (inputs.srange_bit_low > inputs.srange_bit_high) and -1 or 1
		local cursor_x = bitx.band(            inputs.cursor    , 0x1F)
		local cursor_y = bitx.band(bitx.rshift(inputs.cursor, 5), 0x1F)
		local cursor_p = horiz and cursor_x or cursor_y
		local cursor_s = horiz and cursor_y or cursor_x
		local low_p    = bitx.band(            inputs.prange    , 0x1F)
		local high_p   = bitx.band(bitx.rshift(inputs.prange, 5), 0x1F)
		local low_s    = bitx.band(            inputs.srange    , 0x1F)
		local high_s   = bitx.band(bitx.rshift(inputs.srange, 5), 0x1F)
		if do_print and smart then
			local old_cursor_p = cursor_p
			cursor_p = bitx.band(cursor_p + incr_p, 0x1F)
			if old_cursor_p == high_p or newline == char then
				cursor_p = low_p
				if wrap then
					local old_cursor_s = cursor_s
					if scroll then
						-- TODO
					else
						cursor_s = bitx.band(cursor_s + incr_s, 0x1F)
						if old_cursor_s == high_s then
							cursor_s = low_s
						end
					end
				end
			end
		end
		local next_cursor_x = horiz and cursor_p or cursor_s
		local next_cursor_y = horiz and cursor_s or cursor_p
		local next_cursor = bitx.bor(bitx.lshift(next_cursor_y, 5), next_cursor_x)
		return {
			next_cursor = bitx.bor(0x10000000, next_cursor),
		}
	end,
})
