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
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 12,
	inputs = {
		{ name = "ram_instr" , index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "ram_imm"   , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "curr_instr", index = 5, keepalive = 0x10000000, payload = 0x0001FFFF, initial = 0x10000000 },
		{ name = "curr_imm"  , index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "instr", index = 1, keepalive = 0x30000000, payload = 0x0001FFFF },
		{ name = "imm"  , index = 3, keepalive = 0x30000000, payload = 0x0000FFFF },
	},
	func = function(inputs)
		local use_curr = spaghetti.rshiftk(inputs.curr_instr, 16):bor(0x00010000):band(0x00010001)
		local sel_mask = spaghetti.constant(0x3FFFFFFF):lshift(use_curr):assert(0x3FFF0000, 0x0000FFFF)
		local sel_instr_diff = inputs.ram_instr:bxor(0x20000000):bxor(inputs.curr_instr):assert(0x20000000, 0x0001FFFF)
		local sel_imm_diff   = inputs.ram_imm  :bxor(0x20000000):bxor(inputs.curr_imm  ):assert(0x20000000, 0x0000FFFF)
		local sel_instr      = sel_instr_diff:band(sel_mask):bxor(inputs.ram_instr)     :assert(0x30000000, 0x0001FFFF)
		local sel_imm        = sel_imm_diff  :band(sel_mask):bxor(inputs.ram_imm  )     :assert(0x30000000, 0x0000FFFF)
		return {
			instr = sel_instr,
			imm   = sel_imm,
		}
	end,
	fuzz_inputs = function()
		return {
			ram_instr  = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			ram_imm    = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
			curr_instr = bitx.bor(0x10000000, math.random(0x00000000, 0x0001FFFF)),
			curr_imm   = bitx.bor(0x10000000, math.random(0x00000000, 0x0000FFFF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local use_curr = bitx.band(inputs.curr_instr, 0x10000) ~= 0
		return {
			instr = bitx.bor(0x20000000, use_curr and inputs.curr_instr or inputs.ram_instr),
			imm   = bitx.bor(0x20000000, use_curr and inputs.curr_imm   or inputs.ram_imm  ),
		}
	end,
})
