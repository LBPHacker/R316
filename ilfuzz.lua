local r3   = require("r3")
local plot = require("spaghetti.plot")

local pt = plot.pt

local bitx = setmetatable({}, { __index = function(tbl, key)
	local real_value = bit[key]
	local function value(...)
		return real_value(...) % 0x100000000
	end
	tbl[key] = value
	return value
end })

local cx, cy, addr_bits, core_count, space_available
local function detect()
	for id in sim.parts() do
		if sim.partProperty(id, "ctype") == 0x1864A205 and sim.partProperty(id, "type") == elem.DEFAULT_PT_QRTZ then
			local x, y = sim.partPosition(id)
			cx, cy = x, y
			local arr = {}
			while true do
				x = x + 1
				local value = sim.partProperty(sim.partID(x, y), "ctype")
				if value == 0 then
					break
				end
				table.insert(arr, string.char(value))
			end
			local str = table.concat(arr)
			addr_bits, core_count = assert(str:match("^R3A(.)(..)$"))
			addr_bits = string.byte(addr_bits) - 64
			core_count = tonumber(core_count)
			break
		end
	end
	assert(addr_bits)
	space_available = 2 ^ addr_bits
end

local function xpcall_wrap(func)
	return function()
		xpcall(function()
			func()
		end, function(err)
			print(err)
			print(debug.traceback())
		end)
	end
end

local function keyify(arr)
	local tbl = {}
	for _, item in ipairs(arr) do
		tbl[item] = true
	end
	return tbl
end

