local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti      = require("spaghetti")
local bitx           = require("spaghetti.bitx")
local testbed        = require("r3.testbed")
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
	opt_params = {
		thread_count  = 1, -- fast
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
		-- thread_count  = 8, -- good
		-- temp_initial  = 1,
		-- temp_final    = 0.8,
		-- temp_loss     = 1e-8,
		-- round_length  = 40000,
	},
	stacks        = 1,
	storage_slots = 86,
	work_slots    = 32,
	voids         = {                                                                    76, 77, 78         },
	clobbers      = { 1, 30, 31, 32, 57, 58, 59, 60, 61, 62, 63, 65, 68, 70, 73, 74, 75,             79, 81 },
	inputs = {
		{ name = "state"     , index = 10, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000001 },
		{ name = "pc"        , index = 14, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x10000000 },
		{ name = "flags"     , index = 16, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x1000000B },
		{ name = "ram_mask"  , index = 29, keepalive = 0x20000000, payload = 0x0000FFFF,                    initial = 0x20000000 },
		{ name = "curr_instr", index = 35, keepalive = 0x10000000, payload = 0x0001FFFF,                    initial = 0x1000CAFE },
		{ name = "curr_imm"  , index = 48, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
		{ name = "pri_reg"   , index = 64, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "ram"       , index = 69, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sec_reg"   , index = 80, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
		{ name = "sync_bit"  , index = 54, keepalive = 0x00010000, payload = 0x00000007,                    initial = 0x00010001 },
		{ name = "io_state"  , index = 86, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000000 },
	},
	outputs = {
		{ name = "wreg_data" , index =  7, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
		{ name = "state"     , index = 10, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "pc"        , index = 14, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "flags"     , index = 16, keepalive = 0x10000000, payload = 0x0000000F                    },
		{ name = "curr_instr", index = 29, keepalive = 0x10000000, payload = 0x0001FFFF                    },
		{ name = "curr_imm"  , index = 54, keepalive = 0x10000000, payload = 0x0000FFFF                    },
		{ name = "wreg_addr" , index = 62, keepalive = 0x10000000, payload = 0x0000001F                    },
		{ name = "ram_addr"  , index = 86, keepalive = 0x10000000, payload = 0x000FFFFF                    },
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
			sync_bit   = bitx.bor(0x00010000, math.random(0x0000, 0x0007)),
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
