local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx    = require("spaghetti.bitx")
local testbed = require("r3.testbed")

local function build(ram_size)
	local image = {}
	image[0] = 0x0E2E0001
	return image
end

return {
	build = build,
}
