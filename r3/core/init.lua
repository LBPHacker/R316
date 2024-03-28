local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti      = require("spaghetti")
local bitx           = require("spaghetti.bitx")
local testbed        = require("spaghetti.testbed")
local alu            = require("r3.core.alu")
local condition      = require("r3.core.condition")
local flags_sel      = require("r3.core.flags_sel")
local unstack_high   = require("r3.core.unstack_high")
local stack_high     = require("r3.core.stack_high")
local instr_sel      = require("r3.core.instr_sel")
local pc_incr        = require("r3.core.pc_incr")
local pc_sel         = require("r3.core.pc_sel")
local sec_sel        = require("r3.core.sec_sel")
local state_next     = require("r3.core.state_next")
local wreg_addr_sel  = require("r3.core.wreg_addr_sel")
local curr_instr_sel = require("r3.core.curr_instr_sel")
local ram_addr_sel   = require("r3.core.ram_addr_sel")
local util           = require("r3.core.util")

return testbed.module({
	tag = "core",
	opt_params = {
		thread_count        = 8,
		round_length        = 10000,
		rounds_per_exchange = 10,
		seed                = { 0xDEADBEEF, 0xCAFEBABE },
		schedule = {
			durations    = { 1000000, 2000000, 6000000,        },
			temperatures = {      10,       2,       1,    0.5 },
		},
	},
	stacks           = 1,
	voids            = { 78, 79, 80 },
	clobbered        = { 3, 32, 33, 34, 59, 60, 61, 62, 63, 64, 65, 67, 70, 72, 75, 76, 77, 81, 83 },
	unclobbered      = {   4,   5,   6,   7,   8,   9,  10,  11,       13,
	                      14,  15,       17,
	                           35,  36,       38,  39,  40,  41,  42,  43,
	                      44,  45,  46,  47,  48,  49,       51,  52,  53,
	                      54,  55,       57,  58,
	                                          68,  69,                 73,
	                      74,
	                      84,  85,  86,  87,
	                      -3,  -4,  -5,  -6,  -7,  -8,  -9, -10, -11, -12,
	                     -13, -14 },
	compute_operands = {  19,  21,  23,  25,  27,  29, -15, -17, -19, -21, -23, -25, -27, -29, -31, -33, -35, -37, -39, -41, -43, -45, -47, -49, -51, -53, -55, -57, -59, -61, -63, -65 },
	compute_results  = {  20,  22,  24,  26,  28,  30, -16, -18, -20, -22, -24, -26, -28, -30, -32, -34, -36, -38, -40, -42, -44, -46, -48, -50, -52, -54, -56, -58, -60, -62, -64, -66 },
	inputs = {
		{ name = "state"     , index = 12, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000001 },
		{ name = "pc"        , index = 16, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x10000000 },
		{ name = "flags"     , index = 18, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x1000000B },
		{ name = "ram_mask"  , index = 31, keepalive = 0x20000000, payload = 0x0000FFFF,                    initial = 0x20000000 },
		{ name = "curr_instr", index = 37, keepalive = 0x10000000, payload = 0x0001FFFF,                    initial = 0x1000CAFE },
		{ name = "curr_imm"  , index = 50, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
		{ name = "pri_reg"   , index = 66, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram"       , index = 71, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sec_reg"   , index = 82, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sync_bit"  , index = 56, keepalive = 0x00010000, payload = 0x00000019,                    initial = 0x00010001 },
		{ name = "io_state"  , index = 88, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000000 },
	},
	outputs = {
		{ name = "wreg_data" , index =  9, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "state"     , index = 12, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "pc"        , index = 16, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "flags"     , index = 18, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "curr_instr", index = 31, keepalive = 0x10000000, payload = 0x0001FFFF                    },
		{ name = "curr_imm"  , index = 56, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "wreg_addr" , index = 64, keepalive = 0x10000000, payload = 0x0000001F                    },
		{ name = "ram_addr"  , index = 88, keepalive = 0x10000000, payload = 0x000FFFFF                    },
	},
	func = function(inputs)
		local unstack_high_pri_outputs = unstack_high.instantiate({
			both_halves = inputs.pri_reg,
		})
		local unstack_high_sec_outputs = unstack_high.instantiate({
			both_halves = inputs.sec_reg,
		})
		local unstack_high_ram_outputs = unstack_high.instantiate({
			both_halves = inputs.ram,
		})
		local instr_sel_outputs = instr_sel.instantiate({
			state      = inputs.state,
			ram_instr  = unstack_high_ram_outputs.high_half,
			ram_imm    = unstack_high_ram_outputs.low_half,
			curr_instr = inputs.curr_instr,
			curr_imm   = inputs.curr_imm,
		})
		local condition_outputs = condition.instantiate({
			flags    = inputs.flags,
			sync_bit = inputs.sync_bit,
			instr    = instr_sel_outputs.instr,
		})
		local pc_incr_outputs = pc_incr.instantiate({
			pc = inputs.pc,
		})
		local sec_sel_outputs = sec_sel.instantiate({
			instr   = instr_sel_outputs.instr,
			imm     = instr_sel_outputs.imm,
			sec_reg = unstack_high_sec_outputs.low_half,
		})
		local state_next_outputs = state_next.instantiate({
			state    = inputs.state,
			instr    = instr_sel_outputs.instr,
			sync_bit = inputs.sync_bit,
		})
		local alu_outputs = alu.instantiate({
			pri      = unstack_high_pri_outputs.low_half,
			pri_high = unstack_high_pri_outputs.high_half,
			sec      = sec_sel_outputs.sec,
			ram_high = unstack_high_ram_outputs.high_half,
			ram_low  = unstack_high_ram_outputs.low_half,
			flags    = inputs.flags,
			instr    = instr_sel_outputs.instr,
			pc_incr  = pc_incr_outputs.pc,
		})
		local pc_sel_outputs = pc_sel.instantiate({
			pc        = inputs.pc,
			pc_incr   = pc_incr_outputs.pc,
			pc_jump   = alu_outputs.res,
			state     = inputs.state,
			condition = condition_outputs.condition,
		})
		local flags_sel_outputs = flags_sel.instantiate({
			instr     = instr_sel_outputs.instr,
			flags_new = alu_outputs.flags,
			flags_old = inputs.flags,
		})
		local wreg_addr_sel_outputs = wreg_addr_sel.instantiate({
			instr = instr_sel_outputs.instr,
		})
		local curr_instr_sel_outputs = curr_instr_sel.instantiate({
			ram_high = unstack_high_ram_outputs.high_half,
			ram_low  = unstack_high_ram_outputs.low_half,
			state    = inputs.state,
			instr    = instr_sel_outputs.instr,
			st_addr  = alu_outputs.res,
		})
		local ram_addr_sel_outputs = ram_addr_sel.instantiate({
			state    = inputs.state,
			instr    = instr_sel_outputs.instr,
			pc       = pc_sel_outputs.pc,
			ld_addr  = alu_outputs.res,
			st_addr  = inputs.curr_imm,
			ram_mask = inputs.ram_mask,
		})
		local stack_high_outputs = stack_high.instantiate({
			high_half = alu_outputs.res_high,
			low_half  = alu_outputs.res,
		})
		local state, curr_instr, curr_imm, pc, flags, ram_addr, wreg_addr = spaghetti.select(
			inputs.io_state:band(1):zeroable(),
			inputs.state     , state_next_outputs.state,
			inputs.curr_instr, curr_instr_sel_outputs.curr_instr,
			inputs.curr_imm  , curr_instr_sel_outputs.curr_imm,
			inputs.pc        , pc_sel_outputs.pc,
			inputs.flags     , flags_sel_outputs.flags,
			0x10000000       , ram_addr_sel_outputs.ram_addr,
			0x10000000       , wreg_addr_sel_outputs.wreg_addr
		)
		return {
			state      = state,
			curr_instr = curr_instr,
			curr_imm   = curr_imm,
			pc         = pc,
			flags      = flags,
			ram_addr   = ram_addr,
			wreg_addr  = wreg_addr,
			wreg_data  = stack_high_outputs.both_halves,
		}
	end,
	fuzz_inputs = function()
		return {
			pri_reg    = testbed.any(),
			sec_reg    = testbed.any(),
			ram        = testbed.any(),
			io_state   = bitx.bor(0x10000000, math.random(0x0000, 0x000F)),
			state      = bitx.bor(0x10000000, util.any_state()),
			curr_instr = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
			curr_imm   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			pc         = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
			flags      = bitx.bor(0x10000000, math.random(0x0000, 0x000B)),
			sync_bit   = bitx.bor(0x10000000, util.any_sync_bit()),
		}
	end,
	fuzz_outputs = function(inputs)
		return {
			state      = false,
			curr_instr = false,
			curr_imm   = false,
			pc         = false,
			flags      = false,
			ram_addr   = false,
			wreg_addr  = false,
			wreg_data  = false,
		}
	end,
})
