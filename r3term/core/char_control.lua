local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local constants = require("r3term.core.constants")
local sub_2x5   = require("r3term.core.sub_2x5")

assert(constants.max_size == 29)
return testbed.module({
	tag = "core.char_control",
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
		{ name = "print"          , index =  1, keepalive = 0x00000002, payload = 0x00000001,                    initial = 0x00000002 },
		{ name = "dirbits"        , index =  3, keepalive = 0x10000000, payload = 0x2FFFFFFF,                    initial = 0x10000000 },
		{ name = "prange_bit_low" , index =  5, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "prange_bit_high", index =  7, keepalive = 0x00000000, payload = 0x1FFFFFFF, never_zero = true, initial = 0x00000001 },
		{ name = "ssizes"         , index =  9, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "srange"         , index = 11, keepalive = 0x10000000, payload = 0x000003FF,                    initial = 0x10000000 },
		{ name = "scrollmask"     , index = 13, keepalive = 0x20000000, payload = 0x1FFFFFFF,                    initial = 0x20000000 },
	},
	outputs = {
		{ name = "hmask" , index =  1, keepalive = 0x20000000, payload = 0x1FFFFFFF },
		{ name = "vmask" , index =  3, keepalive = 0x20000000, payload = 0x1FFFFFFF },
		{ name = "hdray" , index =  5, keepalive = 0x10000002, payload = 0x00000001 },
		{ name = "vdray" , index =  7, keepalive = 0x10000002, payload = 0x00000001 },
		{ name = "cindex", index =  9, keepalive = 0x0FFFFFE0, payload = 0x0000001F },
		{ name = "dindex", index = 11, keepalive = 0x0FFFFFE0, payload = 0x0000001F },
	},
	func = function(inputs)
		local printh = inputs.print:band(inputs.dirbits:bor(2))        :assert(0x00000002, 0x00000001)
		local printv = inputs.print:band(inputs.dirbits:bor(2):bxor(1)):assert(0x00000002, 0x00000001)
		local sub_2x5_outputs = sub_2x5.instantiate({
			sizes   = inputs.ssizes,
			indices = inputs.srange,
		})
		local bitl = inputs.prange_bit_low
		local bith = inputs.prange_bit_high
		local maskl = spaghetti.constant(0x3FFFFFFE):lshift(bitl):assert(0x20000000, 0x1FFFFFFE)
		                             :bxor(0x1FFFFFFF):bxor(bitl):assert(0x20000000, 0x1FFFFFFF)
		local maskh = spaghetti.constant(0x3FFFFFFE):lshift(bith):assert(0x20000000, 0x1FFFFFFE)
		                             :bxor(0x1FFFFFFF):bxor(bith):assert(0x20000000, 0x1FFFFFFF)
		local maskhl = maskh:bsub(0x10000000)
		local maskll = maskl:bor(0x10000000)
		local maskxl = maskhl:bxor(maskll):band(0x1000FFFF):bor(0x20000000):bsub(0x10000000):assert(0x20000000, 0x0000FFFF)
		local maskhh = spaghetti.rshiftk(maskh, 16)
		local masklh = spaghetti.rshiftk(maskl, 16):bor(0x20000000)
		local maskxh = spaghetti.lshiftk(maskhh:bxor(masklh):bor(0x00002000):assert(0x20002000, 0x00001FFF), 16):assert(0x20000000, 0x1FFF0000)
		local maskx = maskxh:bor(maskxl):assert(0x20000000, 0x1FFFFFFF)
		local emask = bitl:bor(bith):never_zero():bor(maskx)
		local mask_last = spaghetti.select(inputs.dirbits:band(2):zeroable(), inputs.scrollmask, emask):assert(0x20000000, 0x1FFFFFFF)
		return {
			hmask  = spaghetti.select(printh:band(1):zeroable(), mask_last, 0x20000000):bxor(0x1FFFFFFF),
			vmask  = spaghetti.select(printv:band(1):zeroable(), mask_last, 0x20000000):bxor(0x1FFFFFFF),
			hdray  = printh:bor(0x10000000),
			vdray  = printv:bor(0x10000000),
			cindex =                   sub_2x5_outputs.diffs                    :band(0x1000001F):bxor(0x1FFFFFFF),
			dindex = spaghetti.rshiftk(sub_2x5_outputs.diffs, 5):bor(0x10000000):band(0x1000001F):bxor(0x1FFFFFFF),
		}
	end,
	fuzz_inputs = function()
		local size = math.random(1, constants.max_size)
		local ssizes = bitx.bor(bitx.lshift(size                , 5), size                )
		local srange = bitx.bor(bitx.lshift(math.random(0, 0x1F), 5), math.random(0, 0x1F))
		return {
			ssizes          = bitx.bor(0x10000000, ssizes),
			srange          = bitx.bor(0x10000000, srange),
			prange_bit_low  = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			prange_bit_high = bitx.lshift(1, math.random(0, constants.max_size - 1)),
			print           = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			dirbits         = bitx.bor(0x10000000, math.random(0x00000000, 0x3FFFFFFF)),
			scrollmask      = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local do_print       = bitx.band(inputs.print  , 1) ~= 0
		local horiz          = bitx.band(inputs.dirbits, 1) ~= 0
		local use_scrollmask = bitx.band(inputs.dirbits, 2) ~= 0
		local scrollmask     = bitx.band(inputs.scrollmask, 0x1FFFFFFF)
		local bitl = inputs.prange_bit_low
		local bith = inputs.prange_bit_high
		local maskl = bitl - 1
		local maskh = bith - 1
		local emask = bitx.bor(bitx.bor(bitx.bxor(maskl, maskh), bitl), bith)
		if use_scrollmask then
			emask = scrollmask
		end
		local sub_2x5_outputs, err = sub_2x5.fuzz_outputs({
			sizes   = inputs.ssizes,
			indices = inputs.srange,
		})
		if not sub_2x5_outputs then
			return nil, "sub_2x5: " .. err
		end
		local diffs = bitx.band(sub_2x5_outputs.diffs, 0x3FF)
		local printh = do_print and     horiz
		local printv = do_print and not horiz
		return {
			hmask  = bitx.bxor(bitx.bor(0x20000000, printh and emask or 0), 0x1FFFFFFF),
			vmask  = bitx.bxor(bitx.bor(0x20000000, printv and emask or 0), 0x1FFFFFFF),
			hdray  = bitx.bor(0x10000002, printh and     1 or 0),
			vdray  = bitx.bor(0x10000002, printv and     1 or 0),
			cindex = bitx.bxor(bitx.bor(0x10000000, bitx.band(            diffs    , 0x1F)), 0x1FFFFFFF),
			dindex = bitx.bxor(bitx.bor(0x10000000, bitx.band(bitx.rshift(diffs, 5), 0x1F)), 0x1FFFFFFF),
		}
	end,
})