local function advance_state(state, sync_bit, io_state_in, io_data_in)
	local next_state = {
		memory    = {},
		registers = {},
	}
	for index = 0, space_available - 1 do
		next_state.memory[index] = state.memory[index]
	end
	for index = 1, 31 do
		next_state.registers[index] = state.registers[index]
	end
	local pc = bitx.band(state.pc, 0xFFFF)
	local next_pc = bitx.band(pc + 1, 0xFFFF)
	local memory_read = state.memory[bitx.band(state.mem_addr, space_available - 1)]
	if bitx.band(state.mem_addr, 0x10000) ~= 0 then
		memory_read = 0xFFFFFFFF
	end
	if bitx.band(io_state_in, 8) ~= 0 then
		memory_read = io_data_in
	end
	next_state.cinstr_high = bitx.rshift(memory_read, 16)
	next_state.cinstr_low = bitx.band(memory_read, 0xFFFF)
	local early_op = memory_read
	if bitx.band(state.cinstr_high, 0x10000) ~= 0 then
		early_op = bitx.bor(bitx.lshift(bitx.band(state.cinstr_high, 0xFFFF), 16), bitx.band(state.cinstr_low, 0xFFFF))
	end
	local prir = bitx.band(bitx.rshift(early_op, 20), 0x1F)
	local secr = bitx.band(            early_op     , 0x1F)
	local op = early_op
	if state.state == 0x10000008 then
		op = bitx.band(op, 0xFFFF)
	end
	local dest = bitx.band(bitx.rshift(op, 25), 0x1F)
	local pri   =           prir == 0 and 0x20000000 or state.registers[prir]
	local sec16 = bitx.band(secr == 0 and 0x20000000 or state.registers[secr], 0xFFFF)
	local imm = bitx.band(op, 0xFFFF)
	if bitx.band(op, 0x40000000) ~= 0 then
		sec16 = imm
	end
	local cinstr_mask = 0
	local bus_mode = 0x40000
	local pri16 = bitx.band(pri, 0xFFFF)
	local prihi = bitx.band(pri, 0xFFFF0000)
	local carry_in = bitx.band(state.flags, 1)
	if bitx.band(op, 0x00010000) == 0 then
		carry_in = 0
	end
	local sum, ssum
	local function to_signed(value)
		if value >= 0x8000 then
			value = value - 0x10000
		end
		return value
	end
	local ssec16 = to_signed(sec16)
	local spri16 = to_signed(pri16)
	if bitx.band(op, 0x00020000) == 0 then
		 sum =  sec16 - ( pri16 + carry_in)
		ssum = ssec16 - (spri16 + carry_in)
	else
		 sum =  sec16 + ( pri16 + carry_in)
		ssum = ssec16 + (spri16 + carry_in)
	end
	local carry_out    = ( sum <  0x0000 or  sum > 0xFFFF) and 1 or 0
	local overflow_out = (ssum < -0x8000 or ssum > 0x7FFF) and 2 or 0
	local res16
	if bitx.band(op, 0x000F0000) == 0x00000000 then
		res16 = sec16
	elseif bitx.band(op, 0x000F0000) == 0x00010000 then
		res16 = next_pc
		local take
		local carry    = bitx.band(state.flags, 1) ~= 0
		local overflow = bitx.band(state.flags, 2) ~= 0
		local zero     = bitx.band(state.flags, 4) ~= 0
		local sign     = bitx.band(state.flags, 8) ~= 0
		if bitx.band(prir, 7) == 7 then
			take = carry
		elseif bitx.band(prir, 7) == 6 then
			take = overflow
		elseif bitx.band(prir, 7) == 5 then
			take = zero
		elseif bitx.band(prir, 7) == 4 then
			take = sign
		elseif bitx.band(prir, 7) == 3 then
			take = (sign ~= overflow) or zero
		elseif bitx.band(prir, 7) == 2 then
			take = sign ~= overflow
		elseif bitx.band(prir, 7) == 1 then
			take = carry or zero
		elseif bitx.band(prir, 7) == 0 then
			take = true
		end
		if bitx.band(prir, 8) ~= 0 then
			take = not take
		end
		if bitx.band(prir, 0x10) == 0 then
			take = take and bitx.band(sync_bit, 1) ~= 0
		end
		if take then
			next_pc = sec16
		end
	elseif bitx.band(op, 0x000F0000) == 0x00020000 then
		res16 = bitx.band(sum, 0xFFFF)
		cinstr_mask = 0x10000
	elseif bitx.band(op, 0x000F0000) == 0x00030000 then
		res16 = bitx.rshift(prihi, 16)
		prihi = bitx.lshift(sec16, 16)
	elseif bitx.band(op, 0x000C0000) == 0x00040000 then
		res16 = bitx.band(sum, 0xFFFF)
	elseif bitx.band(op, 0x000F0000) == 0x00080000 then
		res16 = bitx.band(bitx.lshift(pri16, bitx.band(sec16, 0xF)), 0xFFFF)
	elseif bitx.band(op, 0x000F0000) == 0x00090000 then
		res16 = bitx.band(bitx.rshift(pri16, bitx.band(sec16, 0xF)), 0xFFFF)
	elseif bitx.band(op, 0x000F0000) == 0x000A0000 then
		res16 = bitx.band(sum, 0xFFFF)
		cinstr_mask = 0x10000
	elseif bitx.band(op, 0x000F0000) == 0x000B0000 then
		res16 = bitx.band(memory_read, 0xFFFF)
		prihi = bitx.rshift(memory_read, 0xFFFF0000)
	elseif bitx.band(op, 0x000F0000) == 0x000C0000 then
		res16 = bitx.band(pri16, sec16)
	elseif bitx.band(op, 0x000F0000) == 0x000D0000 then
		res16 = bitx.bor(pri16, sec16)
	elseif bitx.band(op, 0x000F0000) == 0x000E0000 then
		res16 = bitx.bxor(pri16, sec16)
	elseif bitx.band(op, 0x000F0000) == 0x000F0000 then
		res16 = bitx.band(bitx.bxor(0xFFFF, pri16), sec16)
	end
	local new_flags = carry_out + overflow_out
	if bitx.band(res16, 0x8000) ~= 0 then
		new_flags = new_flags + 8
	end
	if res16 == 0 then
		new_flags = new_flags + 4
	end
	local res = bitx.bor(prihi, res16)
	if bitx.band(res, 0x3FFFFFFF) == 0 then
		res = bitx.bxor(res, 0x20000000)
	end
	if state.state == 0x10000002 then
		next_state.pc = bitx.bor(0x10000000, pc)
		next_state.state = 0x10000001
		-- print(("0x10000002 %08X %08X"):format(state.mem_addr, memory_read))
		if dest ~= 0 then
			next_state.registers[dest] = memory_read
		end
		next_state.mem_addr = bitx.bor(0x10000000, pc)
	elseif state.state == 0x10000004 then
		-- print(("0x10000004 %08X %08X"):format(imm, pri))
		next_state.pc = bitx.bor(0x10000000, pc)
		next_state.state = 0x10000001
		cinstr_mask = 0x10000
		next_state.mem_addr = bitx.bor(0x10000000, imm)
		bus_mode = 0x10000
	elseif state.state == 0x10000008 then
		-- print("0x10000008")
		next_state.pc = bitx.bor(0x10000000, pc)
		next_state.state = state.state
		if bitx.band(sync_bit, 8) ~= 0 then
			next_state.state = 0x10000001
		end
		next_state.mem_addr = bitx.bor(0x10000000, pc)
	else
		-- print(("%04X %08X"):format(pc, op))
		next_state.state = state.state
		if bitx.band(op, 0x000F0000) == 0x00020000 then
			next_state.state = 0x10000002
			next_state.cinstr_high = bitx.bor(bitx.band(bitx.rshift(op, 16), 0xFFF0), 0x000B)
		elseif bitx.band(op, 0x000F0000) == 0x000A0000 then
			next_state.state = 0x10000004
			next_state.cinstr_high = bitx.lshift(dest, 4)
			next_state.cinstr_low = res16
		elseif bitx.band(op, 0x000F0000) == 0x000B0000 then
			next_state.state = 0x10000008
		end
		if dest ~= 0 and bitx.band(op, 0x000F0000) ~= 0x000A0000 then
			next_state.registers[dest] = res
		end
		next_state.pc = bitx.bor(0x10000000, next_pc)
		next_state.mem_addr = bitx.bor(0x10000000, next_pc)
		if bitx.band(op, 0x000F0000) == 0x00020000 then
			next_state.mem_addr = bitx.bor(0x10000000, res16)
		end
	end
	next_state.flags = state.flags
	if bitx.band(op, 0x80000000) ~= 0 then
		next_state.flags = bitx.bor(0x10000000, new_flags)
	end
	if bitx.band(next_state.mem_addr, bitx.bxor(space_available - 1, 0xFFFF)) ~= 0 then
		bus_mode = bitx.lshift(bus_mode, 1)
	end
	next_state.mem_addr = bitx.bor(next_state.mem_addr, bus_mode)
	next_state.mem_data = pri
	if bitx.band(next_state.mem_addr, 0x10000) ~= 0 then
		next_state.memory[bitx.band(next_state.mem_addr, space_available - 1)] = next_state.mem_data
	end
	next_state.cinstr_high = bitx.bor(0x10000000, cinstr_mask, next_state.cinstr_high)
	next_state.cinstr_low = bitx.bor(0x10000000, next_state.cinstr_low)
	if next_state.state == 0x10000001 and bitx.band(sync_bit, 0x10) ~= 0 then
		next_state.state = 0x10000008
	end
	if bitx.band(io_state_in, 1) ~= 0 then
		next_state.memory      = state.memory
		next_state.registers   = state.registers
		next_state.pc          = state.pc
		next_state.flags       = state.flags
		next_state.state       = state.state
		next_state.mem_addr    = 0x10000000
		next_state.cinstr_high = state.cinstr_high
		next_state.cinstr_low  = state.cinstr_low
	end
	return next_state
