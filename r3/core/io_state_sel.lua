local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r3.core.util")

return testbed.module({
	tag = "core.io_state_sel",
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
		{ name = "state"          , index =  1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000001 },
		{ name = "pc"             , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "flags"          , index =  5, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x1000000B },
		{ name = "curr_instr"     , index =  7, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x1000CAFE },
		{ name = "curr_imm"       , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x1000CAFE },
		{ name = "io_state"       , index = 11, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "next_state"     , index = 13, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "next_pc"        , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "next_flags"     , index = 17, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
		{ name = "next_curr_instr", index = 19, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "next_curr_imm"  , index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "next_ram_addr"  , index = 23, keepalive = 0x10000000, payload = 0x000FFFFF, initial = 0x10000000 },
		{ name = "next_wreg_addr" , index = 25, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
	},
	outputs = {
		{ name = "state"     , index =  1, keepalive = 0x10000000, payload = 0x0000000F },
		{ name = "pc"        , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "flags"     , index =  5, keepalive = 0x10000000, payload = 0x0000000F },
		{ name = "curr_instr", index =  7, keepalive = 0x10000000, payload = 0x0001FFFF },
		{ name = "curr_imm"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "ram_addr"  , index = 11, keepalive = 0x10000000, payload = 0x000FFFFF },
		{ name = "wreg_addr" , index = 13, keepalive = 0x10000000, payload = 0x0000001F },
	},
	func = function(inputs)
		local state, curr_instr, curr_imm, pc, flags, ram_addr, wreg_addr = spaghetti.select(
			inputs.io_state:band(1):zeroable(),
			inputs.state     , inputs.next_state,
			inputs.curr_instr, inputs.next_curr_instr,
			inputs.curr_imm  , inputs.next_curr_imm,
			inputs.pc        , inputs.next_pc,
			inputs.flags     , inputs.next_flags,
			0x10000000       , inputs.next_ram_addr,
			0x10000000       , inputs.next_wreg_addr
		)
		return {
			state      = state,
			curr_instr = curr_instr,
			curr_imm   = curr_imm,
			pc         = pc,
			flags      = flags,
			ram_addr   = ram_addr,
			wreg_addr  = wreg_addr,
		}
	end,
	fuzz_inputs = function()
		return {
			state           = bitx.bor(0x10000000, util.any_state()),
			pc              = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			flags           = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000F)),
			curr_instr      = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
			curr_imm        = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			io_state        = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000F)),
			next_state      = bitx.bor(0x10000000, util.any_state()),
			next_pc         = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			next_flags      = bitx.bor(0x10000000, math.random(0x00000000, 0x0000000F)),
			next_curr_instr = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
			next_curr_imm   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			next_ram_addr   = bitx.bor(0x10000000, math.random(0x00000000, 0x000FFFFF)),
			next_wreg_addr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000001F)),
		}
	end,
	fuzz_outputs = function(inputs)
		local keep_old = bitx.band(inputs.io_state, 1) ~= 0
		return {
			state      = keep_old and inputs.state      or inputs.next_state,
			curr_instr = keep_old and inputs.curr_instr or inputs.next_curr_instr,
			curr_imm   = keep_old and inputs.curr_imm   or inputs.next_curr_imm,
			pc         = keep_old and inputs.pc         or inputs.next_pc,
			flags      = keep_old and inputs.flags      or inputs.next_flags,
			ram_addr   = keep_old and 0x10000000        or inputs.next_ram_addr,
			wreg_addr  = keep_old and 0x10000000        or inputs.next_wreg_addr
		}
	end,
})
