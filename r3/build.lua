local runner = require("spaghetti.runner")

local function run(modname, core_type, output_type, output_view, verb)
	output_type = output_type or "plot"
	output_type = output_type or "none"
	local generated = modname:gsub("%.", "/") .. "/generated"
	local module_params = {}
	if modname == "r3.comp.cpu.core" then
		generated = generated .. "_" .. core_type
		module_params.core_type = core_type
	end
	runner.run_internal({
		module = require(modname),
		module_params = module_params,
		output = (output_type == "plot") and (generated .. ".lua") or nil,
		vt100 = true,
		fuzz = verb == "fuzz",
		output_view = output_view,
		output_type = output_type,
		design_params = {
			probes = verb == "fuzz",
		},
	})
end

return {
	run = run,
}