end

local function memory_id(index)
	local row_size = 128
	local row_count = space_available / row_size
	return sim.partID(cx + index % row_size - 41, cy + math.floor(index / row_size) - 13 - row_count - core_count * 6)
end

local function register_id(index)
	return sim.partID(cx - index * 2 - 3, cy - 1 - 6 * core_count)
end

local function pc_id()
	return sim.partID(cx + 15, cy - 6)
end

local function cinstr_high_id()
	return sim.partID(cx + 30, cy - 3)
end

local function cinstr_low_id()
	return sim.partID(cx + 55, cy - 3)
end

local function flags_id()
	return sim.partID(cx + 17, cy - 6)
end

local function wreg_data_id()
	return sim.partID(cx + 8, cy - 6)
end

local function wreg_addr_id()
	return sim.partID(cx + 63, cy - 6)
end

local function mem_data_id()
	return sim.partID(cx + 67, cy - 5 - 6 * core_count)
end

local function mem_addr_id()
	return sim.partID(cx + 87, cy - 6 - 6 * core_count)
end

local function state_id()
	return sim.partID(cx + 11, cy - 6)
end

local function io_addr_out_id(index)
	return sim.partID(cx + 95, cy - 12 - 6 * core_count + 6 * index)
end

local function io_data_out_id(index)
	return sim.partID(cx + 95, cy - 11 - 6 * core_count + 6 * index)
end

local function io_state_in_id(index)
	return sim.partID(cx + 100, cy - 10 - 6 * core_count + 6 * index)
end

local function io_data_in_id(index)
	return sim.partID(cx + 100, cy - 9 - 6 * core_count + 6 * index)
end

