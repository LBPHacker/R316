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
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 86,
	work_slots    = 32,
	-- TODO: maybe reset these voids with dray instead to save space for constants
	voids         = {    30, 31, 32,         59, 60, 61,                             75, 76, 77, 78         },
	clobbers      = { 1,             57, 58,             62, 63, 65, 68, 70, 73, 74,                 79, 81 },
	inputs = {
		{ name = "state"      , index = 10, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x1000000E },
		{ name = "imm_memcc"  , index = 12, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
		{ name = "pc"         , index = 14, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
		{ name = "flags"      , index = 16, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x1000000B },
		{ name = "sync_bit"   , index = 83, keepalive = 0x00010000, payload = 0x00C00001,                    initial = 0x00010001 },
		{ name = "io_state"   , index = 86, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x1000000F },
		{ name = "pri_reg"    , index = 64, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sec_reg"    , index = 80, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram"        , index = 69, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "instr_memcc", index = 35, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
	},
	outputs = {
		{ name = "state"      , index = 10, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "imm_memcc"  , index = 12, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "pc"         , index = 14, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "flags"      , index = 16, keepalive = 0x10000000, payload = 0x0000000B                    },
		{ name = "ram_addr"   , index = 86, keepalive = 0x10000000, payload = 0x0001FFFF                    },
		{ name = "ram_data"   , index = 73, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "wreg_addr"  , index = 62, keepalive = 0x10000000, payload = 0x0000001F                    },
		{ name = "wreg_data"  , index =  7, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "instr_memcc", index = 29, keepalive = 0x10000000, payload = 0x0000FFFF                    },
	},
	func = function(inputs)
		local pri_reg = inputs.pri_reg:bor(0x10000000):band(0x1000FFFF)
		local sec_reg = inputs.sec_reg:bor(0x10000000):band(0x1000FFFF)
		local ram = inputs.ram:bor(0x10000000):band(0x1000FFFF)
		local dummy = inputs.sync_bit
			:bor(pri_reg)
			:bor(sec_reg)
			:bor(ram)
			:bor(inputs.instr_memcc)
			:bor(inputs.imm_memcc)
			:bor(inputs.state)
			:bor(inputs.pc)
			:bor(inputs.flags)
			:bor(inputs.io_state)
			:band(0x10000000)
			-- (3FFFFFFE <<* (pc ^ 1FFFF)) ^ 3FFFFFFF ^ (pc ^ 1FFFF)
		local pc_inv = inputs.pc:bxor(0x0001FFFF)
		local pc_inc_mask = spaghetti.lshift(0x3FFFFFFE, pc_inv):bxor(0x3FFFFFFF)
		local pc_out = inputs.pc:bxor(pc_inc_mask):bsub(0x00010000)
		
		return {
			state       = dummy:bor(0x10000000):bxor(spaghetti.constant(0, 0x0000000F)),
			instr_memcc = dummy:bor(0x10000000):bxor(spaghetti.constant(0, 0x0000FFFF)),
			imm_memcc   = dummy:bor(0x10000000):bxor(spaghetti.constant(0, 0x0000FFFF)),
			ram_addr    = pc_out:bor(spaghetti.constant(0, 0x00010000)),
			ram_data    = pc_out:bxor(0xDEAD0000):force(0x00000000, 0xFFFFFFFF):never_zero(),
			wreg_addr   = dummy:bor(0x10000000):bxor(spaghetti.constant(0, 0x0000001F)),
			wreg_data   = inputs.ram,
			pc          = pc_out,
			flags       = dummy:bor(0x10000000):bxor(spaghetti.constant(0, 0x0000000B)),
		}
	end,
	fuzz_inputs = function()
		local sync_bit = math.random(0x0, 0x1)
		local pri_reg = testbed.any()
		local sec_reg = testbed.any()
		local ram = testbed.any()
		local instr_memcc = math.random(0x0, 0xFFFF)
		local imm_memcc = math.random(0x0, 0xFFFF)
		local pc = math.random(0x0, 0xFFFF)
		local flags = math.random(0x0, 0xB)
		local state = math.random(0x0, 0xF)
		return {
			pri_reg     = pri_reg,
			sec_reg     = sec_reg,
			ram         = ram,
			state       = bitx.bor(0x10000000, state),
			instr_memcc = bitx.bor(0x10000000, instr_memcc),
			imm_memcc   = bitx.bor(0x10000000, imm_memcc),
			pc          = bitx.bor(0x10000000, pc),
			flags       = bitx.bor(0x10000000, flags),
			sync_bit    = bitx.bor(0x00010000, sync_bit),
		}
	end,
	fuzz_outputs = function(inputs)
		return {
			state       = false,
			instr_memcc = false,
			imm_memcc   = false,
			ram_addr    = false,
			ram_data    = false,
			pc          = false,
			flags       = false,
			wreg_addr   = false,
			wreg_data   = false,
		}
	end,
})
