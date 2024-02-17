local strict = require("spaghetti.strict")
strict.wrap_env()

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")

local function modulef(info)
	local fuzz
	if info.fuzz then
		math.randomseed(os.time())
		function fuzz(fuzz_expect, ctype_at)
			-- TODO: test inputs/outputs against keepalive/payload specification
			if fuzz_expect then
				for _, output_info in ipairs(info.outputs or {}) do
					local expect_value = fuzz_expect[output_info.name]
					if ctype_at(2 + output_info.index, 3) ~= expect_value then
						return nil, ("output %s expected to have value %08X"):format(output_info.name, expect_value)
					end
				end
			end
			local values = info.fuzz()
			for _, input_info in ipairs(info.inputs or {}) do
				local set_value = values.inputs[input_info.name]
				ctype_at(2 + input_info.index, -3, set_value)
			end
			return values.outputs
		end
	end
	local function instantiate(named_inputs)
		for _, input_info in ipairs(info.inputs or {}) do
			local input = named_inputs[input_info.name]
			input:assert(input_info.keepalive, input_info.payload)
		end
		local named_outputs = info.func(named_inputs)
		for _, output_info in ipairs(info.outputs or {}) do
			local output = named_outputs[output_info.name]
			output:assert(output_info.keepalive, output_info.payload)
		end
		return named_outputs
	end
	local function design()
		local inputs = {}
		local outputs = {}
		local clobbers = {}
		local function auto_clobber(index)
			if index >= 1 and index <= info.storage_slots then
				clobbers[index] = true
			end
		end
		local extra_parts = {}
		local named_inputs = {}
		for _, input_info in ipairs(info.inputs or {}) do
			local expr = spaghetti.input(input_info.keepalive, input_info.payload)
			inputs[input_info.index] = expr
			named_inputs[input_info.name] = expr
			if input_info.never_zero then
				expr:never_zero()
			else
				assert(bitx.band(input_info.initial, expr.keepalive_) ~= 0)
			end
			table.insert(extra_parts, { type = elem.DEFAULT_PT_FILT, x = 2 + input_info.index, y = -3, ctype = input_info.initial })
			table.insert(extra_parts, { type = elem.DEFAULT_PT_LDTC, x = 2 + input_info.index, y = -1 })
			auto_clobber(input_info.index + 1)
			auto_clobber(input_info.index - 1)
		end
		local named_outputs = instantiate(named_inputs)
		for _, output_info in ipairs(info.outputs or {}) do
			outputs[output_info.index] = named_outputs[output_info.name]
			table.insert(extra_parts, { type = elem.DEFAULT_PT_LDTC, x = 2 + output_info.index, y = 2 })
			table.insert(extra_parts, { type = elem.DEFAULT_PT_FILT, x = 2 + output_info.index, y = 3 })
		end
		for _, part in ipairs(info.extra_parts or {}) do
			table.insert(extra_parts, part)
		end
		return {
			design = spaghetti.build({
				inputs        = inputs,
				outputs       = outputs,
				clobbers      = clobbers,
				stacks        = info.stacks,
				storage_slots = info.storage_slots,
				work_slots    = info.work_slots,
			}),
			extra_parts = extra_parts,
			opt_params  = info.opt_params,
			pause       = false,
			debug       = false,
		}
	end
	return {
		design      = design,
		instantiate = instantiate,
		fuzz        = fuzz,
	}
end

return {
	module = modulef,
}
