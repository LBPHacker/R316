local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")

local valid_states = {
	1, -- normal
	2, -- read_2
	4, -- write_2
	8, -- halt
}
local function any_state()
	return valid_states[math.random(#valid_states)]
end

local function any_sync_bit()
	return math.random(0x00000000, 0x00000007)
end

local function op_is_not_k(instr, k)
	instr:assert(0x30000000, 0x0001FFFF)
	local conjunctive
	for i = 0, 3 do
		local instr_bit = instr
		if bitx.band(k, 1) == 1 then
			instr_bit = instr_bit:bxor(1)
		end
		conjunctive = conjunctive and conjunctive:bor(instr_bit) or instr_bit
		k = bitx.rshift(k, 1)
		instr = spaghetti.rshiftk(instr, 1)
	end
	return conjunctive:bsub(0xFFFE):assert(0x3E000000, 0x00010001)
end

return {
	op_is_not_k  = op_is_not_k,
	any_state    = any_state,
	any_sync_bit = any_sync_bit,
}
