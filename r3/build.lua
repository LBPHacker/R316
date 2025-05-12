local runner = require("spaghetti.runner")

local function run(modname_with_params, output_type, output_view, verb, output_file)
	output_type = output_type or "plot"
	output_view = output_view or "none"
	verb        = verb or "build"
	local modname
	local module_params = {}
	for param_str in modname_with_params:gmatch("[^ ]+") do
		if modname then
			local key, value = param_str:match("^([^=]+)=(.*)$")
			if not key then
				key = param_str
				value = true
			end
			module_params[key] = value
		else
			modname = param_str
		end
	end
	runner.run_internal({
		module        = require(modname),
		module_params = module_params,
		output        = output_file,
		vt100         = true,
		fuzz          = verb == "fuzz",
		output_view   = output_view,
		output_type   = output_type,
		design_params = {
			probes = verb == "fuzz",
		},
	})
end

return {
	run = run,
}