local function sim_value(id, value)
	if value then
		sim.partProperty(id, "ctype", value % 0x100000000)
		return
	end
	value = sim.partProperty(id, "ctype") % 0x100000000
	if bitx.band(value, 0x3FFFFFFF) == 0 then
		value = bitx.lshift(0x0000001F, math.random(0, 25))
	end
	return value
end

local function any32()
	local lo = math.random(0x0000, 0xFFFF)
	local hi = math.random(0x0000, 0xFFFF)
	return lo + hi * 0x10000
end

local function start(sync_bit)
	sim_value(sim.partID(cx + 55, cy - 6), sync_bit)
end

local function do_input()
	for i = 1, core_count do
		sim_value(io_state_in_id(i), bitx.bor(0x10000000, math.random(0x0, 0xF)))
		sim_value(io_data_in_id(i), any32())
		-- print(("do_input %i %08X %08X"):format(i, sim_value(io_state_in_id(i)), sim_value(io_data_in_id(i))))
	end
end

local function get_state()
	local memory = {}
	local registers = {}
	for index = 0, space_available - 1 do
		memory[index] = sim_value(memory_id(index))
	end
	for index = 1, 31 do
		registers[index] = sim_value(register_id(index))
	end
	local wreg_data = sim_value(wreg_data_id())
	local wreg_addr = bitx.band(sim_value(wreg_addr_id()), 0x1F)
	if wreg_addr ~= 0 then
		registers[wreg_addr] = wreg_data
	end
	local mem_data = sim_value(mem_data_id())
	local mem_addr = sim_value(mem_addr_id())
	if bitx.band(mem_addr, 0x10000) ~= 0 then
		-- print(("write2 %08X %08X"):format(mem_addr, mem_data))
		memory[bitx.band(mem_addr, space_available - 1)] = mem_data
	end
	return {
		memory      = memory,
		registers   = registers,
		pc          = sim_value(pc_id()),
		flags       = sim_value(flags_id()),
		state       = sim_value(state_id()),
		mem_data    = mem_data,
		mem_addr    = mem_addr,
		cinstr_high = sim_value(cinstr_high_id()),
		cinstr_low  = sim_value(cinstr_low_id()),
	}
end

local function compare_states(expected, actual)
	for key, value in pairs(expected.memory) do
		if actual.memory[key] ~= value then
			return nil, ("[%04X] expected to be %08X, actually %08X"):format(key, value, actual.memory[key])
		end
	end
	for key, value in pairs(expected.registers) do
		if actual.registers[key] ~= value then
			return nil, ("r%i expected to be %08X, actually %08X"):format(key, value, actual.registers[key])
		end
	end
	if actual.pc ~= expected.pc then
		return nil, ("pc expected to be %08X, actually %08X"):format(expected.pc, actual.pc)
	end
	if actual.flags ~= expected.flags then
		return nil, ("flags expected to be %08X, actually %08X"):format(expected.flags, actual.flags)
	end
	if actual.state ~= expected.state then
		return nil, ("state expected to be %08X, actually %08X"):format(expected.state, actual.state)
	end
	if actual.mem_data ~= expected.mem_data then
		return nil, ("mem_data expected to be %08X, actually %08X"):format(expected.mem_data, actual.mem_data)
	end
	if actual.mem_addr ~= expected.mem_addr then
		return nil, ("mem_addr expected to be %08X, actually %08X"):format(expected.mem_addr, actual.mem_addr)
	end
	if actual.cinstr_high ~= expected.cinstr_high then
		return nil, ("cinstr_high expected to be %08X, actually %08X"):format(expected.cinstr_high, actual.cinstr_high)
	end
	if actual.cinstr_low ~= expected.cinstr_low then
		return nil, ("cinstr_low expected to be %08X, actually %08X"):format(expected.cinstr_low, actual.cinstr_low)
	end
	return true
end

local key = "r3ilfuzz"
if rawget(_G, key) then
	_G[key].unregister()
end

