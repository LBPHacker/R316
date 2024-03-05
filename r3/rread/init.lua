local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")

return testbed.module({
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 5e-7,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 16,
	work_slots    = 10,
	probe_length  = 3,
	inputs = {
		{ name = "curr_instr", index = 1, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "ram_data"  , index = 2, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x1000DEAD, never_zero = true },
	},
	outputs = {
		{ name = "pri_reg", index = 1, keepalive = 0x10000040, payload = 0x0000003E },
		{ name = "sec_reg", index = 2, keepalive = 0x10000000, payload = 0x000000FE },
	},
	func = function(inputs)
		local ram_high    = spaghetti.rshiftk(inputs.ram_data:bor(0x00010000):bsub(0x0000FFFF), 16):bor(0x00010000):bsub(0x10000000):assert(0x00010001, 0x2FFEFFFE)
		local select_mask = spaghetti.lshift(0x3FFFFFFF, spaghetti.rshiftk(inputs.curr_instr, 16):bor(0x00010000):band(0x00010001)) :assert(0x3FFF0000, 0x0000FFFF)
		local instr_data  = inputs.curr_instr:bxor(ram_high):band(select_mask):bxor(ram_high)                                       :assert(0x10000000, 0x2FFFFFFF)
		local pri_reg     = spaghetti.rshiftk(instr_data, 8):bor(0x10000040):band(0x1000007E)
		local sec_reg     = spaghetti.rshiftk(instr_data, 3):bor(0x10000040):band(0x1000007E)
		local sec_reg_inv = sec_reg:bxor(0x3FFFFFFF)
		local sec_reg_p16 = spaghetti.lshift(0x3FFFFFFE, sec_reg_inv:bsub(0x0000000F)):bxor(sec_reg_inv):bxor(0x0000000F)
		return {
			pri_reg = pri_reg,
			sec_reg = sec_reg_p16,
		}
	end,
	fuzz_inputs = function()
		local ram_data = testbed.any()
		local curr_instr = math.random(0x00000000, 0x0001FFFF)
		return {
			ram_data   = ram_data,
			curr_instr = bitx.bor(0x10000000, curr_instr),
		}
	end,
	fuzz_outputs = function(inputs)
		local instr_data = bitx.rshift(inputs.ram_data, 16)
		if bitx.band(inputs.curr_instr, 0x10000) ~= 0 then
			instr_data = inputs.curr_instr
		end
		local pri_reg = bitx.band(bitx.rshift(instr_data, 9), 0x1F) * 2 + 64
		local sec_reg = bitx.band(bitx.rshift(instr_data, 4), 0x1F) * 2 + 80
		return {
			pri_reg = bitx.bor(0x10000000, pri_reg),
			sec_reg = bitx.bor(0x10000000, sec_reg),
		}
	end,
})
