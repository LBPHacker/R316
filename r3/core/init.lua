local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("r3.testbed")
local adder     = require("r3.core.adder")
local bitwise   = require("r3.core.bitwise")
local condition = require("r3.core.condition")
local corestate = require("r3.core.corestate")
local mux       = require("r3.core.mux")
local shifter   = require("r3.core.shifter")

return testbed.module({
	opt_params = {
		thread_count  = 4,
		temp_initial  = 1,
		temp_final    = 0.95,
		temp_loss     = 1e-7,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 80,
	work_slots    = 30,
	voids         = { 30, 31, 32, 62, 63, 64, 78, 79, 80 }, -- TODO: try to reset these with dray instead to save space for constants
	inputs = {
		{ name = "pri_wild"    , index =  1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sec_wild"    , index =  3, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram_wild"    , index =  5, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "corestate"   , index =  7, keepalive = 0x10000000, payload = 0x00FFFFFF,                    initial = 0x10000000 },
		{ name = "sync_bit"    , index =  9, keepalive = 0x00010000, payload = 0x00000001,                    initial = 0x00010000 },
		-- { name = "fwinstr_wild", index =  9, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		-- { name = "cinstr_wild" , index = 11, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
	},
	outputs = {
		{ name = "dest"     , index =  1, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "dest_addr", index =  3, keepalive = 0x10000000, payload = 0x0000001F                    },
		{ name = "ram_addr" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "corestate", index =  7, keepalive = 0x10000000, payload = 0x00FFFFFF                    },
		{ name = "fwinstr"  , index =  9, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "cinstr"   , index = 11, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "mux"      , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF                    },
	},
	func = function(inputs)
		local pri     = inputs.pri_wild:bor(0x10000000):band(0x1000FFFF):assert(0x10000000, 0x0000FFFF)
		local sec_reg = inputs.sec_wild:bor(0x30000000):band(0x3000FFFF):assert(0x30000000, 0x0000FFFF)

		-- TODO: get from cinstr if corestate says read or write
		local instr_wild = inputs.ram_wild
		local instr_8 = spaghetti.rshiftk(instr_wild:bor(0x00001000):bsub(0x000000FF), 8):assert(0x00000010, 0x3FFFFFEF)
		local instr_16 = spaghetti.rshiftk(instr_8:bor(0x10000000):bsub(0x000000FF), 8):assert(0x00100000, 0x002FFFFF)

		local instr_high = instr_16:bor(0x10000000):band(0x1000FFFF)
		local instr_low = instr_wild:bor(0x10000000):band(0x1000FFFF)

		local imm = instr_low

		local mode_bit = spaghetti.rshiftk(instr_high, 15):bor(0x00000100):band(0x00000101):assert(0x00000100, 0x00000001)
		local mode_bit_mask = spaghetti.constant(0x3FFFFFFF):lshift(mode_bit):lshift(mode_bit)
		local wflags_bit = spaghetti.rshiftk(instr_high, 14):bor(0x00000100):band(0x00000101):assert(0x00000100, 0x00000001)
		local wflags_bit_mask = spaghetti.constant(0x3FFFFFFF):lshift(wflags_bit):lshift(wflags_bit)

		local sec = sec_reg:bxor(imm):band(mode_bit_mask):bxor(sec_reg):assert(0x10000000, 0x0000FFFF)

		local condition_outputs = condition.instantiate({
			corestate = inputs.corestate,
			op_bits   = instr_high:bor(0x10000000):band(0x100001F0),
			sync_bit  = inputs.sync_bit,
		})
		local corestate_outputs = corestate.instantiate({
			corestate = inputs.corestate,
			sec       = sec,
			op_bits   = instr_high:bor(0x10000000):band(0x1000000F),
			condition = condition_outputs.condition,
		})
		local shifter_outputs = shifter.instantiate({
			pri = pri,
			sec = sec,
		})
		local bitwise_outputs = bitwise.instantiate({
			pri = pri,
			sec = sec,
		})
		local op_subtract = instr_high:bor(0x10000000):band(0x10000002)
		local op_subtract_17 = spaghetti.rshiftk(op_subtract, 1):assert(0x08000000, 0x00000001)
		local op_carry = instr_high:bor(0x10000000):band(0x10000001):band(inputs.corestate)
		local op_carry_16 = op_carry:assert(0x10000000, 0x00000001)
		local adder_outputs = adder.instantiate({
			pri      = pri,
			sec      = sec,
			carry    = op_carry_16:bor(0x00200000):band(0x00200001),
			subtract = op_subtract_17:bor(0x00010000):band(0x00010001),
		})

		local pri_high_8 = spaghetti.rshiftk(inputs.pri_wild:bor(0x0000FFFF):band(0xFFFFFF00), 8):assert(0x000000FF, 0x3FFFFF00)
		local pri_high_16 = spaghetti.rshiftk(pri_high_8:bor(0x10000000), 8):assert(0x00100000, 0x002FFFFF)
		local l_exh = pri_high_16:bor(0x10000000):band(0x1000FFFF):assert(0x10000000, 0x0000FFFF)

		local mux_outputs = mux.instantiate({
			l_xor   = bitwise_outputs.l_xor,   -- TODO: output pri[31:16] as high half
			l_clr   = bitwise_outputs.l_clr,   -- TODO: output pri[31:16] as high half
			l_and   = bitwise_outputs.l_and,   -- TODO: output pri[31:16] as high half
			l_or    = bitwise_outputs.l_or,    -- TODO: output pri[31:16] as high half
			l_shl   = shifter_outputs.l_shl,   -- TODO: output pri[31:16] as high half
			l_shr   = shifter_outputs.l_shr,   -- TODO: output pri[31:16] as high half
			l_ld    = imm,                     -- TODO: output ram[31:16] as high half
			l_exh   = l_exh,                   -- TODO: output sec[15: 0] as high half
			l_mov   = sec,                     -- TODO: output pri[31:16] as high half
			l_jmp   = corestate_outputs.l_jmp,
			l_st    = sec,                     -- TODO: output pri[31:16] as high half, set dest to r0
			l_hlt   = sec,                     -- TODO: check if using a constant is better
			l_add   = adder_outputs.l_add,     -- TODO: output pri[31:16] as high half
			op_bits = instr_high:bor(0x10000000):band(0x1000000F),
		})
		local dest      = spaghetti.constant(0x00000000, 0xFFFFFFFF)
		local dest_addr = spaghetti.constant(0x10000000, 0x0000001F)
		local ram_addr  = spaghetti.constant(0x10000000, 0x0000FFFF)
		local corestate = corestate_outputs.corestate:bor(spaghetti.constant(0x10000000, 0x000F0000)) -- TODO
		local fwinstr   = spaghetti.constant(0x00000000, 0xFFFFFFFF)
		local cinstr    = spaghetti.constant(0x00000000, 0xFFFFFFFF)
		return {
			dest      = dest,
			dest_addr = dest_addr,
			ram_addr  = ram_addr,
			corestate = corestate,
			fwinstr   = fwinstr,
			cinstr    = cinstr,
			mux       = mux_outputs.muxed,
		}
	end,
	fuzz_inputs = function()
		local function any()
			local v = math.floor(math.random() * 0x100000000)
			return v == 0 and 0x1F or v
		end
		local sync_bit = math.random(0x0, 0x1)
		local pri_wild = any()
		local sec_wild = any()
		local ram_wild = any()
		local ew_instr = any()
		local valid_mem_states = { 0, 1, 2, 8 }
		local corestate = bitx.bor(
			            math.random(0x00000000, 0x0000FFFF)     ,
			bitx.lshift(math.random(0x00000000, 0x0000000B), 16),
			bitx.lshift(valid_mem_states[math.random(1, 4)], 20),
			bitx.lshift(math.random(0x00000000, 0x00000001), 22)
		)
		return {
			pri_wild  = pri_wild,
			sec_wild  = sec_wild,
			ram_wild  = ram_wild,
			ew_instr  = ew_instr,
			sync_bit  = sync_bit,
			corestate = bitx.bor(0x10000000, corestate),
		}
	end,
	fuzz_outputs = function(inputs)
		local instr = inputs.ram_wild
		if bitx.band(inputs.corestate, 0x00800000) ~= 0 then
			instr = inputs.ew_instr
		end
		
		-- local pri     = bitx.bor(0x10000000, bitx.band(pri_wild, 0x0000FFFF))
		-- local sec_reg = bitx.bor(0x10000000, bitx.band(sec_wild, 0x0000FFFF))
		-- local imm     = bitx.bor(0x10000000, bitx.band(ram_wild, 0x0000FFFF))
		-- local sec     = bitx.band(ram_wild, 0x80000000) ~= 0 and imm or sec_reg

		return {
			dest      = false,
			dest_addr = false,
			ram_addr  = false,
			corestate = false,
			fwinstr   = false,
			cinstr    = false,
			mux       = false,
		}
	end,
})
