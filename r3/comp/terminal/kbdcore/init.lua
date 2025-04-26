local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module({
	tag = "kbdcore",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 5e-7,
		round_length  = 10000,
		seed          = { 0x56789ABC, 0x87654321 },
	},
	stacks        = 1,
	storage_slots = 20,
	work_slots    = 10,
	probe_length  = 3,
	inputs = {
		{ name = "key_input", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flush"    , index =  2, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "output"   , index = 16, keepalive = 0x10000000, payload = 0x0000007F, initial = 0x10000000 },
		{ name = "shift"    , index = 11, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
		{ name = "caps"     , index = 13, keepalive = 0x00000002, payload = 0x00000001, initial = 0x00000002 },
	},
	outputs = {
		{ name = "shift_on"   , index = 17, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "shift_off"  , index = 18, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "caps_on"    , index = 19, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "caps_off"   , index = 20, keepalive = 0x10000004, payload = 0x00000001 },
		{ name = "next_output", index = 16, keepalive = 0x10000000, payload = 0x0000007F },
		{ name = "next_shift" , index = 11, keepalive = 0x00000002, payload = 0x00000001 },
		{ name = "next_caps"  , index = 13, keepalive = 0x00000002, payload = 0x00000001 },
	},
	func = function(inputs)
		local shift = spaghetti.select(inputs.key_input:bxor(1):bsub(0x10000000):zeroable(), inputs.shift, inputs.shift:bxor(1))
		local caps  = spaghetti.select(inputs.key_input:bxor(2):bsub(0x10000000):zeroable(), inputs.caps , inputs.caps :bxor(1))
		local key_shift = shift:bxor(spaghetti.rshiftk(inputs.key_input, 15):bor(2):band(caps):bor(0x10000000)):assert(0x10000000, 0x00000001)
		local key_shift_bits = spaghetti.constant(0x80):bor(key_shift:bxor(1)):assert(0x10000080, 0x00000001)
		local output = inputs.key_input:rshift(key_shift_bits):never_zero():bor(0x10000000):band(0x1000007F)
		local shift_2, output_1 = spaghetti.select(
			inputs.key_input:band(0x4000):zeroable(),
			2, shift,
			output, 0x10000000
		)
		local output_3 = spaghetti.select(inputs.flush:band(1):zeroable(), 0x10000000, inputs.output)
		local output_2 = spaghetti.select(output_3:bxor(0x10000000):zeroable(), output_3, output_1)
		return {
			shift_on    = shift_2:bxor(0x10000007),
			shift_off   = shift_2:bxor(0x10000006),
			caps_on     = caps   :bxor(0x10000007),
			caps_off    = caps   :bxor(0x10000006),
			next_output = output_2,
			next_shift  = shift_2,
			next_caps   = caps,
		}
	end,
	fuzz_inputs = function()
		local key_input = math.random(0x00000000, 0x0000FFFF)
		if math.random(1, 10) == 1 then
			key_input = math.random(0, 2)
		end
		return {
			key_input = bitx.bor(0x10000000, key_input),
			flush     = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			output    = bitx.bor(0x10000000, math.random(0x00000000, 0x0000007F)),
			shift     = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
			caps      = bitx.bor(0x00000002, math.random(0x00000000, 0x00000001)),
		}
	end,
	fuzz_outputs = function(inputs)
		local key_input = bitx.band(inputs.key_input, 0xFFFF)
		local output    = bitx.band(inputs.output, 0x7F)
		local flush     = bitx.band(inputs.flush, 1) ~= 0
		local shift     = bitx.band(inputs.shift, 1) ~= 0
		local caps      = bitx.band(inputs.caps , 1) ~= 0
		if key_input == 1 then
			shift = not shift
		end
		if key_input == 2 then
			caps = not caps
		end
		if flush then
			output = 0
		end
		if bitx.band(key_input, 0x4000) ~= 0 then
			local caps_aware = bitx.band(key_input, 0x8000) ~= 0
			local key_shift = shift
			if caps and caps_aware then
				key_shift = not key_shift
			end
			if output == 0 then
				output = bitx.band(bitx.rshift(key_input, key_shift and 7 or 0), 0x7F)
			end
			shift = false
		end
		return {
			shift_on    = bitx.bor(0x10000004, shift and 0 or 1),
			shift_off   = bitx.bor(0x10000004, shift and 1 or 0),
			caps_on     = bitx.bor(0x10000004, caps  and 0 or 1),
			caps_off    = bitx.bor(0x10000004, caps  and 1 or 0),
			next_output = bitx.bor(0x10000000, output),
			next_shift  = bitx.bor(0x00000002, shift and 1 or 0),
			next_caps   = bitx.bor(0x00000002, caps  and 1 or 0),
		}
	end,
})
