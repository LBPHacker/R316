local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local constants = require("r3.comp.terminal.core.constants")

assert(constants.max_size == 29)
return testbed.module({
	tag = "core.sub_2x5",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 20,
	inputs = {
		{ name = "sizes"  , index = 1, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
		{ name = "indices", index = 3, keepalive = 0x10000000, payload = 0x000003FF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "diffs"  , index = 1, keepalive = 0x10000000, payload = 0x000003FF },
	},
	func = function(inputs)
		local inverted = inputs.indices:bxor(0x3FF):bxor(0x20000000):bxor(0x10000000)
		local diffs = inputs.sizes
		local overflow_coarse = spaghetti.constant(0x10000000)
		for i = 0, 4 do
			local sums = diffs:bxor(inverted):bxor(0x20000000):assert(0x10000000, 0x000003FF)
			local carry_payload = bitx.band(bitx.lshift(0x1F, i + 1), 0x1F)
			carry_payload = bitx.bor(carry_payload, bitx.lshift(carry_payload, 5))
			local carries_2 = diffs:bor(0x20000000):band(inverted)
			overflow_coarse = overflow_coarse:bor(carries_2)
			local carries_1 = spaghetti.lshiftk(carries_2:bsub(0x10):bsub(0x200):bor(0x10000000), 1)
			local carries = carries_1:bor(0x20000000):assert(0x20000000, carry_payload)
			diffs, inverted = sums, carries
		end
		overflow_coarse:assert(0x30000000, 0x000003FF)
		local overflow_0 = overflow_coarse:bsub(0x100):bsub(0x80):bsub(0x40):bsub(0x20):bsub(0x0F)
		local overflow_1 = overflow_0:bor(spaghetti.rshiftk(overflow_0, 1))
		local overflow_2 = overflow_1:bor(spaghetti.rshiftk(overflow_1, 2))
		local overflow_3 = overflow_2:bor(spaghetti.rshiftk(overflow_0, 4))
		return {
			diffs = diffs:band(overflow_3),
		}
	end,
	fuzz_inputs = function()
		local sizes = 0x10000000
		local indices = 0x10000000
		for i = 0, 1 do
			local size = math.random(1, constants.max_size)
			local index = math.random(0, 0x1F)
			sizes = bitx.bor(bitx.lshift(size, i * 5), sizes)
			indices = bitx.bor(bitx.lshift(index, i * 5), indices)
		end
		return {
			sizes   = sizes,
			indices = indices,
		}
	end,
	fuzz_outputs = function(inputs)
		local diffs = 0x10000000
		for i = 0, 1 do
			local size = bitx.band(bitx.rshift(inputs.sizes, i * 5), 0x1F)
			local index = bitx.band(bitx.rshift(inputs.indices, i * 5), 0x1F)
			local diff = size - index - 1
			if diff < 0 then
				diff = 0
			end
			diffs = bitx.bor(bitx.lshift(diff, i * 5), diffs)
		end
		return {
			diffs = diffs,
		}
	end,
})
