local bitx          = require("spaghetti.bitx")
local misc          = require("spaghetti.misc")
local check         = require("spaghetti.check")
local r3_check      = require("r3.check")
local inst_breakout = require("r3.comp.inst_breakout")

local function build(params, params_name)
	r3_check.base_address(params_name .. ".base_address", params.base_address, 0xFFFF)
	local normally_low = 0
	if params.normally_low ~= nil then
		normally_low = params.normally_low
		check.integer(params_name .. ".normally_low", params.normally_low)
	end
	local normally_high = 0
	if params.normally_high ~= nil then
		normally_high = params.normally_high
		check.integer(params_name .. ".normally_high", params.normally_high)
	end
	if bitx.band(normally_low, normally_high) ~= 0 then
		misc.user_error("%s and %s must not share bits", params_name .. ".normally_low", params_name .. ".normally_high")
	end
	check.one_of(params_name .. ".facing", params.facing, { "top", "bottom" })
	local derived_params = {
		normally_low  = normally_low,
		normally_high = normally_high,
	}
	return inst_breakout.build_inst_filt(false, params, params_name, derived_params)
end

return {
	build       = build,
	param_types = inst_breakout.param_types,
}
