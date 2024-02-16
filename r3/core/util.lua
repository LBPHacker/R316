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

local function any_state_instr()
	local state, instr
	while true do
		state = any_state()
		instr = math.random(0x00000000, 0x0001FFFF)
		local op = bitx.band(instr, 0x000F)
		if not ((op == 2 or op == 10) and (state == 2 or state == 4)) then -- op is never ld or st in read_2 and write_2
			break
		end
	end
	return state, instr
end

local function any_sync_bit()
	return bitx.bor(bitx.lshift(math.random(0, 1), 3),
	                bitx.lshift(math.random(0, 1), 4),
	                            math.random(0, 1)    )
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
	op_is_not_k     = op_is_not_k,
	any_state       = any_state,
	any_state_instr = any_state_instr,
	any_sync_bit    = any_sync_bit,
}
