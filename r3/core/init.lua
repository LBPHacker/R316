local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti      = require("spaghetti")
local bitx           = require("spaghetti.bitx")
local testbed        = require("spaghetti.testbed")
local alu            = require("r3.core.alu")
local condition      = require("r3.core.condition")     .instantiate()
local flags_sel      = require("r3.core.flags_sel")
local unstack_high   = require("r3.core.unstack_high")  .instantiate()
local stack_high     = require("r3.core.stack_high")    .instantiate()
local instr_sel      = require("r3.core.instr_sel")     .instantiate()
local pc_incr        = require("r3.core.pc_incr")       .instantiate()
local pc_sel         = require("r3.core.pc_sel")        .instantiate()
local sec_sel        = require("r3.core.sec_sel")       .instantiate()
local state_next     = require("r3.core.state_next")
local wreg_addr_sel  = require("r3.core.wreg_addr_sel") .instantiate()
local curr_instr_sel = require("r3.core.curr_instr_sel")
local ram_addr_sel   = require("r3.core.ram_addr_sel")  .instantiate()
local io_state_sel   = require("r3.core.io_state_sel")
local util           = require("r3.core.util")

return testbed.module(function(params)
	local alu_instance            = alu           .instantiate(params)
	local curr_instr_sel_instance = curr_instr_sel.instantiate(params)
	local flags_sel_instance      = flags_sel     .instantiate(params)
	local state_next_instance     = state_next    .instantiate(params)
	local io_state_sel_instance   = io_state_sel  .instantiate(params)

	local function flow(inputs, component)
		local unstack_high_pri_outputs = component("unstack_high_pri", unstack_high, {
			both_halves = inputs.pri_reg,
		})
		local unstack_high_sec_outputs = component("unstack_high_sec", unstack_high, {
			both_halves = inputs.sec_reg,
		})
		local unstack_high_ram_outputs = component("unstack_high_ram", unstack_high, {
			both_halves = inputs.ram,
		})
		local instr_sel_outputs = component("instr_sel", instr_sel, {
			state      = inputs.state,
			ram_instr  = unstack_high_ram_outputs.high_half,
			ram_imm    = unstack_high_ram_outputs.low_half,
			curr_instr = inputs.curr_instr,
			curr_imm   = inputs.curr_imm,
		})
		local condition_outputs = component("condition", condition, {
			flags    = inputs.flags,
			sync_bit = inputs.sync_bit,
			instr    = instr_sel_outputs.instr,
		})
		local pc_incr_outputs = component("pc_incr", pc_incr, {
			pc = inputs.pc,
		})
		local sec_sel_outputs = component("sec_sel", sec_sel, {
			instr   = instr_sel_outputs.instr,
			imm     = instr_sel_outputs.imm,
			sec_reg = unstack_high_sec_outputs.low_half,
		})
		local state_next_outputs = component("state_next", state_next_instance, {
			state    = inputs.state,
			instr    = instr_sel_outputs.instr,
			sync_bit = inputs.sync_bit,
		})
		local alu_outputs = component("alu", alu_instance, {
			pri      = unstack_high_pri_outputs.low_half,
			pri_high = unstack_high_pri_outputs.high_half,
			sec      = sec_sel_outputs.sec,
			imm      = instr_sel_outputs.imm,
			ram_high = unstack_high_ram_outputs.high_half,
			ram_low  = unstack_high_ram_outputs.low_half,
			flags    = inputs.flags,
			instr    = instr_sel_outputs.instr,
			pc_incr  = pc_incr_outputs.pc,
		})
		local pc_sel_outputs = component("pc_sel", pc_sel, {
			pc        = inputs.pc,
			pc_incr   = pc_incr_outputs.pc,
			pc_jump   = sec_sel_outputs.sec,
			state     = inputs.state,
			condition = condition_outputs.condition,
		})
		local flags_sel_outputs = component("flags_sel", flags_sel_instance, {
			instr     = instr_sel_outputs.instr,
			res_mull  = alu_outputs.res_mull,
			flags_new = alu_outputs.flags,
			flags_old = inputs.flags,
		})
		local wreg_addr_sel_outputs = component("wreg_addr_sel", wreg_addr_sel, {
			instr = instr_sel_outputs.instr,
		})
		local curr_instr_sel_outputs = component("curr_instr_sel", curr_instr_sel_instance, {
			ram_high = unstack_high_ram_outputs.high_half,
			ram_low  = unstack_high_ram_outputs.low_half,
			state    = inputs.state,
			imm      = instr_sel_outputs.imm,
			instr    = instr_sel_outputs.instr,
			st_addr  = alu_outputs.res,
		})
		local ram_addr_sel_outputs = component("ram_addr_sel", ram_addr_sel, {
			state    = inputs.state,
			instr    = instr_sel_outputs.instr,
			pc       = pc_sel_outputs.pc,
			ld_addr  = alu_outputs.res,
			st_addr  = inputs.curr_imm,
			ram_mask = inputs.ram_mask,
		})
		local stack_high_outputs = component("stack_high", stack_high, {
			high_half = alu_outputs.res_high,
			low_half  = alu_outputs.res,
		})
		local io_state_sel_outputs = component("io_state_sel", io_state_sel_instance, {
			io_state        = inputs.io_state,
			state           = inputs.state,
			instr           = instr_sel_outputs.instr,
			imm             = instr_sel_outputs.imm,
			curr_instr      = inputs.curr_instr,
			curr_imm        = inputs.curr_imm,
			ram_addr        = inputs.ram_addr,
			ram_data        = inputs.ram_data,
			pc              = inputs.pc,
			flags           = inputs.flags,
			next_state      = state_next_outputs.state,
			next_curr_instr = curr_instr_sel_outputs.curr_instr,
			next_curr_imm   = curr_instr_sel_outputs.curr_imm,
			next_pc         = pc_sel_outputs.pc,
			next_flags      = flags_sel_outputs.flags,
			next_ram_addr   = ram_addr_sel_outputs.ram_addr,
			next_ram_data   = inputs.pri_reg,
			next_wreg_addr  = wreg_addr_sel_outputs.wreg_addr,
		})
		return {
			state      = io_state_sel_outputs.state,
			curr_instr = io_state_sel_outputs.curr_instr,
			curr_imm   = io_state_sel_outputs.curr_imm,
			pc         = io_state_sel_outputs.pc,
			flags      = io_state_sel_outputs.flags,
			ram_addr   = io_state_sel_outputs.ram_addr,
			ram_data   = io_state_sel_outputs.ram_data,
			wreg_addr  = io_state_sel_outputs.wreg_addr,
			wreg_data  = stack_high_outputs.both_halves,
		}
	end

	local mcore_offset = 0
	local voids    = {                                                                    76, 77, 78         }
	local clobbers = { 1, 30, 31, 32, 57, 58, 59, 60, 61, 62, 63, 65, 69, 71, 73, 74, 75,             79, 81 }
	if params.core_type == "m" then
		mcore_offset = 2
		table.remove(clobbers, 1)
		for i = 1, #clobbers do
			clobbers[i] = clobbers[i] - mcore_offset
		end
		for i = 1, #voids do
			voids[i] = voids[i] - mcore_offset
		end
	end
	return {
		tag = "core",
		opt_params = {
			thread_count        = 8,
			round_length        = 10000,
			rounds_per_exchange = 10,
			seed                = { 0x12345678, 0x87654321 },
			schedule = {
				durations    = { 1000000, 2000000, 6000000,        },
				temperatures = {      10,       2,       1,    0.5 },
			},
		},
		stacks        = params.core_type == "m" and 3 or 2,
		storage_slots = params.core_type == "m" and 84 or 86,
		work_slots    = 31,
		voids         = voids,
		clobbers      = clobbers,
		inputs = {
			{ name = "state"     , index = 10 - mcore_offset, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000001 },
			{ name = "pc"        , index = 14 - mcore_offset, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x10000000 },
			{ name = "flags"     , index = 16 - mcore_offset, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x1000000B },
			{ name = "ram_mask"  , index = 29 - mcore_offset, keepalive = 0x20000000, payload = 0x0000FFFF,                    initial = 0x20000000 },
			{ name = "curr_instr", index = 35 - mcore_offset, keepalive = 0x10000000, payload = 0x0001FFFF,                    initial = 0x1000CAFE },
			{ name = "curr_imm"  , index = 48 - mcore_offset, keepalive = 0x10000000, payload = 0x0000FFFF,                    initial = 0x1000CAFE },
			{ name = "pri_reg"   , index = 64 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
			{ name = "ram_data"  , index = 68 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
			{ name = "ram"       , index = 70 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
			{ name = "sec_reg"   , index = 80 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true, initial = 0xDEADBEEF },
			{ name = "sync_bit"  , index = 54 - mcore_offset, keepalive = 0x00010000, payload = 0x00000019,                    initial = 0x00010001 },
			{ name = "io_state"  , index = 84 - mcore_offset, keepalive = 0x10000000, payload = 0x0000000F,                    initial = 0x10000000 },
			{ name = "ram_addr"  , index = 86 - mcore_offset, keepalive = 0x10000000, payload = 0x000FFFFF,                    initial = 0x10000000 },
		},
		outputs = {
			{ name = "wreg_data" , index =  7 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
			{ name = "state"     , index = 10 - mcore_offset, keepalive = 0x10000000, payload = 0x0000000F                    },
			{ name = "pc"        , index = 14 - mcore_offset, keepalive = 0x10000000, payload = 0x0000FFFF                    },
			{ name = "flags"     , index = 16 - mcore_offset, keepalive = 0x10000000, payload = 0x000FFFFF                    },
			{ name = "curr_instr", index = 29 - mcore_offset, keepalive = 0x10000000, payload = 0x0001FFFF                    },
			{ name = "curr_imm"  , index = 54 - mcore_offset, keepalive = 0x10000000, payload = 0x0000FFFF                    },
			{ name = "ram_data"  , index = 63 - mcore_offset, keepalive = 0x00000000, payload = 0xFFFFFFFF, never_zero = true },
			{ name = "wreg_addr" , index = 65 - mcore_offset, keepalive = 0x10000000, payload = 0x0000001F                    },
			{ name = "ram_addr"  , index = 86 - mcore_offset, keepalive = 0x10000000, payload = 0x000FFFFF                    },
		},
		func = function(inputs)
			return flow(inputs, function(name, mod, instance_inputs)
				return mod.component(instance_inputs)
			end)
		end,
		fuzz_inputs = function()
			return {
				pri_reg    = testbed.any(),
				sec_reg    = testbed.any(),
				ram        = testbed.any(),
				ram_data   = testbed.any(),
				ram_addr   = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
				io_state   = bitx.bor(0x10000000, math.random(0x0000, 0x000F)),
				state      = bitx.bor(0x10000000, util.any_state()),
				curr_instr = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
				curr_imm   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
				ram_mask   = bitx.bor(0x20000000, math.random(0x0000, 0xFFFF)),
				pc         = bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)),
				flags      = bitx.bor(0x10000000, math.random(0x0000, 0x000B)),
				sync_bit   = bitx.bor(0x00010000, util.any_sync_bit()),
			}
		end,
		fuzz_outputs = function(inputs)
			return flow(inputs, function(name, mod, instance_inputs)
				local outputs, err = mod.fuzz_outputs(instance_inputs)
				if not outputs then
					return nil, ("%s: %s"):format(name, err)
				end
				return outputs
			end)
		end,
	}
end)
