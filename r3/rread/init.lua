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
	storage_slots = 15,
	work_slots    = 10,
	inputs = {
		{ name = "ram_wild",  index = 1, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x1000DEAD, never_zero = true },
		{ name = "corestate", index = 3, keepalive = 0x10000000, payload = 0x007FFFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "pri_reg", index = 1, keepalive = 0x10000000, payload = 0x0000001F },
		{ name = "sec_reg", index = 3, keepalive = 0x10000000, payload = 0x0000001F },
	},
	func = function(inputs)
		local pri_offset = spaghetti.rshiftk(inputs.corestate, 17):bxor(0x00000010):bor(0x00000200):band(0x00000210)
		local ram = inputs.ram_wild:bor(0x10000000)
		local ram_high = spaghetti.rshiftk(inputs.ram_wild:bor(0x00010000):bsub(0x0000FFFF), 16):assert(0x00000001, 0x3FFFFFFE)
		local pri_reg = ram_high:bor(0x10000000):rshift(pri_offset):never_zero():bor(0x10000000):band(0x1000001F)
		local sec_reg = ram:bor(0x10000000):band(0x1000001F)
		return {
			pri_reg = pri_reg,
			sec_reg = sec_reg,
		}
	end,
	fuzz = function()
		local function any()
			local v = math.floor(math.random() * 0x100000000)
			return v == 0 and 0x1F or v
		end
		local ram_wild = any()
		local corestate =
			math.random(0x00000000, 0x0000FFFF) +
			math.random(0x00000000, 0x0000000B) * 0x10000 +
			math.random(0x00000000, 0x00000007) * 0x100000
		local pri_reg_offset = 20
		if bitx.band(corestate, 0x200000) ~= 0 then
			pri_reg_offset = 25
		end
		local pri_reg = bitx.band(bitx.rshift(ram_wild, pri_reg_offset), 0x1F)
		local sec_reg = bitx.band(ram_wild, 0x1F)
		return {
			inputs = {
				ram_wild  = ram_wild,
				corestate = bitx.bor(0x10000000, corestate),
			},
			outputs = {
				pri_reg = bitx.bor(0x10000000, pri_reg),
				sec_reg = bitx.bor(0x10000000, sec_reg),
			},
		}
	end,
})
