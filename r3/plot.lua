local plot            = require("spaghetti.plot")
local check           = require("spaghetti.check")
local misc            = require("spaghetti.misc")
local bus_termination = require("r3.comp.bus_termination")
local r3_check        = require("r3.check")

local pt = plot.pt
local audited_pairs = pairs

local components = {
	cpu           = require("r3.comp.cpu"),
	terminal      = require("r3.comp.terminal"),
	r2_adapter    = require("r3.comp.r2_adapter"),
	inst_breakout = require("r3.comp.inst_breakout"),
	filt_breakout = require("r3.comp.filt_breakout"),
}
local valid_types = {}
for key in audited_pairs(components) do
	table.insert(valid_types, key)
end

local pos_limits = {
	x = { low = sim.CELL, high = sim.XRES - sim.CELL - 1 },
	y = { low = sim.CELL, high = sim.YRES - sim.CELL - 1 },
}

local function run(params)
	if rawget(_G, "r3plot") then
		r3plot.unregister()
	end
	if params.clear_sim then
		sim.clearSim()
	end
	check.table("params", params)
	check.table("params.components", params.components)
	if params.debug_stacks ~= nil then
		check.table("params.debug_stacks", params.debug_stacks)
		check.integer("params.debug_stacks.x", params.debug_stacks.x)
		check.integer("params.debug_stacks.y", params.debug_stacks.y)
	end
	local x, y = 0, 0
	if params.x ~= nil then
		check.integer("params.x", params.x)
		x = params.x
	end
	if params.y ~= nil then
		check.integer("params.y", params.y)
		y = params.y
	end
	local name_to_component_index = {}
	local buses = {}
	for ix_component, component in ipairs(params.components) do
		local component_name = ("params.components[%i]"):format(ix_component)
		check.table(component_name, component)
		check.string(component_name .. ".name", component.name)
		check.one_of(component_name .. ".type", component.type, valid_types)
		if name_to_component_index[component.name] then
			misc.user_error("%s is not unique", component_name .. ".name")
		end
		name_to_component_index[component.name] = ix_component
		if component.type == "cpu" then
			check.string(component_name .. ".cores", component.cores)
			local component_buses = {}
			for ix_core = 1, #component.cores do
				table.insert(component_buses, {
					through_areas = {},
				})
			end
			buses[ix_component] = component_buses
		end
	end
	local component_to_new_params = {}
	local component_order_forward = {}
	local component_order_backward = {}
	for ix_component = 1, #params.components do
		component_order_forward[ix_component] = {}
		component_order_backward[ix_component] = {}
	end
	local function mark_depends(dependent, dependee)
		component_order_forward[dependent][dependee] = true
		component_order_backward[dependee][dependent] = true
	end
	for ix_component, component in ipairs(params.components) do
		local component_name = ("params.components[%i]"):format(ix_component)
		local new_params = {
			debug_stacks = params.debug_stacks and true,
		}
		for key, value in audited_pairs(component) do
			new_params[key] = value
		end
		local param_types = components[component.type].param_types
		if param_types then
			for param_name, param_type in audited_pairs(param_types()) do
				local param_bus_name = component_name .. "." .. param_name
				if param_type.type == "lowhigh" then
					if (component[param_type.low] or component[param_type.high]) or not param_type.optional then
						new_params[param_name] = r3_check.lowhigh(component_name, component, param_type.low, param_type.high)
					end
				elseif param_type.type == "cpu_bus" then
					if component[param_name] ~= nil or not param_type.optional then
						check.table(param_bus_name, component[param_name])
						check.string(param_bus_name .. ".cpu", component[param_name].cpu)
						check.integer(param_bus_name .. ".bus_index", component[param_name].bus_index)
						local component_buses = buses[name_to_component_index[component[param_name].cpu]]
						local bus = component_buses and component_buses[component[param_name].bus_index + 1]
						if not bus then
							misc.user_error("%s does not refer to a known bus", param_bus_name)
						end
						new_params[param_name] = bus
						local cpu_index = name_to_component_index[component[param_name].cpu]
						mark_depends(ix_component, cpu_index)
					end
				else
					error("bad param type")
				end
			end
		end
		component_to_new_params[component] = new_params
	end
	local relative_parts = {}
	local areas = {}
	local function add_area(area)
		area.x = area.x + x
		area.y = area.y + y
		table.insert(areas, area)
		area.r, area.g, area.b = misc.colour_hash(area.name)
	end
	do
		local to_visit = {}
		for ix_component = 1, #params.components do
			if not next(component_order_forward[ix_component]) then
				table.insert(to_visit, ix_component)
			end
		end
		while #to_visit > 0 do
			local next_to_visit = {}
			for _, ix_component in ipairs(to_visit) do
				local component = params.components[ix_component]
				local component_name = ("params.components[%i]"):format(ix_component)
				local build_info = components[component.type].build(component_to_new_params[component], component_name)
				for _, area in ipairs(build_info.areas) do
					add_area({
						type = area.type,
						name = component.name .. "." .. area.name,
						x    = area.x,
						y    = area.y,
						w    = area.w,
						h    = area.h,
					})
				end
				plot.merge_parts(0, 0, relative_parts, build_info.parts)
				if component.type == "cpu" then
					local component_buses = buses[name_to_component_index[component.name]]
					for ix_bus, bus in ipairs(build_info.buses) do
						component_buses[ix_bus].x = bus.x
						component_buses[ix_bus].y = bus.y
					end
				end
				for dependent_index in audited_pairs(component_order_backward[ix_component]) do
					component_order_forward[dependent_index][ix_component] = nil
					if not next(component_order_forward[dependent_index]) then
						table.insert(next_to_visit, dependent_index)
					end
				end
			end
			to_visit = next_to_visit
		end
		for ix_component = 1, #params.components do
			assert(not next(component_order_forward[ix_component]), "circular dependency")
		end
	end
	for ix_component, component in ipairs(params.components) do
		local component_buses = buses[ix_component]
		if component_buses then
			local last_empty = false
			for ix_bus, bus in ipairs(component_buses) do
				local bus_parts = {}
				local function add_section(x_from, x_to, index, shift)
					for x = x_from, x_to + shift do
						for y = bus.y, bus.y + 3 do
							table.insert(bus_parts, { type = pt.FILT, x = x, y = y, dcolour = 0xFF00FFFF })
						end
					end
					add_area({
						type = "solid",
						name = component.name .. ".bus" .. (ix_bus - 1) .. ".section" .. index,
						x    = x_from,
						y    = bus.y,
						w    = x_to - x_from + 1,
						h    = 4,
					})
				end
				table.sort(bus.through_areas, function(lhs, rhs)
					return lhs.x < rhs.x
				end)
				local last_x = bus.x
				for ix_area, area in ipairs(bus.through_areas) do
					add_section(last_x, area.x - 1, ix_area - 1, 0)
					last_x = area.x + area.w
				end
				local termination_parts = bus_termination.build({
					debug_stacks = params.debug_stacks,
				})
				local bus_termination_x = last_x
				local bus_termination_w = 9
				local bus_termination_shift = 0
				if #bus.through_areas > 0 then
					local extra_width = 4
					add_section(last_x, last_x + extra_width - 1, #bus.through_areas, 2)
					bus_termination_x = bus_termination_x + extra_width
					bus_termination_w = bus_termination_w + 2
					bus_termination_shift = 2
				end
				local shrink = last_empty and #bus.through_areas == 0
				plot.merge_parts(bus_termination_x + bus_termination_shift, bus.y, bus_parts, termination_parts)
				add_area({
					type = "solid",
					name = component.name .. ".bus" .. (ix_bus - 1) .. ".termination",
					x    = bus_termination_x,
					y    = bus.y - (shrink and 0 or 2),
					w    = bus_termination_w,
					h    = shrink and 6 or 8,
				})
				plot.merge_parts(0, 0, relative_parts, bus_parts)
				last_empty = #bus.through_areas == 0
			end
		end
	end
	local debug_areas = params.debug_areas
	do
		local err
		local coverage = {}
		for ix_area, area in ipairs(areas) do
			if area.x < 0 or area.y < 0 then
				err = ("area %s has negative dimensions"):format(area.name)
				break
			end
			if area.x          <  sim.CELL            or
			   area.y          <  sim.CELL            or
			   area.x + area.w >= sim.XRES - sim.CELL or
			   area.y + area.h >= sim.YRES - sim.CELL then
				err = ("area %s is outside simulation bounds"):format(area.name)
				break
			end
			for y = area.y, area.y + area.h - 1 do
				for x = area.x, area.x + area.w - 1 do
					local key = plot.xy_key(x, y)
					if coverage[key] then
						err = ("area %s overlaps with area %s"):format(area.name, coverage[key].name)
						break
					end
					coverage[key] = area
				end
				if err then
					break
				end
			end
		end
		if err then
			print("\bl[r3plot]\14 " .. err)
			if not debug_areas then
				print("\bt[r3plot]\14 area debug view enabled automatically")
				debug_areas = true
			end
			for _, part in ipairs(relative_parts) do
				part.type = pt.DMND
				part.unstack = true
			end
		end
	end
	local parts = {}
	plot.merge_parts(x, y, parts, relative_parts)
	local aftersimdraw
	if params.debug_stacks then
		local aftersimdraw_user_stacks = plot.aftersimdraw_user_stacks(params.debug_stacks.x, params.debug_stacks.y, 0, 0, parts)
		local prev_aftersimdraw = aftersimdraw
		aftersimdraw = function()
			aftersimdraw_user_stacks()
			if not prev_aftersimdraw then
				return
			end
			return prev_aftersimdraw()
		end
	end
	plot.create_parts(0, 0, parts)
	if params.clear_sim then
		sim.paused(true)
		sim.heatSim(false)
		sim.newtonianGravity(false)
		sim.ambientHeatSim(false)
		sim.waterEqualization(0)
		sim.airMode(sim.AIR_OFF)
		sim.gravityMode(sim.GRAV_OFF)
	end
	if debug_areas then
		local prev_aftersimdraw = aftersimdraw
		aftersimdraw = function()
			for _, area in ipairs(areas) do
				gfx.fillRect(area.x, area.y, area.w, area.h, area.r, area.g, area.b, 150)
				gfx.drawRect(area.x, area.y, area.w, area.h, area.r, area.g, area.b)
			end
			local mx, my = sim.adjustCoords(ui.mousePosition())
			for _, area in ipairs(areas) do
				if mx >= area.x          and
				   my >= area.y          and
				   mx <  area.x + area.w and
				   my <  area.y + area.h then
					local tw, th = gfx.textSize(area.name)
					local tx, ty = mx - tw - 8, my - th - 6
					gfx.fillRect(tx, ty, tw + 7, th + 5, 0, 0, 0, 200)
					gfx.drawText(tx + 4, ty + 4, area.name, area.r, area.g, area.b)
				end
			end
			if not prev_aftersimdraw then
				return
			end
			return prev_aftersimdraw()
		end
	end
	local function unregister()
		if aftersimdraw then
			event.unregister(event.AFTERSIMDRAW, aftersimdraw)
		end
		rawset(_G, "r3plot", nil)
	end
	if aftersimdraw then
		event.register(event.AFTERSIMDRAW, aftersimdraw)
	end
	local r3plot = {
		unregister = unregister,
	}
	rawset(_G, "r3plot", r3plot)
	print("\bt[r3plot]\14 done")
end

return {
	run = misc.user_wrap(run),
}
