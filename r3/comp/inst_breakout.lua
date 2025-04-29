local bitx     = require("spaghetti.bitx")
local plot     = require("spaghetti.plot")
local misc     = require("spaghetti.misc")
local check    = require("spaghetti.check")
local r3_check = require("r3.check")

local color_input = 0xFF8080FF
local color_output = 0xFFC04080

local function build_inst_filt(do_inst, params, params_name, derived_params)
	local pins_name = params_name .. ".pins"
	local pin_count = params.pins and #params.pins
	local areas = {}
	local body_x = r3_check.lowhigh(params_name, params, "left", "right")

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local part        = ucontext.part
	local aray        = ucontext.aray
	local dray        = ucontext.dray
	local cray        = ucontext.cray
	local ldtc        = ucontext.ldtc
	local solid_spark = ucontext.solid_spark
	local pt = plot.pt
	local width
	if do_inst then
		width = 35 + pin_count * 2
	else
		width = 27
	end
	local height = 18
	local xoff
	if body_x.which == "left" then
		xoff = body_x.value
	else
		xoff = body_x.value - width + 1
	end

	local max_bits = 29
	local x_pins = 25
	local y_top = -6
	local y_bottom = 5
	local inputs = 0
	local outputs = 0
	local normally_low = 0
	local normally_high = 0
	if not do_inst then
		normally_low = derived_params.normally_low
		normally_high = derived_params.normally_high
	end
	local x_read = 5
	local x_write = 15
	local output_source_top
	local output_source_bottom = part({ type = pt.FILT, x = x_write + 1, y =  8, ctype = 0x20000000 })
	local input_source
	if do_inst then
		for ix_pin = 1, pin_count do
			local pin_type = params.pins:sub(ix_pin, ix_pin)
			local pin_name = ("%s character %i"):format(pins_name, ix_pin)
			check.one_of(pin_name, pin_type, { "i", "o", "l", "h" })
			local x_pin = x_pins + ix_pin * 2
			if ix_pin > 1 then
				part({ type = pt.INSL, x = x_pin - 1, y = y_top       , dcolour = 0xFFFFFFFF })
				part({ type = pt.INSL, x = x_pin - 1, y = y_top    + 1, dcolour = 0xFFFFFFFF })
				part({ type = pt.INSL, x = x_pin - 1, y = y_bottom + 5, dcolour = 0xFFFFFFFF })
				part({ type = pt.INSL, x = x_pin - 1, y = y_bottom + 6, dcolour = 0xFFFFFFFF })
			end
			if pin_type == "i" then
				local b = bitx.lshift(1, inputs)
				inputs = inputs + 1
				if inputs > max_bits then
					misc.user_error("%s specifies more than %i inputs", pins_name, max_bits)
				end
				part({ type = pt.INST, x = x_pin    , y = y_top, dcolour = color_input })
				part({ type = pt.ARAY, x = x_pin    , y = y_top + 1, dcolour = color_input, life = 8 })
				part({ type = pt.FILT, x = x_pin    , y = y_top + 2, ctype = b })
				part({ type = pt.FILT, x = x_pin - 1, y = y_top + 3 })
				part({ type = pt.FILT, x = x_pin    , y = y_top + 3, tmp = 6 })
				part({ type = pt.DTEC, x = x_pin    , y = y_top + 5 })
				part({ type = pt.FILT, x = x_pin    , y = y_top + 6, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_top + 6, tmp = 2, ctype = 0x20000000 })
				part({ type = pt.INST, x = x_pin    , y = y_bottom + 6, dcolour = color_input })
				part({ type = pt.ARAY, x = x_pin    , y = y_bottom + 5, dcolour = color_input, life = 9 })
				part({ type = pt.FILT, x = x_pin    , y = y_bottom + 4, ctype = b })
				part({ type = pt.FILT, x = x_pin - 1, y = y_bottom + 3 })
				part({ type = pt.FILT, x = x_pin    , y = y_bottom + 3, tmp = 6 })
				part({ type = pt.DTEC, x = x_pin    , y = y_bottom + 1 })
				part({ type = pt.FILT, x = x_pin    , y = y_bottom, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_bottom, tmp = 2, ctype = 0x20000000 })
			else
				local b = bitx.lshift(1, outputs)
				if pin_type	== "l" then
					normally_low = bitx.bor(normally_low, b)
				end
				if pin_type	== "h" then
					normally_high = bitx.bor(normally_high, b)
				end
				outputs = outputs + 1
				if outputs > max_bits then
					misc.user_error("%s specifies more than %i outputs", pins_name, max_bits)
				end
				part({ type = pt.INST, x = x_pin, y = y_top, dcolour = color_output })
				part({ type = pt.PSCN, x = x_pin, y = y_top + 1, dcolour = color_output })
				part({ type = pt.FILT, x = x_pin, y = y_top + 2, tmp = 1, ctype = b })
				part({ type = pt.FILT, x = x_pin    , y = y_top + 6, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_top + 6, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_top + 3 })
				part({ type = pt.FILT, x = x_pin    , y = y_top + 3, ctype = 0x20000000 })
				aray(x_pin, y_top + 4, 0, 1, pt.METL)
				part({ type = pt.INST, x = x_pin, y = y_bottom + 6, dcolour = color_output })
				part({ type = pt.PSCN, x = x_pin, y = y_bottom + 5, dcolour = color_output })
				part({ type = pt.FILT, x = x_pin, y = y_bottom + 4, tmp = 1, ctype = b })
				part({ type = pt.FILT, x = x_pin    , y = y_bottom, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_bottom, tmp = 6 })
				part({ type = pt.FILT, x = x_pin - 1, y = y_bottom + 3 })
				part({ type = pt.FILT, x = x_pin    , y = y_bottom + 3, ctype = 0x20000000 })
				aray(x_pin, y_bottom + 2, 0, -1, pt.METL)
			end
		end
	else
		if params.facing == "top" then
			local filt_input = part({ type = pt.FILT, x = 10, y = -6, dcolour = color_input, ctype = 0x20000000 })
			part({ type = pt.INSL, x = 10, y = -5, dcolour = color_input })
			ldtc(10, -4, filt_input.x, filt_input.y)
			local ltdc_output = ldtc(16, -5, output_source_bottom.x, output_source_bottom.y)
			ltdc_output.dcolour = color_output
			part({ type = pt.FILT, x = 16, y = -6, dcolour = color_output, ctype = 0x20000000 })
		else
			local filt_input = part({ type = pt.FILT, x = 10, y = 11, dcolour = color_input, ctype = 0x20000000 })
			part({ type = pt.INSL, x = 10, y = 10, dcolour = color_input })
			ldtc(10, -2, filt_input.x, filt_input.y)
			local ltdc_output = ldtc(16, 10, output_source_bottom.x, output_source_bottom.y)
			ltdc_output.dcolour = color_output
			part({ type = pt.FILT, x = 16, y = 11, dcolour = color_output, ctype = 0x20000000 })
		end
		part({ type = pt.FILT, x = 10, y = -3, ctype = 0x20000000 })
		part({ type = pt.STOR, x = 11, y = -3 })
		part({ type = pt.BRAY, x = 12, y = -3, ctype = 0x20000000 })
		part({ type = pt.INSL, x = 13, y = -3 })
		aray(9, -3, -1, 0, pt.METL)
	end
	if do_inst then
		output_source_top = part({ type = pt.FILT, x = x_write + 1, y = -3, ctype = 0x20000000 })
		ldtc(x_write + 1, -2, output_source_bottom.x, output_source_bottom.y)
		local x_input = x_pins + pin_count * 2
		local reset_top = part({ type = pt.FILT, x = x_input + 4, y = y_top + 6, ctype = 0x20000000 })
		ldtc(x_input + 1, y_top + 6, reset_top.x, reset_top.y)
		part({ type = pt.INSL, x = x_input + 3, y = y_top + 6 })
		part({ type = pt.STOR, x = x_input + 1, y = y_top + 6 })
		part({ type = pt.FILT, x = x_pins, y = y_top + 6, ctype = 0x20000000 })
		aray(x_pins - 1, y_top + 6, -1, 0, pt.METL)
		local top_source = part({ type = pt.BRAY, x = x_input + 2, y = y_top + 6, ctype = 0x20000000 })
		local reset_bottom = part({ type = pt.FILT, x = x_input + 5, y = y_bottom, ctype = 0x20000000 })
		ldtc(x_input + 1, y_bottom, reset_bottom.x, reset_bottom.y)
		part({ type = pt.INSL, x = x_input + 4, y = y_bottom })
		part({ type = pt.STOR, x = x_input + 1, y = y_bottom })
		ldtc(x_input + 2, y_bottom - 1, top_source.x, top_source.y)
		part({ type = pt.FILT, x = x_input + 2, y = y_bottom, ctype = 0x20000000, tmp = 2 })
		part({ type = pt.FILT, x = x_pins, y = y_bottom, ctype = 0x20000000 })
		aray(x_pins - 1, y_bottom, -1, 0, pt.METL)
		part({ type = pt.BRAY, x = x_input + 3, y = y_bottom, ctype = 0x20000000 })
		part({ type = pt.DTEC, x = x_input + 3, y = y_bottom + 1 })
		input_source = part({ type = pt.FILT, x = x_input + 3, y = y_bottom + 2, ctype = 0x20000000 })
		ldtc(x_pins, output_source_top.y, output_source_top.x, output_source_top.y)
		ldtc(x_pins, output_source_bottom.y, output_source_bottom.x, output_source_bottom.y)
	end
	local x_cleanup = width - 4
	local input_0, input_1
	do
		for y = 0, 3 do
			part({ type = pt.FILT, x = 0, y = y })
			local p = part({ type = pt.FILT, x = 1, y = y })
			if y == 0 then
				input_0 = p
			elseif y == 1 then
				input_1 = p
			end
		end
		part({ type = pt.FILT, x = width - 1, y = 0 })
		part({ type = pt.FILT, x = width - 1, y = 1 })
		part({ type = pt.FILT, x = width - 1, y = 2 })
		part({ type = pt.FILT, x = width - 1, y = 3 })
		part({ type = pt.FILT, x = width - 2, y = 2 })
		part({ type = pt.FILT, x = width - 2, y = 3 })
		for x = 2, width - 3 do
			part({ type = pt.FILT, x = x, y = 2, unstack = true })
			part({ type = pt.FILT, x = x, y = 3, unstack = true })
		end
		ldtc(width - 2, 0, input_0.x, input_0.y)
		ldtc(width - 2, 1, input_1.x, input_1.y)
	end
	do
		ldtc(x_read - 1, 0, input_0.x, input_0.y)
		aray(x_read - 1, 0, -1, 0, pt.METL)
		dray(x_cleanup, 0, x_read + 4, 0, 1, pt.PSCN)
		dray(x_read - 1, 0, x_write, 0, 1, pt.METL)
		dray(x_cleanup, 0, x_write, 0, 1, pt.PSCN)
		part({ type = pt.FILT, x = x_read + 6, y = 0 })
		part({ type = pt.DTEC, x = x_read + 5, y = 0 })
		part({ type = pt.LSNS, x = x_read + 5, y = 0, tmp = 3 })
		part({ type = pt.BRAY, x = x_read + 4, y = -1, ctype = 0x10000003, life = 4 })
		part({ type = pt.BRAY, x = x_read + 4, y =  4, ctype = 0x10000008, life = 10000, tmp = 1 })
		part({ type = pt.INSL, x = x_read + 7, y =  4 })
		local input_next = part({ type = pt.BRAY, x = x_read + 7, y =  5, ctype = 0x20000000, life = 2 })
		cray(x_read + 8, 5, input_next.x, input_next.y, pt.SPRK, 1, pt.PSCN)
		part({ type = pt.STOR, x = x_read + 7, y =  6 })
		part({ type = pt.FILT, x = x_read + 7, y =  7, ctype = 0x20000000 })
		if do_inst then
			ldtc(x_read + 8, 7, input_source.x, input_source.y)
		end
		aray(x_read + 7, 8, 0, 1, pt.METL, nil, 2)
		part({ type = pt.LSNS, x = x_read + 5, y = 5, tmp = 3 })
		part({ type = pt.FILT, x = x_read + 4, y = 5, ctype = 0x10001000 })
		local target_reset = part({ type = pt.CONV, x = x_read + 5, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
		local target_0 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y })
		local target_1 = part({ type = pt.ARAY, x = target_reset.x, y = target_reset.y + 1 })
		cray(x_read + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
		cray(x_read + 5, 0, target_0.x, target_0.y, pt.DTEC, 2, pt.PSCN)
		part({ type = pt.FILT, x = x_read    , y = 0 })
		part({ type = pt.STOR, x = x_read + 1, y = 0 })
		part({ type = pt.FILT, x = x_read + 2, y = 0, tmp = 7, ctype = bitx.bor(0x10080000, params.base_address) })
		part({ type = pt.FILT, x = x_read + 3, y = 0, ctype = 0x10000004 })
		part({ type = pt.ARAY, x = x_read + 5, y = 7 })
		dray(x_read + 5, 8, target_0.x, target_0.y, 1, pt.PSCN)
		dray(x_read + 5, 8, target_1.x, target_1.y, 1, pt.PSCN)
	end
	do
		aray(x_write - 1, 0, -1, 0, pt.METL)
		dray(x_cleanup, 0, x_write + 3, 0, 1, pt.PSCN)
		part({ type = pt.FILT, x = x_write + 5, y = 0 })
		part({ type = pt.DTEC, x = x_write + 4, y = 0 })
		part({ type = pt.LSNS, x = x_write + 4, y = 0, tmp = 3 })
		part({ type = pt.BRAY, x = x_write + 3, y = -1, ctype = 0x10000003, life = 4 })
		part({ type = pt.BRAY, x = x_write + 3, y =  4, ctype = 0x10000000, life = 10000, tmp = 1 })
		part({ type = pt.LSNS, x = x_write + 4, y = 4, tmp = 3 })
		ldtc(4, 4, input_1.x, input_1.y)
		local input_1_next = part({ type = pt.FILT, x = 5, y = 5, ctype = 0x20000000 })
		ldtc(x_write + 1, 5, input_1_next.x, input_1_next.y)
		aray(x_write + 1, 5, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_write + 2, y = 5, ctype = 0x20000000 })
		part({ type = pt.BRAY, x = x_write + 3, y = 5, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_write + 5, y = 4, ctype = 0x10001000 })
		local target_reset_0 = part({ type = pt.CONV, x = x_write + 4, y = 2, ctype = pt.FILT, tmp = pt.ARAY })
		local target_0 = part({ type = pt.ARAY, x = target_reset_0.x, y = target_reset_0.y })
		local target_reset_1 = part({ type = pt.CONV, x = x_write + 4, y = 5, ctype = pt.FILT, tmp = pt.ARAY })
		local target_1 = part({ type = pt.ARAY, x = target_reset_1.x, y = target_reset_1.y + 1 })
		cray(x_write + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
		cray(x_write + 4, 0, target_0.x, target_0.y, pt.DTEC, 1, pt.PSCN)
		cray(x_write + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
		cray(x_write + 4, 0, target_1.x, target_1.y, pt.DTEC, 1, pt.PSCN)
		part({ type = pt.FILT, x = x_write + 1, y = 0, tmp = 7, ctype = bitx.bor(0x10020000, params.base_address) })
		part({ type = pt.FILT, x = x_write + 2, y = 0, ctype = 0x10000004 })
		part({ type = pt.ARAY, x = x_write + 4, y = 7 })
		ldtc(x_write + 5, 6, x_write + 7, 6)
		part({ type = pt.FILT, x = x_write + 7, y = 6, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_write + 8, y = 7 })
		part({ type = pt.DTEC, x = x_write + 9, y = 8 })
		part({ type = pt.BRAY, x = x_write + 8, y = 8, ctype = 0x20000000 })
		part({ type = pt.FILT, x = x_write + 3, y = 6 })
		part({ type = pt.LDTC, x = x_write + 2, y = 7 })
		part({ type = pt.STOR, x = x_write + 2, y = 8 })
		part({ type = pt.STOR, x = x_write + 3, y = 8 })
		part({ type = pt.STOR, x = x_write + 4, y = 8, z = 20000000 })
		part({ type = pt.STOR, x = x_write + 5, y = 8 })
		do
			local ptype = pt.STOR
			local ctype, tmp
			if normally_low ~= 0 then
				ptype = pt.FILT
				ctype = normally_low
				tmp = 3
			end
			part({ type = ptype, x = x_write + 6, y = 8, tmp = tmp, ctype = ctype })
		end
		do
			local ptype = pt.STOR
			local ctype, tmp
			if normally_high ~= 0 then
				ptype = pt.FILT
				ctype = normally_high
				tmp = 2
			end
			part({ type = ptype, x = x_write + 7, y = 8, tmp = tmp, ctype = ctype })
		end
		aray(x_write, 8, -1, 0, pt.METL)
		dray(x_write + 4, 8, target_0.x, target_0.y, 1, pt.PSCN)
		dray(x_write + 4, 8, target_1.x, target_1.y, 1, pt.PSCN)
	end

	for i = 1, #parts do
		local part = parts[i]
		if not part.dcolour then
			part.dcolour = 0xFF007F7F
			if part.type == pt.FILT then
				part.dcolour = 0xFF00FFFF
			end
		end
	end
	ucontext.frame(1, -5, width - 2, height - 8, 0, 1)

	local parts_out = {}
	plot.merge_parts(xoff, params.bus.y, parts_out, parts)
	local interface = {
		type = "solid",
		name = "interface",
		x    = xoff,
		y    = params.bus.y - 6,
		w    = width,
		h    = height,
	}
	table.insert(areas, interface)
	table.insert(params.bus.through_areas, interface)
	return {
		parts = parts_out,
		areas = areas,
	}
end

local function param_types()
	return {
		x = {
			type = "lowhigh",
			low  = "left",
			high = "right",
		},
		bus = {
			type = "cpu_bus",
		},
	}
end

local function build(params, params_name)
	r3_check.base_address(params_name .. ".base_address", params.base_address, 0xFFFF)
	local pins_name = params_name .. ".pins"
	check.string(pins_name, params.pins)
	local pin_count = #params.pins
	if pin_count == 0 then
		misc.user_error("%s is empty", pins_name)
	end
	return build_inst_filt(true, params, params_name)
end

return {
	build           = build,
	build_inst_filt = build_inst_filt,
	param_types     = param_types,
}
