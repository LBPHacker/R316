local strict = require("spaghetti.strict")
strict.wrap_env()

local bitx = require("spaghetti.bitx")
local plot = require("spaghetti.plot")

local util = require("r3.util")

local function build()
	local pt = plot.pt
	local parts = {}
	local ucontext = util.make_context(parts)
	local sig_magn      = ucontext.sig_magn
	local mutate        = ucontext.mutate
	local piston_extend = ucontext.piston_extend
	local part          = ucontext.part
	local spark         = ucontext.spark
	local xy_key        = ucontext.xy_key
	local solid_spark   = ucontext.solid_spark
	local lsns_taboo    = ucontext.lsns_taboo
	local lsns_spark    = ucontext.lsns_spark
	local dray          = ucontext.dray
	local ldtc          = ucontext.ldtc
	local cray          = ucontext.cray
	local aray          = ucontext.aray

	local chars_nh = 16
	local chars_nv = 16
	local char_size = 8
	local chars_w = chars_nh * char_size
	local chars_h = chars_nv * char_size

	local x_content = 0
	local y_content = 0
	local x_after_content = x_content + chars_w
	local y_after_content = y_content + chars_h

	for xx = 0, chars_w - 1 do -- content
		for yy = 0, chars_h - 1 do
			part({ type = pt.BRCK, x = x_content + xx, y = y_content + yy })
		end
	end

	for yy = 0, chars_nv - 1 do -- right char pistons
		for yyy = 0, char_size - 1 do
			part({ type = pt.FRME, x = 5 + x_after_content + yy % 2, y = y_content + yy * char_size + yyy })
			if yy % 2 == 1 then
				part({ type = pt.BRCK, x = 5 + x_after_content, y = y_content + yy * char_size + yyy })
			end
		end
		local y_piston = y_content + yy * char_size + char_size - 1
		if yy % 2 == 0 then
			part({ type = pt.PSTN, x = 6 + x_after_content, y = y_piston, extend = 0 })
		end
		solid_spark( 9 + x_after_content, y_piston + 1, -1, 0, pt.PSCN, true)
		solid_spark(10 + x_after_content, y_piston + 1, -1, 0, pt.NSCN, true)
		part({ type = pt.PSTN, x = 7 + x_after_content, y = y_piston, ctype = pt.DRAY, extend = 9 })
		part({ type = pt.PSTN, x = 8 + x_after_content, y = y_piston, ctype = pt.DRAY, extend = 0, tmp = 10000 })
		part({ type = pt.PSTN, x = 9 + x_after_content, y = y_piston, ctype = pt.DRAY, extend = 0, tmp = 10000 })
	end

	for yy = 0, chars_h - 1 do -- right char deleters
		solid_spark(x_after_content + yy % 2 * 3 + 1, y_content + yy, 0, 0, pt.PSCN, true)
		part({ type = pt.CRAY, x = x_after_content + yy % 2 * 3, y = y_content + yy })
		part({ type = pt.FILT, x = x_after_content - yy % 2 * 3 + 4, y = y_content + yy })
		part({ type = pt.FILT, x = x_after_content - yy % 2 * 3 + 3, y = y_content + yy })
		part({ type = pt.FILT, x = x_after_content              + 2, y = y_content + yy })
	end

	for yy = 0, chars_h - 1 do -- right char templates
		for xx = 0, char_size - 1 do
			part({ type = pt.BRCK, x = x_after_content + 10 + xx, y = y_content + yy })
		end
	end

	for yy = 0, chars_h - 1 do -- right char copiers
		part({ type = pt.DRAY, x = x_after_content + 18, y = y_content + yy })
		part({ type = pt.INST, x = x_after_content + 19, y = y_content + yy })
	end

	for xx = 0, chars_nh - 1 do -- bottom char pistons
		for xxx = 0, char_size - 1 do
			part({ type = pt.FRME, x = x_content + xx * char_size + xxx, y = y_after_content + 5 + xx % 2 })
			if xx % 2 == 1 then
				part({ type = pt.BRCK, x = x_content + xx * char_size + xxx, y = y_after_content + 5 })
			end
		end
		local x_piston = x_content + xx * char_size + char_size - 1
		if xx % 2 == 0 then
			part({ type = pt.PSTN, x = x_piston, y = 6 + y_after_content, extend = 0 })
		end
		solid_spark(x_piston + 1,  9 + y_after_content, 0, -1, pt.PSCN, true)
		solid_spark(x_piston + 1, 10 + y_after_content, 0, -1, pt.NSCN, true)
		part({ type = pt.PSTN, x = x_piston, y = 7 + y_after_content, ctype = pt.DRAY, extend = 9 })
		part({ type = pt.PSTN, x = x_piston, y = 8 + y_after_content, ctype = pt.DRAY, extend = 0, tmp = 10000 })
		part({ type = pt.PSTN, x = x_piston, y = 9 + y_after_content, ctype = pt.DRAY, extend = 0, tmp = 10000 })
	end

	for xx = 0, chars_w - 1 do -- bottom char deleters
		solid_spark(x_content + xx, y_after_content + xx % 2 * 3 + 1, 0, 0, pt.PSCN, true)
		part({ type = pt.CRAY, x = x_content + xx, y = y_after_content + xx % 2 * 3 })
		part({ type = pt.FILT, x = x_content + xx, y = y_after_content - xx % 2 * 3 + 4 })
		part({ type = pt.FILT, x = x_content + xx, y = y_after_content - xx % 2 * 3 + 3 })
		part({ type = pt.FILT, x = x_content + xx, y = y_after_content              + 2 })
	end

	for xx = 0, chars_w - 1 do -- bottom char templates
		for yy = 0, char_size - 1 do
			part({ type = pt.BRCK, x = x_content + xx, y = y_after_content + 10 + yy })
		end
	end

	for xx = 0, chars_w - 1 do -- bottom char copiers
		part({ type = pt.DRAY, x = x_content + xx, y = y_after_content + 18 })
		part({ type = pt.INST, x = x_content + xx, y = y_after_content + 19 })
	end

	for yy = 0, char_size - 1 do -- bottom right char template
		for xx = 0, char_size - 1 do
			part({ type = pt.BRCK, x = x_after_content + 10 + xx, y = y_after_content + 10 + yy })
		end
	end

	for xx = 0, char_size - 1 do -- bottom right char copier upward
		part({ type = pt.DRAY, x = x_after_content + xx + 10, y = y_after_content + 18 })
		part({ type = pt.INST, x = x_after_content + xx + 10, y = y_after_content + 19 })
	end

	for yy = 0, char_size - 1 do -- bottom right char copier leftward
		part({ type = pt.DRAY, x = x_after_content + 18, y = y_after_content + yy + 10 })
		part({ type = pt.INST, x = x_after_content + 19, y = y_after_content + yy + 10 })
	end


	local padding = 21
	local x1 = -padding
	local x2 = padding - 1 + chars_w
	local y1 = -padding
	local y2 = padding - 1 + chars_h
	ucontext.frame(x1, y1, x2, y2)

	return parts
end

return {
	build = build,
}
