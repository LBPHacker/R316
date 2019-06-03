local mapped = {
	r0 = 0x0700,
	r1 = 0x0701,
	r2 = 0x0702,
	r3 = 0x0703,
	r4 = 0x0704,
	r5 = 0x0705,
	r6 = 0x0706,
	r7 = 0x0707,
	fl = 0x0708,
	pc = 0x0709,
	lr = 0x070A,
	lo = 0x070B,
	lc = 0x070C,
	lf = 0x070D,
	lt = 0x070E,
	wm = 0x070F,
}

setmetatable(_G, {__index = function(t, k)
	local addr = mapped[k]
	if addr then
		return mem.read(addr)
	end
end, __newindex = function(t, k, v)
	local addr = mapped[k]
	if addr then
		mem.write(addr, v)
		return
	end
	rawset(t, k, v)
end})

setmetatable(mem, {__index = function(t, k)
	if type(k) == "number" then
		return t.read(k)
	end
end, __newindex = function(t, k, v)
	if type(k) == "number" then
		t.write(k, v)
		return
	end
	rawset(t, k, v)
end
})

print_old = print
print = setmetatable({format = "0x%04X"}, {__call = function(t, ...)
	local stuff = {...}
	for ix, thing in ipairs(stuff) do
		if type(thing) == "number" then
			stuff[ix] = t.format:format(thing)
		end
	end
	print_old(unpack(stuff))
end})

dis_follow_pc = true
function pre_draw()
	if dis_follow_pc then
		dis.show(pc - 7)
		dis.highlight(pc)
	end
end

local ok, err = pcall(function()
	local instructions = {
		            --   start:
		0x20C70800, -- 0000: mov sp, 0x0800
		0x20C0006C, -- 0001: mov r0, 0x006C
		0x20C11C00, -- 0002: mov r1, 0x1C00
		0x23C10006, -- 0003: call print_16_to_6
		            --   .die:
		0x21000000, -- 0004: hlt
		0x22C10004, -- 0005: jmp .die
		            --   print_16_to_6:
		0x20DF002C, -- 0006: mov [--sp], .lut
		0x31BF88A0, -- 0007: ext [sp-1], [r0], 0xA0   ; extract #0
		0x31BE88A6, -- 0008: ext [sp-2], [r0], 0xA6   ; extract #1
		0x2C823F20, -- 0009: add r2, [sp-1], [sp]     ; index #0
		            --   .loop:
		0x2091110A, -- 000A: mov [r1++], [r2]         ; emit #0
		0x208F0F10, -- 000B: mov lo, [r0++]           ; shuffle #2
		0x34BF88A4, -- 000C: scl [sp-1], [r0], 0xA4   ; extract #2
		0x2C823E20, -- 000D: add r2, [sp-2], [sp]     ; index #1
		0x2091110A, -- 000E: mov [r1++], [r2]         ; emit #1
		0x20000000, -- 000F: nop
		0x31BD88A8, -- 0010: ext [sp-3], [r0], 0xA8   ; extract #4
		0x2C823F20, -- 0011: add r2, [sp-1], [sp]     ; index #2
		0x2091110A, -- 0012: mov [r1++], [r2]         ; emit #2
		0x31BE88A2, -- 0013: ext [sp-2], [r0], 0xA2   ; extract #3
		0x22C7002A, -- 0014: jz .done
		0x2C823E20, -- 0015: add r2, [sp-2], [sp]     ; index #3
		0x2091110A, -- 0016: mov [r1++], [r2]         ; emit #3
		0x208F0F10, -- 0017: mov lo, [r0++]           ; shuffle #5
		0x34BF88A2, -- 0018: scl [sp-1], [r0], 0xA2   ; extract #5
		0x2C823D20, -- 0019: add r2, [sp-3], [sp]     ; index #4
		0x2091110A, -- 001A: mov [r1++], [r2]         ; emit #4
		0x31BE88A4, -- 001B: ext [sp-2], [r0], 0xA4   ; extract #6
		0x22C7002A, -- 001C: jz .done
		0x2C823F20, -- 001D: add r2, [sp-1], [sp]     ; index #5
		0x2091110A, -- 001E: mov [r1++], [r2]         ; emit #5
		0x20000000, -- 001F: nop
		0x31BD90AA, -- 0020: ext [sp-3], [r0++], 0xAA ; extract #7
		0x2C823E20, -- 0021: add r2, [sp-2], [sp]     ; index #6
		0x2091110A, -- 0022: mov [r1++], [r2]         ; emit #6
		0x31BF88A0, -- 0023: ext [sp-1], [r0], 0xA0   ; extract #0
		0x22C7002A, -- 0024: jz .done
		0x2C823D20, -- 0025: add r2, [sp-3], [sp]     ; index #7
		0x2091110A, -- 0026: mov [r1++], [r2]         ; emit #7
		0x31BE88A6, -- 0027: ext [sp-2], [r0], 0xA6   ; extract #1
		0x2C823F20, -- 0028: add r2, [sp-1], [sp]     ; index #0
		0x22C1000A, -- 0029: jmp .loop
		            --   .done:
		0x2CC70001, -- 002A: add sp, 1
		0x2281470A, -- 002B: ret (aka jmp [0x070A])
		            --   .lut:
	}

	local counter = 0
	for _, instr in ipairs(instructions) do
		mem.write(counter, instr)
		counter = counter + 1
	end
	
	local message = "Hi. I'm a relatively long message being decompressed on the fly from triplets of 16-bit cells holding eight 6-bit LUT indices each. Magically enough, I'm displayed one character per frame. Marvelous, isn't it?"

	local lut_at = 0x2C
	local data_at = 0x6C
	local data_size = 0
	local lut = {[0] = 0}
	local lut_size = 1
	local shift = 0
	local buffer = 0
	for character in (message .. ("\0"):rep(({[0] = 1, 3, 2, 1, 3, 2, 1, 2})[#message % 8])):gmatch(".") do
		local ch = character:byte()
		if not lut[ch] then
			if lut_size == 64 then
				error("LUT overflow")
			end
			lut[ch] = lut_size
			mem[lut_at + lut_size] = 0x20000F00 + ch
			lut_size = lut_size + 1
		end
		buffer = buffer + lut[ch] * 2 ^ shift
		shift = shift + 6
		if shift >= 16 then
			shift = shift - 16
			mem[data_at + data_size] = 0x20000000 + bit.band(buffer, 0xFFFF)
			data_size = data_size + 1
			buffer = bit.rshift(buffer, 16)
		end
	end
	mem.write(data_at + data_size, 0x20000000 + buffer)
end)
if not ok then
	print(err)
end
