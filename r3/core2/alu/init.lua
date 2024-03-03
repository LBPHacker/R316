local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local adder     = require("r3.core2.alu.adder")
local bitwise   = require("r3.core2.alu.bitwise")
local shifter   = require("r3.core2.alu.shifter")
local mux       = require("r3.core2.alu.mux")

return testbed.module({
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 40,
	work_slots    = 30,
	inputs = {
		{ name = "pri"     , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pri_high", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"     , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flags"   , index =  7, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x1000000B },
		{ name = "instr"   , index =  9, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
		{ name = "pc_incr" , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "res"     , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_high", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "flags"   , index = 5, keepalive = 0x10050000, payload = 0x0000000F },
	},
	func = function(inputs)
		local adder_outputs = adder.instantiate({
			pri   = inputs.pri,
			sec   = inputs.sec,
			flags = inputs.flags,
			instr = inputs.instr,
		})
		local bitwise_outputs = bitwise.instantiate({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		local shifter_outputs = shifter.instantiate({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		local mux_outputs = mux.instantiate({
			res_xor = bitwise_outputs.res_xor, -- TODO: res_high = inputs.pri_high
			res_clr = bitwise_outputs.res_clr, -- TODO: res_high = inputs.pri_high
			res_and = bitwise_outputs.res_and, -- TODO: res_high = inputs.pri_high
			res_or  = bitwise_outputs.res_or,  -- TODO: res_high = inputs.pri_high
			res_shl = shifter_outputs.res_shl, -- TODO: res_high = inputs.pri_high
			res_shr = shifter_outputs.res_shr, -- TODO: res_high = inputs.pri_high
			res_ld  = inputs.sec,              -- TODO: res_high = inputs.instr
			res_exh = inputs.pri,              -- TODO: res_high = inputs.sec
			res_mov = inputs.sec,              -- TODO: res_high = inputs.pri_high
			res_jmp = inputs.pc_incr,          -- TODO: res_high = 0
			res_st  = inputs.sec,              -- TODO: res_high = inputs.pri_high (and write_2 should probably use dest as both pri and sec)
			res_hlt = inputs.sec,              -- TODO: res_high = inputs.pri_high
			res_add = adder_outputs.res_add,   -- TODO: res_high = inputs.pri_high
			instr   = inputs.instr,            -- TODO: res_high = inputs.pri_high
		})
		local flags = mux_outputs.sign_zero:bor(adder_outputs.overflow_carry):assert(0x10050000, 0x0000000F)
		return {
			res      = mux_outputs.muxed,
			res_high = inputs.pri_high, -- TODO: see above
			flags    = flags,
		}
	end,
	fuzz_inputs = function()
		return {
			pri      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			pri_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			flags    = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
			pc_incr  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		-- local pri      = bitx.band(inputs.pri     , 0xFFFF)
		-- local sec      = bitx.band(inputs.sec     , 0xFFFF)
		-- local flags    = bitx.band(inputs.flags   , 0x000F)
		-- local instr    = bitx.band(inputs.instr   , 0xFFFF)
		-- local pc_incr  = bitx.band(inputs.pc_incr , 0xFFFF)
		local adder_outputs = adder.fuzz_outputs({
			pri   = inputs.pri,
			sec   = inputs.sec,
			flags = inputs.flags,
			instr = inputs.instr,
		})
		local bitwise_outputs = bitwise.fuzz_outputs({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		local shifter_outputs = shifter.fuzz_outputs({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		local mux_outputs = mux.fuzz_outputs({
			res_xor = bitwise_outputs.res_xor,
			res_clr = bitwise_outputs.res_clr,
			res_and = bitwise_outputs.res_and,
			res_or  = bitwise_outputs.res_or,
			res_shl = shifter_outputs.res_shl,
			res_shr = shifter_outputs.res_shr,
			res_ld  = inputs.sec,
			res_exh = inputs.pri,
			res_mov = inputs.sec,
			res_jmp = inputs.pc_incr,
			res_st  = inputs.sec,
			res_hlt = inputs.sec,
			res_add = adder_outputs.res_add,
			instr   = inputs.instr,
		})
		local flags_out = bitx.bor(mux_outputs.sign_zero, adder_outputs.overflow_carry)
		return {
			res      = mux_outputs.muxed,
			res_high = inputs.pri_high,
			flags    = flags_out,
		}
	end,
})
