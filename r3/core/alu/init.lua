local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local adder     = require("r3.core.alu.adder")
local bitwise   = require("r3.core.alu.bitwise")
local shifter   = require("r3.core.alu.shifter")
local mux       = require("r3.core.alu.mux")

return testbed.module({
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 50,
	work_slots    = 30,
	inputs = {
		{ name = "pri"     , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pri_high", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "sec"     , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_high", index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_low" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flags"   , index = 11, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x1000000B },
		{ name = "instr"   , index = 13, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
		{ name = "pc_incr" , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
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
			res_xor  = bitwise_outputs.res_xor,
			res_clr  = bitwise_outputs.res_clr,
			res_and  = bitwise_outputs.res_and,
			res_or   = bitwise_outputs.res_or,
			res_shl  = shifter_outputs.res_shl,
			res_shr  = shifter_outputs.res_shr,
			res_mov  = inputs.sec,
			res_ld   = adder_outputs.res_add,
			res_st   = adder_outputs.res_add,
			res_add  = adder_outputs.res_add,
			res_jmp  = inputs.pc_incr,
			res_exh  = inputs.pri_high,
			res_hlt  = inputs.ram_low,
			pri_high = inputs.pri_high,
			sec      = inputs.sec,
			ram_high = inputs.ram_high,
			instr    = inputs.instr,
		})
		local flags = mux_outputs.sign_zero:bor(adder_outputs.overflow_carry):assert(0x10050000, 0x0000000F)
		return {
			res      = mux_outputs.muxed,
			res_high = mux_outputs.muxed_high,
			flags    = flags,
		}
	end,
	fuzz_inputs = function()
		return {
			pri      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			pri_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			sec      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			ram_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			ram_low  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			flags    = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000B)),
			instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
			pc_incr  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local adder_outputs, err = adder.fuzz_outputs({
			pri   = inputs.pri,
			sec   = inputs.sec,
			flags = inputs.flags,
			instr = inputs.instr,
		})
		if not adder_outputs then
			return nil, "adder: " .. err
		end
		local bitwise_outputs, err = bitwise.fuzz_outputs({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		if not bitwise_outputs then
			return nil, "bitwise: " .. err
		end
		local shifter_outputs, err = shifter.fuzz_outputs({
			pri = inputs.pri,
			sec = inputs.sec,
		})
		if not shifter_outputs then
			return nil, "shifter: " .. err
		end
		local mux_outputs, err = mux.fuzz_outputs({
			res_xor  = bitwise_outputs.res_xor,
			res_clr  = bitwise_outputs.res_clr,
			res_and  = bitwise_outputs.res_and,
			res_or   = bitwise_outputs.res_or,
			res_shl  = shifter_outputs.res_shl,
			res_shr  = shifter_outputs.res_shr,
			res_mov  = inputs.sec,
			res_ld   = adder_outputs.res_add,
			res_st   = adder_outputs.res_add,
			res_add  = adder_outputs.res_add,
			res_exh  = inputs.pri_high,
			res_jmp  = inputs.pc_incr,
			res_hlt  = inputs.ram_low,
			pri_high = inputs.pri_high,
			sec      = inputs.sec,
			ram_high = inputs.ram_high,
			instr    = inputs.instr,
		})
		if not mux_outputs then
			return nil, "mux: " .. err
		end
		local flags_out = bitx.bor(mux_outputs.sign_zero, adder_outputs.overflow_carry)
		return {
			res      = mux_outputs.muxed,
			res_high = mux_outputs.muxed_high,
			flags    = flags_out,
		}
	end,
})
