fps.set(60)

do
	local mapped_read = {}
	local mapped_write = {}
	local function map(name, read, write)
		mapped_read[name] = read
		mapped_write[name] = write
	end
	local function mapreg(name, addr)
		map(name, function()
			return mem.read(addr)
		end, function(value)
			mem.write(addr, value)
		end)
	end

	mapreg("r0", 0x0700)
	mapreg("r1", 0x0701)
	mapreg("r2", 0x0702)
	mapreg("r3", 0x0703)
	mapreg("r4", 0x0704)
	mapreg("r5", 0x0705)
	mapreg("r6", 0x0706)
	mapreg("r7", 0x0707)
	mapreg("fl", 0x0708)
	mapreg("pc", 0x0709)
	mapreg("li", 0x070A)
	mapreg("lo", 0x070B)
	mapreg("lc", 0x070C)
	mapreg("lf", 0x070D)
	mapreg("lt", 0x070E)
	mapreg("wm", 0x070F)
	mapreg("mc", 0x0710)
	map("kbdin", keyboard.get_buffer, keyboard.set_buffer)

	setmetatable(_G, { __index = function(t, k)
		local read = mapped_read[k]
		if read then
			return read()
		end
	end, __newindex = function(t, k, v)
		local write = mapped_write[k]
		if write then
			write(v)
			return
		end
		rawset(t, k, v)
	end })

	autocomplete_additional_suggestions = {}
	for key in pairs(mapped_read) do
		table.insert(autocomplete_additional_suggestions, key)
	end
	-- TODO: get readline autocompletion to work with this
	-- https://thoughtbot.com/blog/tab-completion-in-gnu-readline
end

setmetatable(mem, { __index = function(t, k)
	if type(k) == "number" then
		return t.read(k)
	end
end, __newindex = function(t, k, v)
	if type(k) == "number" then
		t.write(k, v)
		return
	end
	rawset(t, k, v)
end })

print_old = print
print = setmetatable({ format = "0x%04X" }, { __call = function(t, ...)
	local stuff = { ... }
	for ix, thing in ipairs(stuff) do
		if type(thing) == "number" then
			stuff[ix] = t.format:format(thing)
		end
	end
	print_old(unpack(stuff))
end })

dis_follow_pc = true
function pre_draw()
	if dis_follow_pc then
		dis.show(pc - 7)
		dis.highlight(pc)
	end
end

local ok, err = pcall(function()
	local code = {}
	local func, err = loadfile("../../tptasm/src/tptasm.lua")
	if not func then
		error(err)
	end
	func({
		source = "../16to6.asm",
		target = code,
		log = io.stderr,
		model = "R3"
	})

	for ix = 0, #code do
		mem[ix] = code[ix].dwords[1]
	end
	
	local message = "Hi. I'm a relatively long message being decompressed on the fly from triplets of 16-bit cells holding eight 6-bit LUT indices each. Magically enough, I'm displayed one character per frame. Marvelous, isn't it?"

	local lut_at = #code + 1
	mem[lut_at] = 0x20000000
	local data_at = lut_at + 0x40
	local data_size = 0
	local lut = { [0] = 0 }
	local lut_size = 1
	local shift = 0
	local buffer = 0
	for character in (message .. ("\0"):rep(({ [0] = 1, 3, 2, 1, 3, 2, 1, 2 })[#message % 8])):gmatch(".") do
		local ch = character:byte()
		if not lut[ch] then
			if lut_size == 64 then
				error("LUT overflow")
			end
			lut[ch] = lut_size
			mem[lut_at + lut_size] = 0x20000000 + ch
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
	mem[data_at + data_size] = 0x20000000 + buffer
end)
if not ok then
	print(err)
end
