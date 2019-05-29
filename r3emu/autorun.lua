local instructions = {
	-- 0x28C1F000,
	-- 0x28D1F448,
	-- 0x28D1F449,
	-- 0x21000000,
	0x28C4F000,
	0x28D44B67,
	0x22C10001,
}

local counter = 0
for _, instr in ipairs(instructions) do
	mem.write(counter, instr)
	counter = counter + 1
end

local mapped = {
	r0 = 0x0700,
	r1 = 0x0701,
	r2 = 0x0702,
	r3 = 0x0703,
	r4 = 0x0704,
	r5 = 0x0705,
	r6 = 0x0706,
	r7 = 0x0707,
	pc = 0x0709,
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
