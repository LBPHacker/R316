local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local sub_2x5   = require("r3term.core.sub_2x5").instantiate()

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
		{ name = "print"      , index =  1, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "emask"      , index =  3, keepalive = 0x20000000, payload = 0x1FFFFFFF, initial = 0x20000000 },
		{ name = "range_s"    , index =  5, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "char"       , index =  7, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
		{ name = "horizontal" , index = 11, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "size_s"     , index = 13, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "hmask"      , index =  1, keepalive = 0x20000000, payload = 0x1FFFFFFF },
		{ name = "vmask"      , index =  3, keepalive = 0x20000000, payload = 0x1FFFFFFF },
		{ name = "hdray"      , index =  5, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "vdray"      , index =  7, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "cindex"     , index =  9, keepalive = 0x0FFFFFE0, payload = 0x0000001F },
		{ name = "dindex"     , index = 11, keepalive = 0x0FFFFFE0, payload = 0x0000001F },
		{ name = "rindex_low" , index = 15, keepalive = 0x10000000, payload = 0x000000FF },
		{ name = "rindex_high", index = 17, keepalive = 0x10000001, payload = 0x00000006 },
	},
	func = function(inputs)
		local printh = inputs.print:band(inputs.horizontal)        :assert(0x00000002, 0x00000001)
		local printv = inputs.print:band(inputs.horizontal:bxor(1)):assert(0x00000002, 0x00000001)
		local sub_2x5_outputs = sub_2x5.component({
			sizes   = inputs.size_s,
			indices = inputs.range_s,
		})
		return {
			hmask       = spaghetti.select(printh:band(1):zeroable(), inputs.emask, 0x20000000):bxor(0x1FFFFFFF),
			vmask       = spaghetti.select(printv:band(1):zeroable(), inputs.emask, 0x20000000):bxor(0x1FFFFFFF),
			hdray       = printh:bxor(7):bor(0x10000000),
			vdray       = printv:bxor(7):bor(0x10000000),
			cindex      =                   sub_2x5_outputs.diffs                    :band(0x1000001F):bxor(0x1FFFFFFF),
			dindex      = spaghetti.rshiftk(sub_2x5_outputs.diffs, 5):bor(0x10000000):band(0x1000001F):bxor(0x1FFFFFFF),
			rindex_low  = inputs.char,
			rindex_high = spaghetti.rshiftk(inputs.char, 5):bor(0x10000000):bor(1):band(0x100000FF),
		}
	end,
	fuzz_inputs = function()
		return {
			print      = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			emask      = bitx.bor(0x20000000, math.random(0x00000000, 0x1FFFFFFF)),
			range_s    = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
			char       = bitx.bor(0x10000000, math.random(0x00000000, 0x000000FF)),
			horizontal = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			size_s     = bitx.bor(0x10000000, math.random(0x00000000, 0x000003FF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local do_print   = bitx.band(inputs.print     , 1) ~= 0
		local horizontal = bitx.band(inputs.horizontal, 1) ~= 0
		local sub_2x5_outputs, err = sub_2x5.fuzz_outputs({
			sizes   = inputs.size_s,
			indices = inputs.range_s,
		})
		if not sub_2x5_outputs then
			return nil, "sub_2x5: " .. err
		end
		local diffs = bitx.band(sub_2x5_outputs.diffs, 0x3FF)
		local printh = do_print and     horizontal
		local printv = do_print and not horizontal
		return {
			hmask       = bitx.bxor(bitx.bor(0x20000000, printh and inputs.emask or 0), 0x1FFFFFFF),
			vmask       = bitx.bxor(bitx.bor(0x20000000, printv and inputs.emask or 0), 0x1FFFFFFF),
			hdray       = bitx.bor(0x10000004, printh and 0 or 1),
			vdray       = bitx.bor(0x10000004, printv and 0 or 1),
			cindex      = bitx.bxor(bitx.bor(0x10000000, bitx.band(            diffs    , 0x1F)), 0x1FFFFFFF),
			dindex      = bitx.bxor(bitx.bor(0x10000000, bitx.band(bitx.rshift(diffs, 5), 0x1F)), 0x1FFFFFFF),
			rindex_low  = inputs.char,
			rindex_high = { value = bitx.bor(0x10000001, bitx.band(bitx.rshift(inputs.char, 5), 6)), mask = 0x10000007 },
		}
	end,
})
