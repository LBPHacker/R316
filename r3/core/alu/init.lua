local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local adder     = require("r3.core.alu.adder")
local bitwise   = require("r3.core.alu.bitwise").instantiate()
local shifter   = require("r3.core.alu.shifter").instantiate()
local csmult    = require("r3.core.alu.csmult") .instantiate()
local mux       = require("r3.core.alu.mux")

return testbed.module(function(params)
	local adder_instance = adder.instantiate(params)
	local mux_instance   = mux.instantiate(params)

	return {
		tag = "core.alu",
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
			{ name = "pri"     , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pri_high", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "sec"     , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "ram_high", index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "ram_low" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "flags"   , index = 11, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x1000000B },
			{ name = "instr"   , index = 13, keepalive = 0x30000000, payload = 0x0001FFFF, initial = 0x30000000 },
			{ name = "pc_incr" , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "imm"     , index = 17, keepalive = 0x30000000, payload = 0x0000FFFF, initial = 0x30000000 },
		},
		outputs = {
			{ name = "res"     , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_high", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "flags"   , index = 5, keepalive = 0x10050000, payload = 0x0000000F },
			params.core_type == "m" and { name = "res_mull", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF } or nil,
		},
		func = function(inputs)
			local adder_pri = inputs.pri
			local adder_sec = inputs.sec
			local csmult_outputs
			if params.core_type == "m" then
				csmult_outputs = csmult.component({
					pri   = inputs.pri,
					sec   = inputs.sec,
					instr = inputs.instr,
				})
				adder_pri, adder_sec = spaghetti.select(
					inputs.instr:bxor(0xF):bsub(1):band(0xF):zeroable(),
					inputs.pri, csmult_outputs.carries,
					inputs.sec, csmult_outputs.sums_high
				)
			end
			local adder_outputs = adder_instance.component({
				pri   = adder_pri,
				sec   = adder_sec,
				flags = inputs.flags,
				instr = inputs.instr,
			})
			local bitwise_outputs = bitwise.component({
				pri = inputs.pri,
				sec = inputs.sec,
			})
			local shifter_outputs = shifter.component({
				pri = inputs.pri,
				sec = inputs.sec,
			})
			local res_mull, res_mulh
			if params.core_type == "m" then
				res_mull = csmult_outputs.sums_low:bor(spaghetti.lshiftk(adder_outputs.sum_27:bor(0x10000), 5)):band(0x1000FFFF)
				res_mulh = spaghetti.rshiftk(spaghetti.rshiftk(adder_outputs.sum_27, 9), 2):bor(0x10000000):band(0x1000FFFF)
			end
			local mux_outputs = mux_instance.component({
				res_xor  = bitwise_outputs.res_xor,
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
				imm      = inputs.imm,
				ram_high = inputs.ram_high,
				instr    = inputs.instr,
				flags    = params.core_type == "s" and inputs.flags or nil,
				res_mull = params.core_type == "m" and res_mull or nil,
				res_mulh = params.core_type == "m" and res_mulh or nil,
			})
			local flags = mux_outputs.sign_zero:bor(adder_outputs.overflow_carry)
			return {
				res      = mux_outputs.muxed,
				res_high = mux_outputs.muxed_high,
				flags    = flags,
				res_mull = params.core_type == "m" and res_mull or nil,
			}
		end,
		fuzz_inputs = function()
			return {
				pri      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				pri_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				sec      = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				ram_high = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				ram_low  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				flags    = bitx.bor(0x10000000, math.random(0x0, 0xB), bitx.lshift(math.random(0x0000, 0xFFFF), 4)),
				instr    = bitx.bor(0x30000000, math.random(0x00000000, 0x0001FFFF)),
				imm      = bitx.bor(0x30000000, math.random(0x00000000, 0x0000FFFF)),
				pc_incr  = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			}
		end,
		fuzz_outputs = function(inputs)
			local adder_pri = inputs.pri
			local adder_sec = inputs.sec
			local res_mull, res_mulh
			local flags_mask = 0xFFF0000F
			if params.core_type == "m" then
				local pri    = bitx.band(inputs.pri, 0xFFFF)
				local sec    = bitx.band(inputs.sec, 0xFFFF)
				local signed = bitx.band(inputs.instr, 0x8000) ~= 0
				local mixed  = bitx.band(inputs.instr, 0x0001) ~= 0
				if signed then
					if not mixed then
						if pri >= 0x8000 then
							pri = pri - 0x10000
						end
					end
					if sec >= 0x8000 then
						sec = sec - 0x10000
					end
				end
				local prod = pri * sec
				local high = bitx.band(bitx.rshift(prod, 5), 0x07FFFFFF)
				local high_carries = math.random(0, high)
				local sums_high = bitx.bor(0x10000000, high - high_carries)
				local carries = bitx.bor(0x10000000, high_carries)
				local sums_low = bitx.bor(0x10000000, bitx.band(prod, 0x001F))
				local ok, err = csmult.fuzz_outputs_implicit({
					pri   = inputs.pri,
					sec   = inputs.sec,
					instr = inputs.instr,
				}, {
					carries   = carries,
					sums_high = sums_high,
					sums_low  = sums_low,
				})
				if not ok then
					return nil, "csmult: " .. err
				end
				if bitx.band(inputs.instr, 0x000E) == 0x000E then
					flags_mask = 0xFFF00000
					adder_pri = carries
					adder_sec = sums_high
				end
				res_mull = bitx.bor(0x10000000, bitx.band(            prod     , 0xFFFF))
				res_mulh = bitx.bor(0x10000000, bitx.band(bitx.rshift(prod, 16), 0xFFFF))
			end
			local adder_outputs, err = adder_instance.fuzz_outputs({
				pri   = adder_pri,
				sec   = adder_sec,
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
			local mux_outputs, err = mux_instance.fuzz_outputs({
				res_xor  = bitwise_outputs.res_xor,
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
				imm      = inputs.imm,
				ram_high = inputs.ram_high,
				instr    = inputs.instr,
				flags    = inputs.flags,
				res_mull = params.core_type == "m" and res_mull or nil,
				res_mulh = params.core_type == "m" and res_mulh or nil,
			})
			if not mux_outputs then
				return nil, "mux: " .. err
			end
			local flags_out = bitx.bor(mux_outputs.sign_zero, adder_outputs.overflow_carry)
			return {
				res      = mux_outputs.muxed,
				res_high = mux_outputs.muxed_high,
				flags    = { value = bitx.bor(0x10050000, flags_out), mask = flags_mask },
				res_mull = params.core_type == "m" and bitx.band(inputs.instr, 0x000E) == 0x000E and res_mull or false,
			}
		end,
	}
end)
