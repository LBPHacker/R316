local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx    = require("spaghetti.bitx")
local testbed = require("spaghetti.testbed")

local function build(ram_size)
	local image = {
		[ 0x0000 ] = 0x4600C0DE,
		[ 0x0001 ] = 0x060A00AD,
		[ 0x0002 ] = 0x0C0200AD,
		[ 0x0003 ] = 0x00000000,
		[ 0x0004 ] = 0x00000000,
		[ 0x0005 ] = 0x00000000,
		[ 0x0006 ] = 0x00000000,
		[ 0x0007 ] = 0x000B0000,
		[ 0x0008 ] = 0x00000000,
		[ 0x0009 ] = 0x00000000,
		[ 0x000A ] = 0x00000000,
		[ 0x000B ] = 0x00000000,
		[ 0x000C ] = 0x00000000,
		[ 0x000D ] = 0x00000000,
		[ 0x000E ] = 0x00000000,
		[ 0x000F ] = 0x00000000,
		[ 0x0010 ] = 0x00000000,
		[ 0x0011 ] = 0x00000000,
		[ 0x0012 ] = 0x00000000,
		[ 0x0013 ] = 0x00000000,
		[ 0x0014 ] = 0x00000000,
		[ 0x0015 ] = 0x00000000,
		[ 0x0016 ] = 0x00000000,
		[ 0x0017 ] = 0x00000000,
		[ 0x0018 ] = 0x00000000,
		[ 0x0019 ] = 0x00000000,
		[ 0x001A ] = 0x00000000,
		[ 0x001B ] = 0x00000000,
		[ 0x001C ] = 0x00000000,
		[ 0x001D ] = 0x00000000,
		[ 0x001E ] = 0x00000000,
		[ 0x001F ] = 0x00000000,
	}
	return image
end

return {
	build = build,
}
