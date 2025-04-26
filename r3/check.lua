local bitx  = require("spaghetti.bitx")
local check = require("spaghetti.check")
local misc  = require("spaghetti.misc")

local function lowhigh(name, value_parent, low, high)
	local specified = 0
	if value_parent[low] ~= nil then
		check.integer(name .. "." .. low, value_parent[low])
		specified = specified + 1
	end
	if value_parent[high] ~= nil then
		check.integer(name .. "." .. high, value_parent[high])
		specified = specified + 1
	end
	if specified ~= 1 then
		misc.user_error("exactly one of %s or %s should be specified", name .. "." .. low, name .. "." .. high)
	end
	if value_parent[low] ~= nil then
		return { which = low, value = value_parent[low] }
	end
	return { which = high, value = value_parent[high] }
end


local function base_address(name, value, mask)
	check.integer_range(name, value, 0x0000, 0xFFFF)
	if bitx.band(value, mask) ~= value then
		misc.user_error("%s must not have bits set outside %04X", name, mask)
	end
end

return {
	lowhigh      = lowhigh,
	base_address = base_address,
}
