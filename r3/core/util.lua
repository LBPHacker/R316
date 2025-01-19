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

local function op_is_bits(instr, k, mask)
	assert(bitx.band(mask, 0x800F) == mask)
	instr:assert(0x30000000, 0x0001FFFF)
	local bits = {}
	local last_index = 0
	local function next_bit(index)
		local shift_by = index - last_index
		if shift_by > 0 then
			k = bitx.rshift(k, shift_by)
			instr = spaghetti.rshiftk(instr, shift_by)
		end
		if bitx.band(mask, bitx.lshift(1, index)) ~= 0 then
			local instr_bit = instr
			if bitx.band(k, 1) == 1 then
				instr_bit = instr_bit:bxor(1)
			end
			table.insert(bits, instr_bit)
		end
		last_index = index
	end
	next_bit(0)
	next_bit(1)
	next_bit(2)
	next_bit(3)
	next_bit(15)
	return bits
end

local function op_is_not_k(instr, k, mask)
	local conjunctive
	for _, instr_bit in ipairs(op_is_bits(instr, k, mask)) do
		conjunctive = conjunctive and conjunctive:bor(instr_bit) or instr_bit
	end
	return conjunctive:bsub(0xFFFE)
end

return {
	op_is_not_k     = op_is_not_k,
	op_is_bits      = op_is_bits,
	any_state       = any_state,
	any_state_instr = any_state_instr,
	any_sync_bit    = any_sync_bit,
}