local round_length = 0
local round_pos = 0
local tx, ty = 80, 220
local broken
local last_state, expect_io_addr_out, expect_io_data_out
local randomize = true
local spawn_delay = 0
local start_delay
local sync_bit = 0x10000
local aftersim = xpcall_wrap(function()
	if spawn_delay > 0 then
		spawn_delay = spawn_delay - 1
		return
	end
	if not space_available then
		return
	end
	local state = get_state()
	if last_state then
		local expected = last_state
		local ok = true
		local err
		for i = 1, core_count do
			local io_addr_out = sim_value(io_addr_out_id(i))
			if ok and expect_io_addr_out and io_addr_out ~= expect_io_addr_out then
				ok, err = nil, ("io_addr_out[%i] expected to be %08X, actually %08X"):format(i, expect_io_addr_out, io_addr_out)
			end
			local io_data_out = sim_value(io_data_out_id(i))
			if ok and expect_io_data_out and io_data_out ~= expect_io_data_out then
				ok, err = nil, ("io_data_out[%i] expected to be %08X, actually %08X"):format(i, expect_io_data_out, io_data_out)
			end
			local io_state_in = sim_value(io_state_in_id(i))
			local io_data_in = sim_value(io_data_in_id(i))
			local i_sync_bit = i == core_count and sync_bit or 0x10001
			expected = advance_state(expected, i_sync_bit, io_state_in, io_data_in)
			expect_io_addr_out = expected.mem_addr
			expect_io_data_out = expected.mem_data
		end
		sync_bit = 0x10000
		if math.random() < 0.001 then
			sync_bit = bitx.bor(sync_bit, 0x10)
		end
		start(sync_bit)
		if ok then
			ok, err = compare_states(expected, state)
		end
		if not ok then
			broken = err
			sim.paused(true)
		end
	end
	if not broken then
		if not start_delay and state.state == 0x10000008 then
			start_delay = math.random(1, 3)
		end
		if start_delay then
			start_delay = start_delay - 1
			if start_delay == 0 then
				start_delay = nil
				sync_bit = bitx.bor(sync_bit, 8)
				start(sync_bit)
			end
		end
		do_input()
	end
	last_state = state
	round_pos = round_pos + 1
	if round_pos > round_length then
		round_pos = 0
		randomize = true
		start_delay = nil
		sync_bit = 0x10000
	end
end)
local tick = xpcall_wrap(function()
	if broken then
		gfx.drawText(tx, ty, broken)
	else
		if randomize then
			last_state = nil
			expect_io_addr_out = nil
			expect_io_data_out = nil
			randomize = nil
			sim.clearSim()
			local x, y = 100, 100
			local core_count = 10
			local height_order = 4
			local io_probes = {}
			for i = 0, core_count - 1 do
				table.insert(io_probes, { type = pt.FILT, x = 136, y = i * 6 + 15 })
				table.insert(io_probes, { type = pt.FILT, x = 136, y = i * 6 + 16 })
				table.insert(io_probes, { type = pt.FILT, x = 136, y = i * 6 + 17 })
				table.insert(io_probes, { type = pt.FILT, x = 136, y = i * 6 + 18 })
				table.insert(io_probes, { type = pt.FILT, x = 137, y = i * 6 + 17 })
				table.insert(io_probes, { type = pt.FILT, x = 137, y = i * 6 + 18 })
				table.insert(io_probes, { type = pt.FILT, x = 138, y = i * 6 + 17 })
				table.insert(io_probes, { type = pt.FILT, x = 138, y = i * 6 + 18 })
				table.insert(io_probes, { type = pt.LDTC, x = 139, y = i * 6 + 17 })
				table.insert(io_probes, { type = pt.LDTC, x = 139, y = i * 6 + 18 })
				table.insert(io_probes, { type = pt.FILT, x = 141, y = i * 6 + 17, ctype = 0x10000000 })
				table.insert(io_probes, { type = pt.FILT, x = 141, y = i * 6 + 18, ctype = 0x10000000 })
			end
			plot.create_parts(x, y, plot.merge_parts(0, 0, r3.build(core_count, height_order), io_probes))
			detect()
			for index = 0, space_available - 1 do
				sim_value(memory_id(index), any32())
			end
			for index = 1, 31 do
				sim_value(register_id(index), any32())
			end
			start(0x10008)
			sim_value(pc_id(), bitx.bor(0x10000000, math.random(0x0000, 0xFFFF)))
			sim_value(flags_id(), bitx.bor(0x10000000, math.random(0x0, 0xB)))
			do_input()
			round_length = math.random(0x10, 0x100)
			spawn_delay = 1
		end
		gfx.drawText(tx, ty, "Fuzzing...")
	end
end)

event.register(event.AFTERSIM, aftersim)
event.register(event.TICK, tick)
local function unregister()
	event.unregister(event.AFTERSIM, aftersim)
	event.unregister(event.TICK, tick)
end
_G[key] = {
	unregister = unregister,
}

-- print("=========")
sim.paused(false)
