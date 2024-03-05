local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx    = require("spaghetti.bitx")
local testbed = require("r3.testbed")

local function build(ram_size)
	local image = {}
	for i = 0, ram_size - 1 do
		image[i] = bitx.band(testbed.any(), 0xFFF0FFFF)
	end
	return image
end

return {
	build = build,
}
