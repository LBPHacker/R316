local bitx     = require("spaghetti.bitx")
local plot     = require("spaghetti.plot")
local misc     = require("spaghetti.misc")
local check    = require("spaghetti.check")
local font     = require("r3.comp.terminal.font")
local core     = require("r3.comp.terminal.core.generated")
local kbdcore  = require("r3.comp.terminal.kbdcore.generated")
local r3_check = require("r3.check")

local outputs = {
	char_color       = { x =   9, y = -18, ctype = 0x20000000 },
	char_color_2     = { x =  35, y = -18, ctype = 0x20000000 },
	char_dindex      = { x =  64, y = -18, ctype = 0x20000000 },
	char_cindex      = { x =  84, y = -18, ctype = 0x20000000 },
	pixel_xindex     = { x =  -1, y = -18, ctype = 0x3FFFFFFF },
	char_hdray       = { x = -15, y = -18, ctype = 0x10000005 },
	char_vdray       = { x = -13, y = -18, ctype = 0x10000005 },
	char_hmask       = { x = -17, y = -18, ctype = 0x3FFFFFFF },
	char_vmask       = { x = -11, y = -18, ctype = 0x3FFFFFFF },
	pixel_yindex     = { x =  -5, y = -18, ctype = 0x200000B2 },
	char_rindex_low  = { x =  15, y = -18, ctype = 0x10000002 },
	char_rindex_high = { x =  17, y = -18, ctype = 0x10000003 },
}
local char_size = 8

local function build_internal(params, derived_params)
	local chars_nh          = params.chars_nh
	local chars_nv          = params.chars_nv
	local single_pixel      = params.single_pixel
	local base_address      = params.base_address
	local debug_flags       = params.debug_flags
	local unibody           = params.unibody
	local y_interface       = derived_params.y_interface
	local y_keyboard        = derived_params.y_keyboard

	--[[
	 - rows are row counts, columns are column counts
	 - . means invalid
	 - # means valid with the 1px plotter
	 - + means only valid without the 1px plotter
	 - any combination not shown in the table is invalid

	     1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2
	     2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9
	    ------------------------------------
	 4 | + + + + + + + + + + + + + + + + + +
	 5 | + + + + + + + + + + + + + + + + + +
	 6 | + + + + + + + + + + + + + + + + + +
	 7 | + + + + + + + + + + + + + + + + + +
	 8 | # + + + + + + + + + + + + + + + + +
	 9 | # # # # # + + + + + + + + + + + + +
	10 | # # # # # # # # # + + + + + + + + +
	11 | # # # # # # # # # # # # # + + + + +
	12 | # # # # # # # # # # # # # # # # # +
	13 | . # # # # # # # # # # # # # # # # #
	14 | . # # # # # # # # # # # # # # # # #
	15 | . # # # # # # # # # # # # # # # # #
	16 | . # # # # # # # # # # # # # # # # #
	17 | . . # # # # # # # # # # # # # # # #
	18 | . . # # # # # # # # # # # # # # # #
	19 | . . # # # # # # # # # # # # # # # #
	20 | . . # # # # # # # # # # # # # # # #
	21 | . . . # # # # # # # # # # # # # # #
	22 | . . . # # # # # # # # # # # # # # #
	23 | . . . # # # # # # # # # # # # # # #
	24 | . . . # # # # # # # # # # # # # # #
	25 | . . . . # # # # # # # # # # # # # #
	26 | . . . . # # # # # # # # # # # # # #
	27 | . . . . # # # # # # # # # # # # # #
	28 | . . . . # # # # # # # # # # # # # #
	29 | . . . . . # # # # # # # # # # # # #
	--]]

	local pt = plot.pt
	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local sig_magn      = ucontext.sig_magn
	local mutate        = ucontext.mutate
	local piston_extend = ucontext.piston_extend
	local part          = ucontext.part
	local spark         = ucontext.spark
	local xy_key        = ucontext.xy_key
	local solid_spark   = ucontext.solid_spark
	local lsns_taboo    = ucontext.lsns_taboo
	local lsns_spark    = ucontext.lsns_spark
	local dray_log      = ucontext.dray_log
	local dray          = ucontext.dray
	local ldtc          = ucontext.ldtc
	local cray          = ucontext.cray
	local aray          = ucontext.aray
	local spark_row     = ucontext.spark_row

	local colors = {
		0x000000,
		0x0000AA,
		0x00AA00,
		0x00AAAA,
		0xAA0000,
		0xAA00AA,
		0xAAAA00,
		0xAAAAAA,
		0x555555,
		0x5555FF,
		0x55FF55,
		0x55FFFF,
		0xFF5555,
		0xFF55FF,
		0xFFFF55,
		0xFFFFFF,
	}

	local chars_w = chars_nh * char_size
	local chars_h = chars_nv * char_size

	local x_content = 0
	local y_content = 0
	local x_after_content = x_content + chars_w
	local y_after_content = y_content + chars_h

	local x_bi_disp_left, x_bi_disp_right
	local padding = 21
	if derived_params.have_screen then
	if debug_flags and debug_flags.no_core then
		for _, output in misc.ordered_pairs(outputs) do
			part({ type = pt.FILT, x = output.x, y = output.y, ctype = output.ctype })
		end
	else
		local core_x = 24
		local storage_remap = setmetatable({}, { __index = function(_, k)
			if k >= 73 then
				k = k + chars_w - 93
			elseif k >= 65 then
				k = k + chars_w - 96
			end
			return k
		end })
		plot.merge_parts(core_x, -18, parts, core.get_parts(), storage_remap)
	end
	do -- core constants
		local y = y_after_content + 6
		local function constant(x, value)
			part({ type = pt.FILT, x = x, y = y, ctype = value })
			part({ type = pt.FILT, x = x, y = -17, ctype = value })
			ldtc(x, -16, x, y)
			for _, part in ipairs(parts) do
				if part.x == x and part.y == -18 then
					part.ctype = value
				end
			end
		end
		constant(48, bitx.bor(0x10000000, bitx.bor(chars_nh, bitx.lshift(chars_nh, 5))))
		constant(50, bitx.bor(0x10000000, bitx.bor(chars_nv, bitx.lshift(chars_nv, 5))))
		constant(52, bitx.bor(0x00020000, base_address))
	end

	for xx = 0, chars_w - 1 do -- content
		for yy = 0, chars_h - 1 do
			local freezable = xx >= sim.CELL and
			                  yy >= sim.CELL and
			                  xx <  chars_w - sim.CELL and
			                  yy <  chars_h - sim.CELL
			part({ type = pt.CRMC, x = x_content + xx, y = y_content + yy, freezable = freezable, dcolour = 0xFF000000 })
		end
	end

	for yy = 0, chars_h - 1 do -- right char templates
		for xx = 0, char_size - 1 do
			part({ type = pt.STOR, x = x_after_content + 10 + xx, y = y_content + yy, grvt_cover = params.grvt_cover })
		end
	end

	local right_char_copy_space = 1

	for xx = 0, chars_w - 1 do -- bottom char templates
		for yy = 0, char_size - 1 do
			part({ type = pt.STOR, x = x_content + xx, y = y_after_content + 10 + yy, grvt_cover = params.grvt_cover })
		end
	end

	do -- copier dray inst reset
		local function patch_inwr_cray() -- fragile: patch inwr cray
			-- delete last batch of convs
			local convs_begin, convs_end
			for i = #parts, 1, -1 do
				if not convs_end then
					if parts[i].type == pt.CONV then
						convs_end = i
					end
				end
				if convs_end then
					if parts[i].type ~= pt.CONV then
						convs_begin = i + 1
						break
					end
				end
			end
			assert(convs_begin and convs_end)
			for i = convs_end, convs_begin, -1 do
				table.remove(parts, i)
			end
		end

		local x_copier = x_after_content + char_size + 11
		local y_copier = y_after_content + char_size + 11
		spark_row(x_copier, y_after_content + 10, x_copier, chars_h - 1, pt.INWR, chars_h, 4, 4)
		part({ type = pt.LSNS, x = x_copier - 1, y = y_after_content + 15, tmp = 3 })
		part({ type = pt.FILT, x = x_copier - 2, y = y_after_content + 15, ctype = 0x10000004 })
		patch_inwr_cray()
		do
			local y = y_after_content + 14
			local source = part({ type = pt.FILT, x = outputs.char_vdray.x, y = y - 1, ctype = 0x10000005 })
			ldtc(source.x, source.y - 1, outputs.char_vdray.x, outputs.char_vdray.y)
			part({ type = pt.LSNS, x = x_copier	- 1, y = y - 1, tmp = 3 })
			part({ type = pt.FILT, x = x_copier - 2, y = y - 1, ctype = 0x10000005 })
			ldtc(x_copier - 3, y - 1, source.x, source.y)
		end

		local x_bottom = -12
		spark_row(x_bottom, y_copier, 0, y_copier, pt.INWR, chars_w, 4)
		patch_inwr_cray()
		part({ type = pt.FILT, x = x_bottom - 1, y = y_copier - 1, ctype = 0x10000003 })
		do
			part({ type = pt.LSNS, x = x_bottom - 2, y = y_copier - 1, tmp = 3 })
			part({ type = pt.FILT, x = x_bottom + 2, y = y_copier - 1 })
			local source_prev = part({ type = pt.FILT, x = x_bottom - 3, y = y_copier - 1, ctype = 0x10000005 })
			ldtc(x_bottom - 3, y_copier - 2, outputs.char_hdray.x, outputs.char_hdray.y)
			ldtc(x_bottom + 1, y_copier - 1, source_prev.x, source_prev.y)
			part({ type = pt.LSNS, x = x_bottom + 1, y = y_copier - 1, tmp = 3 })
		end
	end

	local copier_last
	do -- right char copier insert + apom
		local x = x_after_content + char_size + 10
		copier_last = part({ type = pt.HEAC, x = x, y = -1 - right_char_copy_space })
		local apom_base = -right_char_copy_space
		local apom_size = chars_h + right_char_copy_space
		cray(x, -2 - right_char_copy_space, x, apom_base + char_size - 1, pt.INSL, apom_size, pt.PSCN)
		cray(x, -2 - right_char_copy_space, x, apom_base + char_size - 1, pt.INSL, apom_size, pt.PSCN)
		cray(x, -2 - right_char_copy_space, x, apom_base + char_size - 1, pt.INSL, apom_size, pt.PSCN)
		dray_log(x, -2 - right_char_copy_space, x, apom_base, apom_size, pt.PSCN)
		for i = 1, right_char_copy_space + 1 do
			cray(x, -2 - right_char_copy_space, x, -3 + i, pt.INSL, 1, pt.PSCN)
			cray(x, -2 - right_char_copy_space, x, -3 + i, pt.INSL, 1, pt.PSCN)
		end
		cray(x, y_after_content + char_size - 1, x, y_after_content +           - 1, pt.INSL, apom_size, pt.PSCN)
		cray(x, y_after_content + char_size - 1, x, y_after_content + char_size - 2, pt.INSL, apom_size, pt.PSCN)
		cray(x, y_after_content + char_size - 1, x, y_after_content + char_size - 2, pt.INSL, apom_size, pt.PSCN)
		cray(x, y_after_content + char_size - 1, x, y_after_content + char_size - 2, pt.INSL, apom_size, pt.PSCN)
		part({ type = pt.CONV, x = x - 2, y = -3, tmp = pt.SPRK, ctype = pt.INSL })
	end

	do -- bottom char copier insert
		local y = y_after_content + char_size + 10
		part({ type = pt.HEAC, x = -1, y = y })
		dray_log(-2, y, 0, y, chars_w, pt.PSCN)
	end

	local function generic_demuxer(x, y, x_off, y_off, targets, lsns_filt, cond_part, no_auto_transparent, aray_life, source_ctype)
		assert(x and y and x_off and y_off and targets and lsns_filt and cond_part and type(no_auto_transparent) == "boolean" and aray_life and source_ctype)
		spark({ type = pt.PSCN, x = x - x_off, y = y - y_off })
		part({ type = pt.FILT, x = x + x_off * 3, y = y + y_off * 3, tmp = 1, ctype = source_ctype })
		if not no_auto_transparent then
			part({ type = pt.STOR, x = x + x_off * 2, y = y + y_off * 2 })
		end
		part({ type = pt.FILT, x = x + x_off * 1, y = y + y_off * 1, ctype = lsns_filt.ctype })
		local bit_temp = part({ type = pt.FILT, x = x - x_off * 2, y = y - y_off * 2, ctype = targets[#targets].bit_filt.ctype })
		local part_count = 0
		for i = 1, #targets do
			part_count = part_count + #targets[i].parts
		end
		cray(x, y, targets[1].parts[1].x, targets[1].parts[1].y, pt.ARAY, part_count                           , false)
		cray(x, y, targets[1].parts[1].x, targets[1].parts[1].y, pt.ARAY, part_count - #targets[#targets].parts, false)
		part({ type = pt.CONV, x = x, y = y, ctype = pt.INST, tmp = pt.SPRK })
		part({ type = pt.CONV, x = x, y = y, ctype = pt.SPRK, tmp = pt.INST })
		part({ type = pt.LSNS, x = x, y = y, tmp = 3 })
		for i = #targets, 1, -1 do
			local target = targets[i]
			local next_target = targets[i > 1 and (i - 1) or #targets]
			ldtc(x, y, bit_temp.x, bit_temp.y)
			part({ type = pt.ARAY, x = x, y = y, life = aray_life })
			for j = 1, #target.parts do
				cond_part(x, y, target.parts[j].x, target.parts[j].y)
			end
			part({ type = pt.CONV, x = x, y = y, ctype = pt.HEAC, tmp = pt.FILT })
			part({ type = pt.CONV, x = x, y = y, ctype = pt.FILT, tmp = pt.SPRK })
			ldtc(x, y, next_target.bit_filt.x, next_target.bit_filt.y)
			part({ type = pt.CONV, x = x, y = y, ctype = pt.PSCN, tmp = pt.FILT })
			part({ type = pt.CONV, x = x, y = y, ctype = pt.SPRK, tmp = pt.PSCN })
			part({ type = pt.CONV, x = x, y = y, ctype = pt.FILT, tmp = pt.HEAC })
			ldtc(x, y, lsns_filt.x, lsns_filt.y)
			if i > 1 then
				part({ type = pt.LSNS, x = x, y = y, tmp = 3 })
				cray(x, y, next_target.parts[1].x, next_target.parts[1].y, pt.ARAY, #next_target.parts, false)
				part({ type = pt.CONV, x = x, y = y, ctype = pt.INST, tmp = pt.SPRK })
				part({ type = pt.CONV, x = x, y = y, ctype = pt.SPRK, tmp = pt.INST })
				part({ type = pt.LSNS, x = x, y = y, tmp = 3 })
			end
		end
	end

	local right_cray_first
	do
		local topmost_cray
		local y_demux = y_after_content + 15
		for rank = 0, 1 do
			local x_rank = x_after_content + rank * 3
			local targets = {}
			for yy = chars_nv - 1, 0, -1 do
				local target = {
					parts = {},
				}
				for yyy = char_size - 1, 0, -1 do
					local rank_index = yyy % 2
					if rank_index ~= rank then
						table.insert(target.parts, part({ type = pt.INSL, x = x_rank + 1, y = y_content + yy * char_size + yyy }))
						local rank_cray = part({ type = pt.CRAY, x = x_rank, y = y_content + yy * char_size + yyy })
						if rank == 0 then
							right_cray_first = rank_cray
						end
					else
						target.bit_filt = part({ type = pt.FILT, x = x_rank + 1, y = y_content + yy * char_size + yyy, ctype = bitx.lshift(1, yy) })
						part({ type = pt.FILT, x = x_rank, y = y_content + yy * char_size + yyy })
					end
				end
				table.insert(targets, target)
			end
			for y = y_after_content, y_demux - 4 do
				part({ type = pt.FILT, x = x_rank + 1, y = y, unstack = true })
			end
			local lsns_filt = part({ type = pt.FILT, x = x_rank + 1, y = y_after_content + 19, ctype = 0x10000003 })
			generic_demuxer(x_rank + 1, y_demux, 0, -1, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to, y_to + 1, 2, false)
			end, true, 20, outputs.char_vmask.ctype)
			solid_spark(x_rank + 2, y_demux - 2, -1, 0, pt.PSCN, true)
			part({ type = pt.DMND, x = x_rank + 1, y = -1 })
		end
		for yy = 0, chars_h - 1 do
			part({ type = pt.FILT, x = x_after_content + 2, y = y_content + yy })
		end
		part({ type = pt.FILT, x = x_after_content + 2, y = y_demux - 3 })
		part({ type = pt.FILT, x = x_after_content + 3, y = y_demux - 3 })
		local source = part({ type = pt.FILT, x = outputs.char_vmask.x, y = y_demux - 3, ctype = outputs.char_vmask.ctype })
		ldtc(x_after_content, y_demux - 3, source.x, source.y)
		ldtc(outputs.char_vmask.x, source.y - 1, outputs.char_vmask.x, outputs.char_vmask.y)
	end

	do
		local x_demux = x_after_content + 13
		for rank = 0, 1 do
			local y_rank = y_after_content + rank * 3
			local targets = {}
			for xx = chars_nh - 1, 0, -1 do
				local target = {
					parts = {},
				}
				for xxx = char_size - 1, 0, -1 do
					local rank_index = xxx % 2
					if rank_index == rank then
						table.insert(target.parts, part({ type = pt.INSL, x = x_content + xx * char_size + xxx, y = y_rank + 1 }))
						part({ type = pt.CRAY, x = x_content + xx * char_size + xxx, y = y_rank })
					else
						target.bit_filt = part({ type = pt.FILT, x = x_content + xx * char_size + xxx, ctype = bitx.lshift(1, xx), y = y_rank + 1 })
						part({ type = pt.FILT, x = x_content + xx * char_size + xxx, y = y_rank })
					end
				end
				table.insert(targets, target)
			end
			for x = x_after_content, x_demux - 4 do
				part({ type = pt.FILT, x = x, y = y_rank + 1, unstack = true })
			end
			local lsns_filt = part({ type = pt.FILT, x = x_after_content + 19, y = y_rank + 1, ctype = 0x10000003 })
			generic_demuxer(x_demux, y_rank + 1, -1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to + 1, y_to, 2, false)
			end, true, 20, outputs.char_hmask.ctype)
			solid_spark(x_demux - 2, y_rank, 0, 1, pt.PSCN, true)
			part({ type = pt.DMND, x = -1, y = y_rank + 1 })
		end
		for xx = 0, chars_w - 1 do
			part({ type = pt.FILT, x = x_content + xx, y = y_after_content + 2 })
		end
		part({ type = pt.FILT, x = x_demux - 3, y = y_after_content + 2 })
		part({ type = pt.FILT, x = x_demux - 3, y = y_after_content + 3 })
		local source = part({ type = pt.FILT, x = x_demux - 3, y = -4, ctype = outputs.char_hmask.ctype })
		local source_prev = part({ type = pt.FILT, x = outputs.char_hmask.x, y = -4, ctype = outputs.char_hmask.ctype })
		ldtc(x_demux - 3, y_after_content, source.x, source.y)
		ldtc(source.x - 1, source.y, source_prev.x, source_prev.y)
		ldtc(outputs.char_hmask.x, source_prev.y - 1, outputs.char_hmask.x, outputs.char_hmask.y)
	end

	local charpipe_1_x = -8
	local charpipe_1_y = chars_h + 10
	do -- character pipeline 1
		for xx = 0, char_size - 1 do
			for yy = 0, char_size - 1 do
				part({ type = pt.STOR, x = charpipe_1_x + xx, y = charpipe_1_y + yy, grvt_cover = params.grvt_cover })
			end
			part({ type = pt.DMND, x = charpipe_1_x + xx, y = charpipe_1_y - 1 })
		end
		local y_delete = -19
		for xx = 0, char_size - 1 do
			cray(charpipe_1_x + xx, y_delete + xx % 2 * 3, charpipe_1_x + xx, charpipe_1_y, pt.SPRK, char_size, pt.PSCN)
		end
	end

	local y_char_gen_fg
	local y_bg_bricks
	local y_char_gen_odd_offset
	local x_char_gen_src, y_char_gen_src
	local x_char_gen = charpipe_1_x
	local y_char_gen = 11
	do -- character generator
		x_char_gen_src = x_char_gen - 5
		y_char_gen_src = y_char_gen - 12
		local odd_offset = 7
		local stack_gap = 3
		local y_stack = y_char_gen + stack_gap
		y_char_gen_fg = y_stack - 2
		y_char_gen_odd_offset = odd_offset
		for j = 0, stack_gap - 1 do
			for i = 0, char_size - 1 do
				part({ type = pt.STOR, x = x_char_gen + i, y = y_char_gen + j - 3 })
			end
		end
		for j = 0, 1 do
			for i = 0, 1 do
				local x = x_char_gen + j + i * 4 + 1
				local y = y_stack - 3 + j * odd_offset
				part({ type = pt.FILT, x = x, y = y, tmp = 6 })
				ldtc(x - 2, y, x - 6 - i * 6 - j, y, nil, 1)
			end
		end
		for j = 0, char_size - 1 do
			local x_stack = x_char_gen + j
			local targets = {}
			for i = 0, char_size - 1 do
				local bit_filt_y = y_char_gen - 24 - i
				if i < 6 or j % 2 == 0 then
					bit_filt_y = bit_filt_y + 3
				end
				if i < 5 then
					bit_filt_y = bit_filt_y + 1
				end
				if i < 1 then
					bit_filt_y = bit_filt_y + 1
					if j == 0 then
						bit_filt_y = bit_filt_y + 3
					end
				end
				table.insert(targets, {
					bit_filt = part({ type = pt.FILT, x = x_stack, y = bit_filt_y, ctype = bitx.lshift(1, i + math.floor(j / 2) % 2 * 8 + j % 2 * 8), tmp = 6 }),
					parts    = { part({ type = pt.INSL, x = x_stack, y = y_char_gen - 4 - i, grvt_cover = params.grvt_cover }) },
				})
			end
			local lsns_filt = part({ type = pt.FILT, x = x_stack, y = y_after_content + 19, ctype = 0x10000003 })
			generic_demuxer(x_stack, y_stack + j % 2 * odd_offset, 0, -1, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to, y_to + 1, 2, false)
			end, false, 1, 0x10000000)
			for i = 0, odd_offset - 1 do
				if j % 2 == 1 and not (i == odd_offset - 1 and j % 4 ~= 3) then
					part({ type = pt.STOR, x = x_stack, y = y_stack - i - 4 + odd_offset })
				end
			end
		end
		local y_bg_source = y_char_gen - char_size - 3
		y_bg_bricks = y_bg_source - 1
		for x = 0, char_size - 1 do
			part({ type = pt.BRCK, x = x_char_gen + x, y = y_bg_bricks })
			for y = 0, char_size - 1 do
				dray(x_char_gen + x, y_bg_source - 2, x_char_gen + x, y_bg_source + y, 1, false)
			end
			dray(x_char_gen + x, y_bg_source - 2, charpipe_1_x + x, charpipe_1_y - 1, char_size + 1, false)
			spark({ type = pt.INWR, x = x_char_gen + x, y = y_bg_source - 3 })
		end
		spark_row(79, y_bg_source - 3, x_char_gen + char_size - 1, y_bg_source - 3, pt.INWR, char_size, 3)

		local x_copy_donor = x_after_content - char_size - 9
		local y_copy_donor = y_bg_source - 2
		for i = 0, char_size - 1 do
			part({ type = pt.HEAC, x = x_copy_donor + i, y = y_copy_donor })
		end
		local x_copy = x_char_gen - 2
		cray(x_copy - 2, y_copy_donor, x_copy_donor, y_copy_donor, pt.SPRK, char_size, pt.PSCN)
		dray_log(x_copy, y_copy_donor, x_copy, y_copy_donor + 2, char_size, pt.PSCN)
		part({ type = pt.DRAY, x = x_copy, y = y_copy_donor + 1, tmp = char_size + 1, tmp2 = chars_w + 9 })
		local y_copy_inwr = y_char_gen - 4
		for i = 0, char_size - 1 do
			spark({ type = pt.INWR, x = x_copy - 1, y = y_copy_inwr - i })
		end
		spark_row(x_copy - 1, y_char_gen - 2, x_copy - 1, y_copy_inwr, pt.INWR, char_size, 4)

		local y_apom_restore = y_after_content - 6
		do
			cray(x_copy, y_apom_restore, x_copy, y_copy_inwr, pt.SPRK, char_size, pt.PSCN)
			local donor = part({ type = pt.HEAC, x = x_copy + 2, y = y_apom_restore })
			part({ type = pt.CRAY, x = x_copy - 4, y = y_apom_restore - 1, ctype = pt.HEAC, tmp = char_size, tmp2 = x_copy_donor - (x_copy - 3) })
			dray(x_copy - 4, y_apom_restore    , x_copy - 4, y_copy_donor, 1, pt.PSCN)
			dray(x_copy - 4, y_apom_restore + 3, x_copy - 4, y_copy_donor, 1, pt.PSCN)
			cray(x_copy - 6, y_apom_restore    , donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
			cray(donor.x   , y_apom_restore + 3, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			lsns_spark({ type = pt.PSCN, x = x_copy - 5, y = y_copy_donor, life = 3 }, 0, -1, 0, -2)
		end

		local x_copy_delete = x_after_content + 10
		local y_copy_delete = -19
		for xx = 0, char_size - 1 do
			cray(x_copy_delete + xx, y_copy_delete + xx % 2 * 3, x_copy_delete + xx, y_content, pt.SPRK, chars_h, pt.PSCN)
			dray_log(x_copy_delete + xx, -1, x_copy_delete + xx, char_size, chars_h - char_size, false)
			spark({ type = pt.INWR, x = x_copy_delete + xx, y = -2, life = 3 })
		end
		spark_row(x_after_content - 5, -2, x_copy_delete, -2, pt.INWR, char_size, 3)

		for i = 0, char_size - 1 do
			local y = y_after_content + 10 + i
			dray_log(-char_size - 1, y, 0, y, chars_w, false)
			spark({ type = pt.INWR, x = -char_size - 2, y = y })
			local conductor = pt.PSCN
			local xx = -char_size - 4 - i % 2 * 3
			if i == 1 then
				conductor = false
				lsns_spark({ type = pt.PSCN, x = xx - 1, y = y, life = 3 }, 1, 0, 1, -1)
			end
			cray(xx, y, 0, y, pt.SPRK, chars_w, conductor)
		end
		spark_row(-char_size - 2, y_after_content + 8, -char_size - 2, y_after_content + 10, pt.INWR, char_size, 3)

		for i = 0, 1 do
			local x = x_char_gen_src - i * 2
			local y = y_stack
			part({ type = pt.FILT, x = x, y = y_char_gen_src, ctype = 0xFFFFFFFF })
			ldtc(x, y - 4, x, y_char_gen_src)
			aray(x, y - 4, 0, -1, pt.METL)
			part({ type = pt.STOR, x = x, y = y - 2 })
			part({ type = pt.FILT, x = x, y = y - 3          , ctype = 0xFFFFFFFF })
			part({ type = pt.FILT, x = x, y = y - 1, tmp =  2, ctype = 0x00000100 })
			part({ type = pt.FILT, x = x, y = y    , tmp =  1, ctype = 0xFFFFFF00 })
			part({ type = pt.FILT, x = x, y = y + 1, tmp = 11, ctype = 0x00000100 })
			for yy = 2, -4 + odd_offset do
				part({ type = pt.STOR, x = x, y = y + yy })
			end
			part({ type = pt.BRAY, x = x, y = y - 3 + odd_offset })
			part({ type = pt.DMND, x = x, y = y - 2 + odd_offset })
		end
	end

	do -- char 0 delivery
		local x = x_after_content + 11
		local y = -6

		ldtc(x, y, x, -18)
		part({ type = pt.FILT, x = x, y = y + 1 })
		dray(x + 1, y + 1, 13, y + 1, 1, pt.PSCN)

		ldtc(x + 3, y, x + 3, -18)
		part({ type = pt.FILT, x = x + 3, y = y + 1 })
		part({ type = pt.FILT, x = x + 3, y = y + 2 })
		dray(x + 4, y + 2, 14, y + 2, 1, false)
		lsns_spark({ type = pt.PSCN, x = x + 5, y = y + 2, life = 3 }, 0, -1, 0, -2)
		part({ type = pt.CONV, x = x + 4, y = y + 1, tmp = pt.INSL, ctype = pt.PSCN })
		part({ type = pt.CONV, x = x + 4, y = y + 1, tmp = pt.PSCN, ctype = pt.SPRK })
	end

	local y_color_grab
	do
		local size                  = math.max(chars_nh, chars_nv)
		local log_size              = misc.ilog2ceil(size)
		local x_color_rom           = 13
		local y_dray_rom            = -13
		local x_spark_row           = -10
		local y_spark_row           = y_dray_rom - 2
		local lsns_filt             = part({ type = pt.FILT, x = -12, y = y_dray_rom - 2, ctype = 0x10000003 })
		local x_bit_filts           = x_after_content + 19
		local x_retract_donor       = x_after_content + 14
		local x_retract_donor_left  = -1
		local x_retract_donor_right = x_after_content + 16
		local y_retract_donor       = y_dray_rom - 1

		local bit_filts = {}
		for i = 0, 7 do
			bit_filts[i] = part({ type = pt.FILT, x = x_bit_filts - i, y = y_dray_rom - 2, ctype = bitx.lshift(1, i) })
		end

		local w_color_rom
		do -- color rom
			local y_color_rom = y_dray_rom
			local csize = #colors
			w_color_rom = csize + 13
			local log_size = misc.ilog2ceil(csize)
			local function color_rom(x, carrier_type, shift, input_x_offset, input)
				assert(x and carrier_type and shift)
				local targets = {}
				for i = 0, log_size - 1 do
					part({ type = pt.PSTN, x = x + i - log_size - 2, y = y_color_rom - 1, extend = bitx.lshift(1, math.max(0, log_size - 2 - i)) })
					table.insert(targets, {
						parts    = { part({ type = pt.INSL, x = x + i - log_size - 2, y = y_color_rom - 2 }) },
						bit_filt = bit_filts[shift + log_size - 1 - i],
					})
				end

				local x_retract = x - log_size - 4
				local y_retract = y_color_rom - 1
				local retract_donor = part({ type = pt.HEAC, x = x_retract_donor, y = y_retract_donor })
				cray(x_retract_donor_left, y_retract_donor, retract_donor.x, retract_donor.y, pt.SPRK, 1, pt.PSCN)
				dray(x_retract_donor_left, y_retract_donor, x_retract, y_retract, 1, pt.PSCN)
				cray(x_retract_donor_right, y_retract_donor, x_retract, y_retract, pt.SPRK, 1, pt.PSCN)
				cray(x_retract_donor_right, y_retract_donor, retract_donor.x, retract_donor.y, retract_donor.type, 1, pt.PSCN)
				x_retract_donor = x_retract_donor - 1

				ldtc(x - log_size - 3 + input_x_offset, y_color_rom - 3, input.x, input.y)
				part ({ type = pt.PSTN, x = x - 2           , y = y_color_rom - 1, extend = 1 })
				part ({ type = pt.PSTN, x = x - log_size - 3, y = y_color_rom - 1, extend = math.huge })
				part ({ type = pt.INSL, x = x - log_size - 5, y = y_color_rom - 1 })
				part ({ type = pt.INSL, x = x + csize + 2   , y = y_color_rom - 1 })
				part ({ type = pt.DMND, x = x - 2, y = y_color_rom - 2 })
				local template = spark({ type = pt.NSCN, x = x - log_size - 4, y = y_color_rom - 2 })
				spark_row(x_spark_row, y_spark_row, template.x, template.y, pt.NSCN, 1, 3)
				solid_spark(x - log_size - 5, y_color_rom,  1, 0, pt.NSCN, true)
				solid_spark(x - log_size - 2, y_color_rom, -1, 0, pt.PSCN, true)
				part ({ type = pt.FRME, x = x - 1, y = y_color_rom - 2 })
				part ({ type = pt.FRME, x = x - 1, y = y_color_rom - 1 })
				spark({ type = pt.PSCN, x = x    , y = y_color_rom - 2 })
				part ({ type = pt.DRAY, x = x    , y = y_color_rom - 1, tmp = 1 })
				part ({ type = pt.CONV, x = x + 1, y = y_color_rom - 1, ctype = pt.PSCN, tmp = pt.SPRK })
				part ({ type = pt.BTRY, x = x + 2, y = y_color_rom - 1 })
				for i = 0, csize - 1 do
					part({ type = carrier_type, x = x + i, y = y_color_rom, dcolour = 0xFF000000 + colors[i + 1] })
				end
				generic_demuxer(x - log_size - 6, y_color_rom - 2, 1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
					dray(x, y, x_to - 1, y_to, 2, false)
				end, true, 20, 0x10000000)
			end
			color_rom(x_color_rom, pt.CRMC, log_size, 1, outputs.char_color)
			color_rom(x_color_rom + w_color_rom, pt.STOR, 0, 0, outputs.char_color_2)
		end

		local x_dray_rom = x_color_rom + w_color_rom * 2 - 4 + log_size
		part({ type = pt.PSTN, x = x_retract_donor_left + 1, y = y_retract_donor, extend = math.huge })
		do -- dray/pstn rom
			for i = 0, size - 1 do
				part({ type = pt.DRAY, x = x_dray_rom + i * 2    , y = y_dray_rom, tmp = 8, tmp2 = 10 + (size - i - 1) * char_size })
				part({ type = pt.PSTN, x = x_dray_rom + i * 2 + 3, y = y_dray_rom, extend = 0, tmp = 6 + (size - i - 1) * char_size })
			end
			local targets = {}
			for i = 0, log_size - 1 do
				part({ type = pt.PSTN, x = x_dray_rom + i - log_size - 2, y = y_dray_rom - 1, extend = bitx.lshift(1, math.max(0, log_size - i - 2) + 1) })
				table.insert(targets, {
					parts    = { part({ type = pt.INSL, x = x_dray_rom + i - log_size - 2, y = y_dray_rom - 2 }) },
					bit_filt = bit_filts[log_size - 1 - i],
				})
			end

			local x_retract = x_dray_rom - log_size - 4
			local y_retract = y_dray_rom - 1
			local retract_donor = part({ type = pt.HEAC, x = x_retract_donor, y = y_retract_donor })
			cray(x_retract_donor_left, y_retract_donor, retract_donor.x, retract_donor.y, pt.SPRK, 1, pt.PSCN)
			dray(x_retract_donor_left, y_retract_donor, x_retract, y_retract, 1, pt.PSCN)
			cray(x_retract_donor_right, y_retract_donor, x_retract, y_retract, pt.SPRK, 1, pt.PSCN)
			cray(x_retract_donor_right, y_retract_donor, retract_donor.x, retract_donor.y, retract_donor.type, 1, pt.PSCN)
			x_retract_donor = x_retract_donor - 1

			ldtc(x_dray_rom - log_size - 3, y_dray_rom - 3, outputs.char_dindex.x, outputs.char_dindex.y)
			part ({ type = pt.PSTN, x = x_dray_rom - 2           , y = y_dray_rom - 1, extend = 1 })
			part ({ type = pt.PSTN, x = x_dray_rom - log_size - 3, y = y_dray_rom - 1, extend = math.huge })
			part ({ type = pt.INSL, x = x_dray_rom - log_size - 5, y = y_dray_rom - 1 })
			part ({ type = pt.INSL, x = x_dray_rom + size * 2 + 4, y = y_dray_rom - 1 })
			part ({ type = pt.DMND, x = x_dray_rom - 2, y = y_dray_rom - 2 })
			local template = spark({ type = pt.NSCN, x = x_dray_rom - log_size - 4, y = y_dray_rom - 2 })
			spark_row(x_spark_row, y_spark_row, template.x, template.y, pt.NSCN, 1, 3)
			solid_spark(x_dray_rom - log_size - 5, y_dray_rom,  1, 0, pt.NSCN, true)
			solid_spark(x_dray_rom - log_size - 2, y_dray_rom, -1, 0, pt.PSCN, true)
			part ({ type = pt.FRME, x = x_dray_rom - 1, y = y_dray_rom - 2 })
			part ({ type = pt.FRME, x = x_dray_rom - 1, y = y_dray_rom - 1 })
			spark({ type = pt.PSCN, x = x_dray_rom    , y = y_dray_rom - 2 })
			part ({ type = pt.BRCK, x = x_dray_rom + 1, y = y_dray_rom - 2 })
			part ({ type = pt.BRCK, x = x_dray_rom + 2, y = y_dray_rom - 2 })
			spark({ type = pt.PSCN, x = x_dray_rom + 3, y = y_dray_rom - 2 })
			part ({ type = pt.DRAY, x = x_dray_rom    , y = y_dray_rom - 1, tmp = 1 })
			part ({ type = pt.DRAY, x = x_dray_rom + 3, y = y_dray_rom - 1, tmp = 1 })
			part ({ type = pt.CONV, x = x_dray_rom + 1, y = y_dray_rom - 1, ctype = pt.PSCN, tmp = pt.SPRK })
			part ({ type = pt.CONV, x = x_dray_rom + 4, y = y_dray_rom - 1, ctype = pt.PSCN, tmp = pt.SPRK })
			part ({ type = pt.BTRY, x = x_dray_rom + 2, y = y_dray_rom - 1 })
			part ({ type = pt.BTRY, x = x_dray_rom + 5, y = y_dray_rom - 1 })
			generic_demuxer(x_dray_rom - log_size - 6, y_dray_rom - 2, 1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to - 1, y_to, 2, false)
			end, true, 20, 0x10000000)
		end

		local x_grab = x_color_rom - 4
		local y_grab = y_dray_rom + 1
		y_color_grab = y_grab
		local x_grab_end = x_after_content + 10
		part({ type = pt.INSL, x = x_grab - 2, y = y_grab })
		part({ type = pt.PSTN, x = x_grab - 1, y = y_grab, extend = math.huge })
		part({ type = pt.PSTN, x = x_grab    , y = y_grab, extend = math.huge })
		part({ type = pt.PSTN, x = x_grab + 1, y = y_grab, extend = 0 })
		part({ type = pt.PSTN, x = x_grab + 2, y = y_grab, extend = 1 })
		part({ type = pt.FRME, x = x_grab + 3, y = y_grab, tmp = 1 })
		part({ type = pt.INSL, x = x_grab_end, y = y_grab })
		dray(x_grab - 3 - log_size, y_grab, x_grab_end - 4, y_grab, 4, pt.PSCN)
		part({ type = pt.HEAC, x = x_grab_end - 1, y = y_grab })
		part({ type = pt.HEAC, x = x_grab_end - 2, y = y_grab })
		part({ type = pt.STOR, x = x_grab_end - 3, y = y_grab })
		part({ type = pt.CRMC, x = x_grab_end - 4, y = y_grab })
		solid_spark(x_grab - 2, y_grab + 1,  1, 0, pt.PSCN, true)
		solid_spark(x_grab + 1, y_grab + 1, -1, 0, pt.NSCN, true)
	end

	for yy = 0, chars_nv - 1 do -- right char pistons
		local y_base = y_content + yy * char_size
		for yyy = 0, char_size - 1 do
			local frame_type = pt.FRME
			if yy > 0 and yyy < 2 then
				frame_type = pt.HEAC
			end
			part({ type = frame_type, x = 5 + x_after_content, y = y_base + yyy })
		end
		if yy > 0 then
			part({ type = pt.CONV, x = 6 + x_after_content, y = y_base, tmp = pt.FRME, ctype = pt.CRMC })
			part({ type = pt.CONV, x = 6 + x_after_content, y = y_base, tmp = pt.HEAC, ctype = pt.FRME })
		end
		local y_piston = y_base + char_size - 1
		part({ type = pt.PSTN, x = 6 + x_after_content, y = y_piston, extend = 0 })
		part({ type = pt.PSTN, x = 7 + x_after_content, y = y_piston, ctype = pt.DMND, extend = 9 })
		part({ type = pt.PSTN, x = 8 + x_after_content, y = y_piston, ctype = pt.DMND, extend = 0, tmp = chars_w - char_size + 6 })
		local target = part({ type = pt.PSTN, x = 9 + x_after_content, y = y_piston, ctype = pt.DMND, extend = 0, tmp = chars_w - char_size + 6 })
		-- no solid_spark because this is more complicated
		part ({ type = pt.CONV, x = 7 + x_after_content, y = y_piston + 1, tmp = pt.SPRK, ctype = pt.PSCN })
		part ({ type = pt.CONV, x = 8 + x_after_content, y = y_piston + 1, tmp = pt.SPRK, ctype = pt.NSCN })
		part ({ type = pt.BTRY, x = 9 + x_after_content, y = y_piston + 3 })
		spark({ type = pt.PSCN, x = 8 + x_after_content, y = y_piston + 1 })
		spark({ type = pt.NSCN, x = 9 + x_after_content, y = y_piston + 1 })
		-- part({ type = pt.DMND, x = -1, y = y_piston })

		dray(9 + x_after_content, y_color_grab - 1, target.x, target.y, 1, pt.PSCN)
		if yy > 0 then
			dray(5 + x_after_content, y_after_content + 9, 5 + x_after_content, y_base + 1, 3, pt.PSCN)
		end
	end
	part({ type = pt.FRME, x = 5 + x_after_content, y = y_after_content + 6 })
	part({ type = pt.HEAC, x = 5 + x_after_content, y = y_after_content + 7 })
	part({ type = pt.HEAC, x = 5 + x_after_content, y = y_after_content + 8 })

	local y_bottom_char_piston
	for xx = 0, chars_nh - 1 do -- bottom char pistons
		local x_base = x_content + xx * char_size
		for xxx = 0, char_size - 1 do
			local frame_type = pt.FRME
			if xx < chars_nh - 1 and xxx == char_size - 1 then
				frame_type = pt.HEAC
			end
			local frame = part({ type = frame_type, x = x_base + xxx, y = y_after_content + 5 })
			if xx > 0 and xxx == 0 then
				cray(frame.x + 2, frame.y + 3, frame.x - 1, frame.y, pt.HEAC, 1, pt.PSCN)
				cray(frame.x + 2, frame.y + 3, frame.x - 1, frame.y, pt.HEAC, 1, pt.PSCN)
				cray(frame.x + 3, frame.y + 3, frame.x    , frame.y, pt.FRME, 1, pt.PSCN)
				cray(frame.x + 3, frame.y + 3, frame.x    , frame.y, pt.FRME, 1, pt.PSCN)
			end
		end
		local x_piston = x_base + char_size - 1
		part({ type = pt.PSTN, x = x_piston, y = 6 + y_after_content, extend = 0 })
		part({ type = pt.PSTN, x = x_piston, y = 7 + y_after_content, ctype = pt.DMND, extend = 9 })
		part({ type = pt.PSTN, x = x_piston, y = 8 + y_after_content, ctype = pt.DMND, extend = 0, tmp = chars_h - char_size + 6 })
		part({ type = pt.CONV, x = x_piston, y = 8 + y_after_content, tmp = pt.SPRK, ctype = pt.NSCN })
		part({ type = pt.CONV, x = x_piston, y = 8 + y_after_content, tmp = pt.NSCN, ctype = pt.SPRK })
		part({ type = pt.LSNS, x = x_piston, y = 8 + y_after_content, tmp = 3 })
		part({ type = pt.FILT, x = x_piston, y = 9 + y_after_content, ctype = 0x10000000 })
		local target = part({ type = pt.PSTN, x = x_piston, y = 8 + y_after_content, ctype = pt.DMND, extend = 0, tmp = chars_h - char_size + 6 })
		solid_spark(x_piston - 1, 9 + y_after_content, -1, -1, pt.NSCN, true)
		solid_spark(x_piston + 1, 8 + y_after_content,  0,  0, pt.PSCN, true)
		y_bottom_char_piston = target.y

		dray(-2, target.y, target.x, target.y, 1, pt.PSCN)
		if xx > 0 then
			dray(x_after_content + 7, y_after_content + 5, x_base, y_after_content + 5, 2, pt.PSCN)
		end
	end
	part({ type = pt.HEAC, x = x_after_content + 6, y = y_after_content + 5 })
	part({ type = pt.FRME, x = x_after_content + 5, y = y_after_content + 5 })

	do -- cray rom
		local size                  = math.max(chars_nh, chars_nv)
		local log_size              = misc.ilog2ceil(size)
		local x_cray_rom            = 87 + log_size
		local y_cray_rom            = -8
		local x_spark_row           = -10
		local y_spark_row           = y_cray_rom - 2
		local lsns_filt             = part({ type = pt.FILT, x = -12, y = y_cray_rom - 2, ctype = 0x10000003 })
		local x_bit_filts           = x_after_content + 19
		local x_retract_donor       = x_after_content + 14
		local x_retract_donor_left  = -1
		local x_retract_donor_right = x_after_content + 16
		local y_retract_donor       = y_cray_rom - 1

		part({ type = pt.PSTN, x = x_retract_donor_left + 1, y = y_retract_donor, extend = math.huge })
		local w_dray_rom
		w_dray_rom = size * 2
		for i = 0, size - 1 do
			part({ type = pt.CRAY, x = x_cray_rom + i - 1, y = y_cray_rom    , tmp = 8, tmp2 = (size - i - 1) * 8    , ctype = pt.SPRK })
			part({ type = pt.CRAY, x = x_cray_rom + i - 2, y = y_cray_rom + 1, tmp = 8, tmp2 = (size - i - 1) * 8 + 3, ctype = pt.SPRK })
		end
		local targets = {}
		for i = 0, log_size - 1 do
			part({ type = pt.PSTN, x = x_cray_rom + i - log_size - 2, y = y_cray_rom - 1, extend = bitx.lshift(1, math.max(0, log_size - i - 2)) })
			table.insert(targets, {
				parts    = { part({ type = pt.INSL, x = x_cray_rom + i - log_size - 2, y = y_cray_rom - 2 }) },
				bit_filt = part({ type = pt.FILT, x = x_bit_filts - i, y = y_cray_rom - 2, ctype = bitx.lshift(1, log_size - 1 - i) }),
			})
		end

		local x_retract = x_cray_rom - log_size - 4
		local y_retract = y_cray_rom - 1
		local retract_donor = part({ type = pt.HEAC, x = x_retract_donor, y = y_retract_donor })
		cray(x_retract_donor_left, y_retract_donor, retract_donor.x, retract_donor.y, pt.SPRK, 1, pt.PSCN)
		dray(x_retract_donor_left, y_retract_donor, x_retract, y_retract, 1, pt.PSCN)
		cray(x_retract_donor_right, y_retract_donor, x_retract, y_retract, pt.SPRK, 1, pt.PSCN)
		cray(x_retract_donor_right, y_retract_donor, retract_donor.x, retract_donor.y, retract_donor.type, 1, pt.PSCN)
		x_retract_donor = x_retract_donor - 1

		ldtc(x_cray_rom - log_size - 3, y_cray_rom - 3, outputs.char_cindex.x, outputs.char_cindex.y)
		part ({ type = pt.PSTN, x = x_cray_rom - 2           , y = y_cray_rom - 1, extend = 1 })
		part ({ type = pt.PSTN, x = x_cray_rom - log_size - 3, y = y_cray_rom - 1, extend = math.huge })
		part ({ type = pt.INSL, x = x_cray_rom - log_size - 5, y = y_cray_rom - 1 })
		part ({ type = pt.INSL, x = x_cray_rom + size     + 2, y = y_cray_rom - 1 })
		part ({ type = pt.DMND, x = x_cray_rom - 2, y = y_cray_rom - 2 })
		local template = spark({ type = pt.NSCN, x = x_cray_rom - log_size - 4, y = y_cray_rom - 2 })
		spark_row(x_spark_row, y_spark_row, template.x, template.y, pt.NSCN, 1, 3)
		solid_spark(x_cray_rom - log_size - 5, y_cray_rom,  1, 0, pt.NSCN, true)
		solid_spark(x_cray_rom - log_size - 2, y_cray_rom, -1, 0, pt.PSCN, true)
		part ({ type = pt.FRME, x = x_cray_rom - 1, y = y_cray_rom - 2 })
		part ({ type = pt.FRME, x = x_cray_rom - 1, y = y_cray_rom - 1 })
		part ({ type = pt.BRCK, x = x_cray_rom    , y = y_cray_rom - 2 })
		spark({ type = pt.PSCN, x = x_cray_rom + 1, y = y_cray_rom - 2 })
		part ({ type = pt.DRAY, x = x_cray_rom    , y = y_cray_rom - 1, tmp = 2 })
		part ({ type = pt.CONV, x = x_cray_rom + 1, y = y_cray_rom - 1, ctype = pt.PSCN, tmp = pt.SPRK })
		part ({ type = pt.BTRY, x = x_cray_rom + 2, y = y_cray_rom - 1 })
		generic_demuxer(x_cray_rom - log_size - 6, y_cray_rom - 2, 1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
			dray(x, y, x_to - 1, y_to, 2, false)
		end, true, 20, 0x10000000)

		local x_grab = x_cray_rom - 8
		local y_grab = y_cray_rom + 2
		local x_grab_end = x_after_content + 8
		part({ type = pt.INSL, x = x_grab - 1, y = y_grab     })
		part({ type = pt.PSTN, x = x_grab    , y = y_grab    , extend = math.huge })
		part({ type = pt.PSTN, x = x_grab + 1, y = y_grab    , extend = math.huge })
		part({ type = pt.PSTN, x = x_grab + 2, y = y_grab    , extend = 1 })
		part({ type = pt.FRME, x = x_grab + 3, y = y_grab    , tmp = 1 })
		part({ type = pt.FRME, x = x_grab + 4, y = y_grab    , tmp = 1 })
		part({ type = pt.FRME, x = x_grab + 3, y = y_grab + 1, tmp = 1 })
		part({ type = pt.INSL, x = x_grab_end, y = y_grab })
		part({ type = pt.HEAC, x = x_grab_end - 1, y = y_grab     })
		part({ type = pt.HEAC, x = x_grab_end - 2, y = y_grab + 1 })
		solid_spark(x_grab - 1, y_grab + 1,  1, 0, pt.PSCN, true)
		solid_spark(x_grab + 2, y_grab + 1, -1, 0, pt.NSCN, true)
		dray(x_grab_end, y_grab - 1, right_cray_first.x, right_cray_first.y, 1, pt.PSCN)
		dray(x_grab_end, y_grab - 1, right_cray_first.x + 4, right_cray_first.y - 4, 2, pt.PSCN)
		part({ type = pt.CONV, x = x_grab_end, y = y_grab - 1, tmp = pt.CRAY, ctype = pt.INSL })
		dray(x_grab_end, y_grab - 1, x_grab_end - 2, y_grab + 1, 1, pt.PSCN)
		cray(x_grab_end, y_grab - 1, x_grab_end - 1, y_grab, pt.SPRK, 2, pt.PSCN)
		part({ type = pt.HEAC, x = right_cray_first.x + 3, y = right_cray_first.y - 3 })
		part({ type = pt.HEAC, x = right_cray_first.x + 4, y = right_cray_first.y - 4 })
		part({ type = pt.FILT, x = right_cray_first.x + 3, y = right_cray_first.y - 2 })
		dray    (right_cray_first.x    , right_cray_first.y - 2, right_cray_first.x    , y_after_content - 1, 2, pt.PSCN)
		dray_log(right_cray_first.x    , right_cray_first.y - 2, right_cray_first.x    , right_cray_first.y + 1, chars_h - 2, pt.PSCN)
		dray_log(right_cray_first.x + 3, right_cray_first.y - 4, right_cray_first.x + 3, right_cray_first.y - 1, chars_h    , pt.PSCN)
		dray    (right_cray_first.x + 3, right_cray_first.y - 4, right_cray_first.x + 3, y_after_content + 3, 1, pt.PSCN)

		for rank = 0, 1 do
			local y = y_after_content + rank * 3
			part({ type = pt.HEAC, x = right_cray_first.x + rank * 3, y = y })
			local former = part({ type = pt.HEAC, x = -4, y = y })
			local latter = part({ type = pt.ARAY, x = right_cray_first.x + rank * 3 + 1, y = y })
			solid_spark(right_cray_first.x + rank * 3 + 3, y, -1, 0, pt.PSCN, true)
			cray(x_after_content + 16, y, latter.x, latter.y, pt.ARAY, 1, pt.PSCN)
			cray(x_after_content + 16, y, former.x, former.y, pt.HEAC, 1, pt.PSCN)
			cray(x_after_content + 16, y, latter.x, latter.y, pt.ARAY, 1, pt.PSCN)
			cray(-6, y, latter.x, latter.y, pt.SPRK, 1, pt.PSCN)
			cray(-6, y, former.x, former.y, pt.SPRK, 1, pt.PSCN)
			dray(-6, y, latter.x, latter.y, 1, pt.PSCN)
			part({ type = pt.DRAY, x = -5, y = y, tmp = 1, tmp2 = chars_w - 1 + rank * 4, z = 1001 })
			part({ type = rank == 1 and pt.HEAC or pt.FILT, x = -1, y = y })
			dray_log(-2, y, 1, y, chars_w - 1, pt.PSCN)
		end
	end

	local piston_last
	do -- fg color delivery
		local x_fg_source = x_after_content + 7
		local y_target    = 4
		local y_ecopy     = y_color_grab - 1

		for j, y in ipairs({
			y_char_gen_fg,
			y_char_gen_fg + y_char_gen_odd_offset,
		}) do
			for i = 0, char_size - 1, 2 do
				dray(x_fg_source + 1, y, x_char_gen + i + j - 1, y, 1, pt.PSCN)
				part({ type = pt.STOR, x = x_fg_source, y = y })
			end
			dray(x_fg_source, y_target - 1, x_fg_source, y, 1, pt.PSCN)
		end

		local y_fg_last = y_ecopy + 11
		part ({ type = pt.DMND, x = x_fg_source - 1, y = y_ecopy + 10 })
		piston_last = part({ type = pt.HEAC, x = x_fg_source + 6, y = y_ecopy + 6 })

		dray(x_fg_source, y_ecopy, piston_last.x, piston_last.y, 1, pt.PSCN)
		dray(x_fg_source, y_ecopy, copier_last.x, copier_last.y, 1, pt.PSCN)
	end

	do -- bg color delivery
		local x_bg_del = x_after_content + 6
		local y_bg_del = y_color_grab
		for x = 0, char_size - 1 do
			dray(x_bg_del + 1, y_bg_bricks, x_char_gen + x, y_bg_bricks, 1, pt.PSCN)
		end
	end

	do
		local y_before = -19
		local y_after = 27
		for i, offsets in ipairs({
			{ lsx = -1, lss = -1, target = -1 },
			{ lsx =  1, lss =  2, target =  4 },
		}) do
			local x = x_after_content + 5 + i
			part({ type = pt.DRAY, x = x, y = y_before + 1, tmp = 4, tmp2 = offsets.target - y_before - 11 })
			local donor = part({ type = pt.HEAC, x = x, y = y_color_grab + 1 })
			lsns_spark({ type = pt.INWR, x = x, y = y_before + 2, life = 3 }, offsets.lsx, 0, offsets.lss, 1)
			cray(x, y_before, donor.x, donor.y, pt.HEAC, 1, false, 1000)
			dray(x, y_before, x, y_before + 3, 1, false, 1001)
			cray(x, y_after, x, y_before + 3, pt.SPRK, 1, false, 1000)
			cray(x, y_after, donor.x, donor.y, pt.HEAC, 1, false, 1001)
			part({ type = pt.CRAY, x = x, y = y_after, ctype = pt.SPRK, tmp = 1, tmp2 = y_after - offsets.target - 1, z = 1002 })
		end
		for i, offsets in ipairs({
			{ spy = -1, target = y_before },
			{ spy =  1, target = y_after  },
		}) do
			local x = x_after_content + 6
			spark({ type = pt.PSCN, x = x    , y = offsets.target + offsets.spy })
			part ({ type = pt.CRMC, x = x + 1, y = offsets.target + offsets.spy })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.SPRK, ctype = pt.INSL, z =  900 })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.CRMC, ctype = pt.PSCN, z =  901 })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.PSCN, ctype = pt.SPRK, z =  902 })
			part ({ type = pt.LSNS, x = x + 1, y = offsets.target, tmp = 3,                        z =  903 })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.SPRK, ctype = pt.CRMC, z = 1100 })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.INSL, ctype = pt.PSCN, z = 1101 })
			part ({ type = pt.CONV, x = x + 1, y = offsets.target, tmp = pt.PSCN, ctype = pt.SPRK, z = 1102 })
			part ({ type = pt.FILT, x = x + 2, y = offsets.target, ctype = 0x10000003 })
		end
	end

	do
		local x = -4
		local y = y_bottom_char_piston
		local target = part({ type = pt.HEAC, x = 9 + x_after_content, y = y })
		dray(9 + x_after_content, y_color_grab - 1, target.x, target.y, 1, pt.PSCN)
		local donor = part({ type = pt.HEAC, x = x, y = y })
		part({ type = pt.BRCK, x = x + 3, y = y })
		part({ type = pt.DRAY, x = x - 1, y = y, tmp = 1, tmp2 = target.x })
		cray(x - 2, y, donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
		dray(x - 2, y, target.x + 1, target.y, 1, pt.PSCN)
		solid_spark(target.x + 3, target.y, -1, 0, pt.PSCN, true)
		cray(target.x + 5, target.y, target.x + 1, target.y, pt.SPRK, 1, pt.PSCN)
		cray(target.x + 5, target.y, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
	end
	do	
		local x = -4
		local y = y_after_content + 18
		local target = part({ type = pt.HEAC, x = piston_last.x, y = y })
		dray(piston_last.x, piston_last.y - 1, target.x, target.y, 1, pt.PSCN)
		local donor = part({ type = pt.HEAC, x = x, y = y })
		part({ type = pt.DRAY, x = x - 1, y = y, tmp = 1, tmp2 = target.x })
		cray(x - 2, y, donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
		dray(x - 2, y, target.x + 1, target.y, 1, pt.PSCN)
		solid_spark(target.x + 3, target.y, -1, 0, pt.PSCN, true)
		cray(target.x + 5, target.y, target.x + 1, target.y, pt.SPRK, 1, pt.PSCN)
		cray(target.x + 5, target.y, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
	end

	for yy = 0, chars_h - 1 do -- right char copiers
		spark({ type = pt.INWR, x = x_after_content + 19, y = y_content + yy })
	end
	for yy = 0, chars_h - 1 + right_char_copy_space do -- right char copiers
		part({ type = pt.INSL, x = x_after_content + 18, y = y_content + yy + char_size - 1 - right_char_copy_space })
	end
	for xx = 0, chars_w - 1 do -- bottom char copiers
		part({ type = pt.INSL, x = x_content + xx, y = y_after_content + 18 })
		spark({ type = pt.INWR, x = x_content + xx, y = y_after_content + 19 })
	end

	do -- last horizontal cray fixup
		local x = -9
		local y = y_after_content - 1
		local y_before = 22
		local donor = part({ type = pt.HEAC, x = x, y = y + 1 })
		part({ type = pt.DRAY, x = x, y = y_before - 1, tmp = 1, tmp2 = chars_w + 8 })
		cray(x, y_before - 2, donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
		dray(x, y_before - 2, x, y, 1, pt.PSCN)
		spark({ type = pt.PSCN, x = x - 1, y = y, life = 3 })
		part ({ type = pt.INSL, x = x + 1, y = y })
		part ({ type = pt.LSNS, x = x - 1, y = y - 1, tmp = 3 })
		part ({ type = pt.FILT, x = x - 1, y = y - 2, ctype = 0x10000003 })
		cray(x, y + 3, x, y, pt.SPRK, 1, pt.PSCN)
		cray(x, y + 3, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
	end

	if single_pixel then -- 1px plotter dray bank
		local x = -6
		local y = char_size + 19
		local log_size = misc.ilog2ceil(chars_w)
		local rows = chars_w / 4
		local log_rows = misc.ilog2ceil(rows)
		local x_piston = x + 3
		local x_demux = x_piston + 2
		local y_piston = y + rows + 2
		for yy = 0, rows - 1 do
			for xx = 0, 3 do
				part({ type = pt.DRAY, x = x_piston + xx - 4, y = y + yy, tmp = 1, tmp2 = yy * 4 + xx + 17 })
			end
		end
		do
			local lsns_filt = part({ type = pt.FILT, x = x_demux, y = y_piston - 12, ctype = 0x10000003, unstack = true })
			local targets = {}
			local y_bit_filt = y_after_content + 7
			for i = log_rows - 1, 0, -1 do
				part({ type = pt.PSTN, x = x_piston, y = y_piston + log_rows - i - 1, tmp = 2, extend = bitx.lshift(1, math.max(0, log_rows - i - 2)) })
				table.insert(targets, {
					parts    = { part({ type = pt.INSL, x = x_demux, y = y_piston + log_rows - i - 1 }) },
					bit_filt = part({ type = pt.FILT, x = x_demux, y = y_bit_filt, ctype = bitx.lshift(8, log_rows - i - 1) }),
				})
				y_bit_filt = y_bit_filt - 1
				while y_bit_filt == y_after_content + 4 or
				      y_bit_filt == y_after_content + 3 or
				      y_bit_filt == y_after_content + 1 or
				      y_bit_filt == y_after_content     do
					y_bit_filt = y_bit_filt - 1
				end
			end
			part ({ type = pt.PSTN, x = x_piston, y = y_piston - 1, tmp = 2, extend = 1 })
			part ({ type = pt.PSTN, x = x_piston, y = y_piston + log_rows + 1, tmp = 2, extend = math.huge })
			part ({ type = pt.FRME, x = x_piston, y = y_piston - 2 })
			part ({ type = pt.FRME, x = x_piston + 1, y = y_piston - 2 })
			spark({ type = pt.PSCN, x = x_piston + 1, y = y_piston - 3 })
			part ({ type = pt.DMND, x = x_demux, y = y_piston + log_rows })
			solid_spark(x_demux, y_piston - 6, 0, 0, pt.NSCN, true)
			ldtc(x_demux, y_piston - 15, outputs.pixel_xindex.x, outputs.pixel_xindex.y)
			dray(x_demux, y_piston - 15, x_demux, y_piston - 5, 1, pt.PSCN)
			part({ type = pt.FILT, x = x_demux, y = y_piston - 14, ctype = outputs.pixel_xindex.ctype, tmp = 1 })
			generic_demuxer(x_demux, y_piston - 8, 0, 1, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to, y_to - 1, 2, false)
			end, true, 20, outputs.pixel_xindex.ctype)
		end
		part({ type = pt.LSNS, x = x_demux, y = y_piston - 4, tmp = 3 })
		part({ type = pt.STOR, x = x_demux, y = y_piston - 4 })
		part({ type = pt.FILT, x = x_demux, y = y_piston - 3, ctype = 0x10000003 })
		part({ type = pt.FILT, x = x_demux, y = y_piston - 2 })
		part({ type = pt.FILT, x = x_demux, y = y_piston - 1 })
		solid_spark(x_piston - 1, y_piston + log_rows + 1, 0, -1, pt.PSCN, true)
		solid_spark(x_piston - 1, y_piston + log_rows + 3, 1,  0, pt.NSCN, true)

		do -- 4px selector
			local y_before = -6
			local y_after = y_after_content + 5
			part({ type = pt.PSTN, x = x_piston, y = y_before + 1, tmp = 2, extend = math.huge })
			local copy_donor = part({ type = pt.HEAC, x = x_piston, y = y_piston + log_rows })
			local extend_donor = part({ type = pt.HEAC, x = x_piston, y = y_piston - 3 })
			cray(x_piston, y_before, copy_donor.x, copy_donor.y, pt.HEAC, 1, pt.PSCN)
			cray(x_piston, y_before, extend_donor.x, extend_donor.y, pt.HEAC, 1, pt.PSCN)
			dray(x_piston, y_before, x_piston, y_piston + log_rows, 1, pt.PSCN)
			cray(x_piston, y_before, x_piston, y_piston - 3, pt.DRAY, 1, pt.PSCN)
			cray(x_piston, y_after, x_piston, y_piston + log_rows, pt.SPRK, 1, pt.PSCN)
			cray(x_piston, y_after, x_piston, y_piston - 3, pt.SPRK, 1, pt.PSCN)
			cray(x_piston, y_after, copy_donor.x, copy_donor.y, pt.HEAC, 1, pt.PSCN)
			cray(x_piston, y_after, extend_donor.x, extend_donor.y, pt.HEAC, 1, pt.PSCN)
		end

		do -- push up
			for i = 0, 3 do
				part({ type = pt.FRME, x = x_piston - 8 + i, y = y_piston - 2 })
			end
			local y_before = -8
			local y_after = y_after_content + 5
			part({ type = pt.PSTN, x = x_piston - 5, y = y_piston - 1 })
			part({ type = pt.PSTN, x = x_piston - 5, y = y_before + 1, tmp = 1, extend = math.huge })
			part({ type = pt.PSTN, x = x_piston - 5, y = y_before + 2, tmp = 2, extend = math.huge })
			local donor_1 = part({ type = pt.HEAC, x = x_piston - 5, y = y_after - 4 })
			                part({ type = pt.HEAC, x = x_piston - 5, y = y_after - 3 })
			cray(x_piston - 5, y_before, donor_1.x, donor_1.y, pt.HEAC, 2, pt.PSCN)
			dray(x_piston - 5, y_before, x_piston - 5, y_piston, 2, pt.PSCN)
			cray(x_piston - 5, y_after, x_piston - 5, y_piston + 1, pt.SPRK, 2, pt.PSCN)
			cray(x_piston - 5, y_after, donor_1.x, donor_1.y + 1, pt.HEAC, 2, pt.PSCN)
			spark({ type = pt.NSCN, x = x_piston - 4, y = y_piston     })
			spark({ type = pt.PSCN, x = x_piston - 4, y = y_piston + 1 })
			part ({ type = pt.FILT, x = x_piston - 3, y = y_piston    , ctype = 0x10000003 })
			part ({ type = pt.LSNS, x = x_piston - 3, y = y_piston + 1, tmp = 3 })
		end

		local y_push_left_end
		do -- push left
			local lsns_filt = part({ type = pt.FILT, x = -17, y = y - 3, ctype = 0x10000003 })
			local targets = {}
			local xs_pstn = { [ 0 ] =  1, [ 1 ] = 3, [ 2 ] = 4 }
			local xs_filt = { [ 0 ] = -2, [ 1 ] = 0, [ 2 ] = 2 }
			for i = 0, 2 do
				part({ type = pt.PSTN, x = x + xs_pstn[i], y = y - 1, tmp = 5, extend = bitx.lshift(1, math.max(0, i - 1)) })
				table.insert(targets, {
					parts    = { part({ type = pt.INSL, x = x + xs_pstn[i], y = y - 3 }) },
					bit_filt = part({ type = pt.FILT, x = x + xs_filt[i], y = y - 3, ctype = bitx.lshift(1, i) }),
				})
			end
			for i = 0, 4 do
				part({ type = pt.CRMC, x = x - 6 + i, y = y - 1 })
			end
			part({ type = pt.INSL, x = x - 11, y = y - 1 })
			part({ type = pt.INSL, x = x - 2, y = y - 2 })
			part({ type = pt.DMND, x = x + 5, y = y - 3 })
			part({ type = pt.STOR, x = x - 1, y = y - 3 })
			part({ type = pt.STOR, x = x - 3, y = y - 3 })
			part({ type = pt.PSTN, x = x - 1, y = y - 1, extend = 1 })
			part({ type = pt.PSTN, x = x + 2, y = y - 1 })
			part({ type = pt.PSTN, x = x    , y = y - 1 })
			solid_spark(x - 5, y - 3, 0, 0, pt.PSCN, true)
			local source = part({ type = pt.FILT, x = x - 4, y = y + rows + 6, ctype = 0x3FFFFFFF })
			local source_prev = part({ type = pt.FILT, x = x - 4, y = y - 11, ctype = source.ctype })
			part({ type = pt.LDTC, x = x - 3, y = y + rows + 5, life = 7 })
			ldtc(x - 4, y - 4, source_prev.x, source_prev.y)
			ldtc(x - 4, source_prev.y + 1, source.x, source.y)
			generic_demuxer(x - 7, y - 3, 1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to - 1, y_to, 2, false)
			end, true, 20, source.ctype)

			local y_before = -6
			local y_after = 32
			y_push_left_end = y_after
			local donor = part({ type = pt.HEAC, x = x + 5, y = y_after - 1 })
			cray(x + 5, y_before, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			dray(x + 5, y_before, x + 5, y - 1, 1, pt.PSCN)
			part({ type = pt.PSTN, x = x + 5, y = y_before + 1, extend = math.huge, tmp = 5 })
			cray(x + 5, y_after, x + 5, y - 1, pt.SPRK, 1, pt.PSCN)
			cray(x + 5, y_after, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			spark({ type = pt.NSCN, x = x + 5, y = y })
			part ({ type = pt.LSNS, x = x + 5, y = y + 1, tmp = 3 })
			part ({ type = pt.FILT, x = x + 5, y = y + 2, ctype = 0x10000003 })
		end

		do -- get plot dray
			local y_before = -6
			local y_after = y_push_left_end - 1
			local donor = part({ type = pt.HEAC, x = x - 6, y = y_after - 1 })
			cray(x - 6, y_before, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			dray(x - 6, y_before, x - 6, y - 5, 1, pt.PSCN)
			part({ type = pt.DRAY, x = x - 6, y = y_before + 1, tmp = 4, tmp2 = chars_h - 31 })
			cray(x - 6, y_after, x - 6, y - 5, pt.SPRK, 1, pt.PSCN)
			cray(x - 6, y_after, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			lsns_spark({ type = pt.PSCN, x = x - 6, y = y - 6, life = 3 }, 0, -1, 1, -2)
		end

		cray(x - 5, y + rows + 1, x - 5, y - 1, pt.SPRK, 1, pt.PSCN)
		cray(x - 4, y + rows + 4, x - 4, y - 1, pt.SPRK, 1, pt.PSCN)
		cray(x - 3, y + rows + 1, x - 3, y - 1, pt.SPRK, 1, pt.PSCN)
		cray(x - 2, y + rows + 5, x - 2, y - 1, pt.SPRK, 1, pt.PSCN)
	end

	if single_pixel then -- 1px plotter arm
		local log_size = misc.ilog2ceil(chars_h)
		local x = -17
		local y = y_after_content + 1
		local lsns_filt = part({ type = pt.FILT, x = x, y = -16, ctype = 0x10000003 })
		local targets = {}
		for i = 0, log_size - 1 do
			part({ type = pt.PSTN, x = x - 1, y = y + i + 1, tmp = 2, extend = bitx.lshift(1, math.max(0, i - 1)) })
			table.insert(targets, {
				parts    = { part({ type = pt.INSL, x = x, y = y + i + 1 }) },
				bit_filt = part({ type = pt.FILT, x = x, y = y_after_content + 19 - i, ctype = bitx.lshift(1, i) }),
			})
		end
		part ({ type = pt.DMND, x = x, y = y + log_size + 1 })
		part ({ type = pt.FRME, x = x - 2, y = y - 1 })
		part ({ type = pt.LSNS, x = x - 3, y = y - 1, tmp = 3 })
		part ({ type = pt.FILT, x = x - 3, y = y    , ctype = 0x10000003 })
		part ({ type = pt.FRME, x = x - 3, y = y - 1 })
		spark({ type = pt.PSCN, x = x - 3, y = y - 2, life = 3 })
		solid_spark(x + 1, y - 1, -1, 0, pt.NSCN, true)
		part({ type = pt.PSTN, x = x - 1, y = y, tmp = 2, extend = 1 })
		part({ type = pt.PSTN, x = x - 1, y = y + log_size + 2, tmp = 2, extend = math.huge })
		solid_spark(x - 1, y + log_size + 5, 0, -1, pt.NSCN, true)
		solid_spark(x - 3, y + log_size + 2, 0, -1, pt.PSCN, true)
		local source = part({ type = pt.FILT, x = outputs.pixel_yindex.x, y = y, ctype = outputs.pixel_yindex.ctype })
		ldtc(outputs.pixel_yindex.x, y - 1, outputs.pixel_yindex.x, outputs.pixel_yindex.y, 1000)
		ldtc(x + 1, y, source.x, source.y)
		generic_demuxer(x, y - 3, 0, 1, targets, lsns_filt, function(x, y, x_to, y_to)
			dray(x, y, x_to, y_to - 1, 2, false)
		end, true, 20, source.ctype)

		do -- extend piston
			local donor = part({ type = pt.HEAC, x = x - 1, y = y - 1 })
			local y_before = -14
			local y_after = y_after_content + 18
			cray(x - 1, y_before, donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
			dray(x - 1, y_before, x - 1, y + log_size + 1, 1, pt.PSCN)
			cray(x - 1, y_before, donor.x, donor.y, pt.FRME, 1, pt.PSCN)
			part({ type = pt.PSTN, x = x - 1, y = y_before + 1, tmp = 2, extend = math.huge })
			cray(x - 1, y_after, donor.x, donor.y, pt.FRME, 1, pt.PSCN)
			cray(x - 1, y_after, x - 1, y + log_size + 1, pt.HEAC, 1, pt.PSCN)
			cray(x - 1, y_after, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
		end

		do -- plot dray
			local donor = part({ type = pt.HEAC, x = x - 2, y = y + log_size + 2 })
			local y_before = -11
			local y_after = y_after_content + 15
			cray(x - 2, y_before, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			cray(x - 2, y_before, x - 2, y - 2, pt.HEAC, 1, pt.PSCN)
			cray(x - 2, y_after, x - 2, y - 2, pt.HEAC, 1, pt.PSCN)
			cray(x - 2, y_after, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
		end

		local target = part ({ type = pt.CRMC, x = x - 1, y = y - 2 })
		part({ type = pt.DMND, x = -6, y = target.y - 1 })
		part({ type = pt.DMND, x = -6, y = target.y - 2 })
		-- part({ type = pt.CONV, x = -5, y = target.y, tmp = pt.CRMC, ctype = pt.GLAS }) -- debugging
		dray(-5, target.y, target.x, target.y, 1, pt.PSCN)
		cray(-5, target.y, -6, target.y, pt.SPRK, 1, pt.PSCN)
		dray(-6, -2, -6, target.y, 1, false)

		dray(x + 6, y - 2, x - 2, y - 2, 1, false)
		part({ type = pt.CRMC, x = x + 5, y = y - 2 })
		part({ type = pt.FILT, x = x + 5, y = y - 4 })
	end

	do -- character rom
		local x_char_rom = 13
		local y_char_rom = 0
		local bank_offset = 1
		local size = #font
		assert(size == 256)
		for y = 0, 7 do
			for x = 0, 63 do
				local row = font[(3 - math.floor(y / 2)) * 64 + x + 1]
				local data = 0
				for j = 0, 7 do
					for i = 0, 3 do
						local row_bit = i % 2 * 2 + math.floor(i / 2) + 4 - y % 2 * 4
						data = bitx.bor(data, bitx.lshift(bitx.band(bitx.rshift(row[8 - j], row_bit), 1), j + i * 8))
					end
				end
				local ctype = bitx.bxor(0xFFFFFFFF, data)
				part({ type = pt.FILT, x = x_char_rom + x + y % 2 * bank_offset, y = y_char_rom + y - 11, ctype = ctype })
			end
		end
		solid_spark(x_char_rom - 11, y_char_rom - 3,  1, -1, pt.NSCN, true)
		solid_spark(x_char_rom -  8, y_char_rom - 1, -1,  0, pt.PSCN, true)
		do
			local target = spark({ type = pt.NSCN, x = x_char_rom - 10, y = y_char_rom - 1 })
			spark_row(x_char_rom + 66, y_char_rom - 1, target.x, target.y, pt.INWR, 1, 3)
		end
		part({ type = pt.LDTC, x = x_char_rom              , y = y_char_rom - 3, tmp = 1, life = 1 })
		part({ type = pt.LDTC, x = x_char_rom + bank_offset, y = y_char_rom - 2, tmp = 1, life = 1 })
		local output_1 = part({ type = pt.FILT, x = x_char_rom              , y = y_char_rom - 2 })
		local output_2 = part({ type = pt.FILT, x = x_char_rom + bank_offset, y = y_char_rom - 1 })
		for i = 1, bank_offset do
			if i > 1 then
				part({ type = pt.BRCK, x = x_char_rom + i - 1, y = y_char_rom - 2 })
			end
			part({ type = pt.BRCK, x = x_char_rom + i - 1, y = y_char_rom - 1 })
		end
		part({ type = pt.FRME, x = x_char_rom -  1, y = y_char_rom - 1 })
		part({ type = pt.FRME, x = x_char_rom -  1, y = y_char_rom - 2 })
		part({ type = pt.FRME, x = x_char_rom -  1, y = y_char_rom - 3 })
		for i = 0, 6 do
			part({ type = pt.PSTN, x = x_char_rom - 2 - i, y = y_char_rom - 3, extend = bitx.lshift(1, math.max(0, i - 2)) })
		end
		part({ type = pt.PSTN, x = x_char_rom -  9, y = y_char_rom - 3, extend = math.huge })
		part({ type = pt.INSL, x = x_char_rom - 11, y = y_char_rom - 3 })
		part({ type = pt.INSL, x = x_char_rom + 64, y = y_char_rom - 3 })

		local default_char = 0x42
		do -- demuxer
			part({ type = pt.DMND, x = x_char_rom - 2, y = y_char_rom - 4 })
			local lsns_filt = part({ type = pt.FILT, x = x_char_rom - 28, y = y_char_rom - 4, ctype = 0x10000003, unstack = true })
			local targets = {}
			for i = 0, 5 do
				table.insert(targets, {
					parts    = { part({ type = pt.INSL, x = x_char_rom - 8 + i, y = y_char_rom - 4 }) },
					bit_filt = part({ type = pt.FILT, x = x_char_rom + 66 + i, y = y_char_rom - 4, ctype = bitx.lshift(1, 5 - i) }),
				})
			end
			generic_demuxer(x_char_rom - 12, y_char_rom - 4, 1, 0, targets, lsns_filt, function(x, y, x_to, y_to)
				dray(x, y, x_to - 1, y_to, 2, false)
			end, true, 20, 0x10000000)
			local addr_source = part({ type = pt.FILT, x = x_char_rom - 9, y = y_char_rom - 7, ctype = outputs.char_rindex_low.ctype })
			ldtc(x_char_rom - 9, y_char_rom - 5, addr_source.x, addr_source.y)
			ldtc(addr_source.x + 1, addr_source.y - 1, outputs.char_rindex_low.x, outputs.char_rindex_low.y)

			do -- retract apom
				local x = x_char_rom - 10
				local y = y_char_rom - 7
				local donor = part({ type = pt.HEAC, x = x, y = y_after_content + 7 })
				cray(x, y, donor.x, donor.y, pt.SPRK, 1, pt.PSCN)
				dray(x, y, x, y_char_rom - 3, 1, pt.PSCN)
				part({ type = pt.PSTN, x = x, y = y + 1, extend = math.huge })
				cray(x, y_after_content + 8, x, y_char_rom - 3, pt.SPRK, 1, pt.PSCN)
				cray(x, y_after_content + 8, donor.x, donor.y, donor.type, 1, pt.PSCN)
			end
		end

		do
			local x = x_char_rom - 2
			local y = y_char_rom - 5
			part({ type = pt.LSNS, x = x - 2, y = y - 4, tmp = 3 })
			part({ type = pt.FILT, x = x - 2, y = y - 5, ctype = outputs.char_rindex_high.ctype })
			ldtc(x - 1, y - 6, outputs.char_rindex_high.x, outputs.char_rindex_high.y, 1000)
			part({ type = pt.LDTC, x = x - 1, y = y - 3, tmp = 1 })
			local ldtc_next = part({ type = pt.LDTC, x = x - 2, y = y - 2, tmp = 1 })
			dray(x    , y - 4, ldtc_next.x, ldtc_next.y, 1, pt.PSCN)
			dray(x - 3, y - 3, x_char_rom    , y_char_rom - 3, 1, pt.PSCN)
			dray(x - 3, y - 3, x_char_rom + 1, y_char_rom - 2, 1, pt.PSCN)
		end

		local x_output = x_char_gen_src - 1
		part({ type = pt.FILT, x = x_output - 4, y = y_char_rom - 2 })
		ldtc(x_output - 3, y_char_rom - 2, output_1.x, output_1.y)
		aray(x_output - 3, y_char_rom - 2, 1, 0, pt.METL)
		part({ type = pt.BRAY, x = x_output - 5, y = y_char_rom - 2 })
		part({ type = pt.DMND, x = x_output - 6, y = y_char_rom - 2 })
		part({ type = pt.DTEC, x = x_output - 4, y = y_char_rom - 1 })
		part({ type = pt.FILT, x = x_output - 3, y = y_char_rom - 1 })
		part({ type = pt.FILT, x = x_output - 2, y = y_char_rom - 1 })
		ldtc(x_char_gen_src + 1, y_char_rom - 1, output_2.x, output_2.y)
	end

	do -- bus interface
		local old_parts_length = #parts
		local x_bi = chars_w - 14
		local y_bi = y_interface + 21
		local x_left = x_bi + 4
		local x_right = x_bi + 30
		x_bi_disp_left, x_bi_disp_right = x_left - 1, x_right
		local x_tap = x_left + 20
		part({ type = pt.FILT, x = x_left - 1, y = y_bi    , unstack = true, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_left - 1, y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
		part({ type = pt.FILT, x = x_left    , y = y_bi    , unstack = true, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_left    , y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
		part({ type = pt.FILT, x = x_right   , y = y_bi    , unstack = true, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_right   , y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
		ldtc(x_right - 1, y_bi    , x_left, y_bi    )
		ldtc(x_right - 1, y_bi + 1, x_left, y_bi + 1)
		part({ type = pt.CRMC, x = x_right - 1, y = y_bi     })
		part({ type = pt.CRMC, x = x_right - 1, y = y_bi + 1 })
		for i = x_left - 1, x_right do
			part({ type = pt.FILT, x = i, y = y_bi + 2, unstack = true })
			part({ type = pt.FILT, x = i, y = y_bi + 3, unstack = true })
		end
		local tap_target_1 = part({ type = pt.CONV, x = x_tap    , y = y_bi + 2, tmp = pt.INSL, ctype = pt.FILT })
		local tap_target_2 = part({ type = pt.CONV, x = x_tap + 4, y = y_bi + 2, tmp = pt.INSL, ctype = pt.FILT })
		part({ type = pt.INSL, x = tap_target_1.x, y = y_bi + 2 })
		part({ type = pt.INSL, x = tap_target_2.x, y = y_bi + 2 })
		lsns_spark({ type = pt.PSCN, x = tap_target_1.x, y = y_bi - 1, life = 3 }, 0, 1, -1, 1)
		lsns_spark({ type = pt.PSCN, x = tap_target_2.x, y = y_bi - 1, life = 3 }, 0, 1, -1, 1)
		part({ type = pt.DTEC, x = tap_target_1.x - 2, y = y_bi })
		part({ type = pt.DTEC, x = tap_target_2.x - 2, y = y_bi })
		local ghost_1 = { x = x_tap - 3, y = y_bi }
		local ghost_2 = { x = x_tap - 12, y = y_bi }
		ldtc(tap_target_1.x - 2, y_bi, ghost_1.x, ghost_1.y, nil, 1)
		ldtc(tap_target_1.x - 2, y_bi, ghost_2.x, ghost_2.y, nil, 1)
		ldtc(tap_target_2.x - 2, y_bi, ghost_2.x, ghost_2.y, nil, 1)
		cray(tap_target_1.x, y_bi, tap_target_1.x, tap_target_1.y, pt.DTEC, 1, false)
		cray(tap_target_1.x, y_bi, tap_target_1.x, tap_target_1.y, pt.DTEC, 1, false)
		cray(tap_target_2.x, y_bi, tap_target_2.x, tap_target_2.y, pt.DTEC, 1, false)
		cray(tap_target_2.x, y_bi, tap_target_2.x, tap_target_2.y, pt.DTEC, 1, false)
		part({ type = pt.FILT, x = x_tap - 4, y = y_bi, ctype = 0x10000004 })
		part({ type = pt.FILT, x = x_tap - 5, y = y_bi, ctype = 3, tmp = 7 })
		part({ type = pt.STOR, x = x_tap - 6, y = y_bi })
		part({ type = pt.FILT, x = x_tap - 7, y = y_bi, ctype = 3 })
		ldtc(x_tap - 10, y_bi, x_left, y_bi)
		part({ type = pt.FILT, x = x_tap - 9, y = y_bi })
		part({ type = pt.BRAY, x = x_tap - 8, y = y_bi })
		part({ type = pt.BRAY, x = x_tap - 5, y = y_bi + 1 })
		part({ type = pt.FILT, x = x_tap - 13, y = y_bi, ctype = 0x10000004 })
		part({ type = pt.FILT, x = x_tap - 14, y = y_bi, tmp = 7, ctype = bitx.bor(0x10020000, base_address) })
		part({ type = pt.FILT, x = x_tap - 15, y = y_bi, tmp = 1, ctype = 0x100FFF80 })
		part({ type = pt.STOR, x = x_tap - 16, y = y_bi })
		part({ type = pt.FILT, x = x_tap - 17, y = y_bi })
		ldtc(x_tap - 18, y_bi, x_left, y_bi)
		aray(x_tap - 18, y_bi, -1, 0, pt.METL)
		aray(x_tap - 10, y_bi, -1, 0, pt.METL)
		ldtc(x_tap - 7, y_bi + 1, x_left, y_bi + 1)
		aray(x_tap - 7, y_bi + 1, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_tap - 6, y = y_bi + 1 })
		part({ type = pt.DMND, x = x_tap - 4, y = y_bi + 1 })
		part({ type = pt.DTEC, x = x_tap - 7, y = y_bi + 1, tmp2 = 2 })
		part({ type = pt.DTEC, x = x_tap - 10, y = y_bi, tmp2 = 2 })
		cray(ghost_1.x, y_bi + 5, ghost_1.x, ghost_1.y, pt.SPRK, 1, pt.PSCN)
		cray(ghost_2.x, y_bi + 5, ghost_2.x, ghost_2.y, pt.SPRK, 1, pt.PSCN)
		part({ type = pt.DMND, x = ghost_1.x, y = ghost_1.y - 1 })
		part({ type = pt.DMND, x = ghost_2.x, y = ghost_2.y - 1 })
		part({ type = pt.BRAY, x = tap_target_1.x - 1, y = y_bi - 1, ctype = 0x10000003, life = 3 })
		part({ type = pt.BRAY, x = tap_target_2.x - 1, y = y_bi - 1, ctype = 0x10000003, life = 3 })
		part({ type = pt.BRAY, x = tap_target_1.x, y = y_bi + 1, ctype = 0x10000001, life = 3 })
		part({ type = pt.BRAY, x = tap_target_2.x, y = y_bi + 1, ctype = 0x10000000, life = 3 })
		part({ type = pt.INSL, x = tap_target_1.x, y = y_bi + 4 })
		part({ type = pt.INSL, x = tap_target_2.x, y = y_bi + 4 })
		dray(tap_target_1.x, y_bi + 5, tap_target_1.x, tap_target_1.y, 1, pt.PSCN)
		dray(tap_target_2.x, y_bi + 5, tap_target_2.x, tap_target_2.y, 1, pt.PSCN)
		for i = -(y_interface - y_after_content) - 3, -1 do
			for j = 1, 4 do
				local ctype
				local ptype = pt.INSL
				if j == 4 then
					ctype = 0x10000000
					ptype = pt.FILT
				end
				if j == 1 then
					ctype = 0xDEADBEEF
					ptype = pt.FILT
				end
				if j == 1 or j == 4 or (i >= -(y_interface - y_after_content) - 1 and i <= -2) then
					part({ type = ptype, x = x_tap - 6 - j, y = y_bi + i, ctype = ctype })
				end
			end
		end
		for i = -13, -5 do
			part({ type = pt.FILT, x = x_tap - 7, y = y_after_content + 22 + i, unstack = true })
		end
		ldtc(x_tap - 7, y_after_content + 8, chars_w + 3, -18)
		local input_tap
		do
			local x_before = x_tap - 20
			local x_after = x_after_content + 18
			local y = -19
			part({ type = pt.LDTC, x = x_before + 1, y = y, life = chars_h + 37 })
			function input_tap(x)
				part({ type = pt.FILT, x = x, y = y - 1 })
				part({ type = pt.LDTC, x = x - 1, y = y, tmp = 1 })
				local donor = part({ type = pt.HEAC, x = x - 7, y = y })
				cray(x_before, y, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
				dray(x_before, y, x, y, 1, pt.PSCN)
				cray(x_after, y, x, y, pt.SPRK, 1, pt.PSCN)
				cray(x_after, y, donor.x, donor.y, pt.HEAC, 1, pt.PSCN)
			end
		end
		input_tap(x_tap - 7)
		input_tap(x_tap - 10)
		if not unibody then
			for i = old_parts_length + 1, #parts do
				local part = parts[i]
				if part.y >= y_after_content + 20 then
					part.dcolour = 0xFF007F7F
					if part.type == pt.FILT then
						part.dcolour = 0xFF00FFFF
					end
				end
			end
		end
		if not unibody and (y_interface - y_after_content) >= 2 then
			ucontext.frame(x_left, y_bi - 2, x_right - 1, y_bi + 7, 0, 1)
		end
	end

	if not unibody then
		local x1 = -padding
		local x2 = padding - 1 + chars_w
		local y1 = -padding
		local y2 = padding - 1 + chars_h
		ucontext.frame(x1, y1, x2, y2)
	end
	end

	local y_kb
	local x_bi_kbd_left, x_bi_kbd_right
	if derived_params.have_keyboard then -- keyboard
		local x_kb = math.floor(chars_w / 2) - 60
		y_kb = y_keyboard + 30
		local old_parts_length = #parts

		local life_values = {}
		local function emit_key(vx, vy, size, code, glyph, glyph_offset)
			local life, glyph_index
			if type(code) == "string" then
				life = bitx.bor(bitx.bor(code:byte(1), bitx.lshift(code:byte(2), 7)), 0x4000)
				glyph_index = code:byte(1)
			else
				life = code
				glyph_index = 0
			end
			if glyph_index >= 0x61 and glyph_index <= 0x7A then
				life = bitx.bor(life, 0x8000)
				glyph_index = glyph_index - 0x20
			end
			glyph        = glyph        or font[glyph_index + 1]
			glyph_offset = glyph_offset or 0
			local max_x = 8 * size / 2 - 1
			local max_y = 7
			local x_dray = 0
			if (vx + vy) % 2 == 1 then
				x_dray = 1
			end
			x_dray = x_dray * 4 + 3
			for xx = 0, max_x do
				for yy = 0, max_y do
					local ptype = pt.INST
					local dcolour = 0xFF3F3F3F
					if yy == max_y or xx == max_x then
						ptype = pt.INSL
						dcolour = 0xFF000000
					elseif yy == 0 then
						if (vx * 4 + xx) % 8 == (vy * 4 + 5) % 8 then
							ptype = pt.PSCN
						elseif (vx * 4 + xx) % 8 == (vy * 4 + 6) % 8 then
							ptype = pt.INWR
						elseif (vx * 4 + xx) % 8 == (vy * 4 + 7) % 8 then
							ptype = pt.INSL
						elseif (vx * 4 + xx) % 8 == (vy * 4 + 8) % 8 then
							ptype = pt.INWR
						elseif (vx * 4 + xx) % 8 == (vy * 4 + 9) % 8 then
							ptype = pt.PSCN
						end
					elseif yy == max_y - 1 then
						if xx == x_dray - 2 then
							ptype = pt.PSCN
						elseif xx == x_dray - 1 then
							ptype = pt.INWR
						elseif xx == x_dray then
							ptype = pt.NSCN
							part({ type = pt.DRAY, x = x_kb + vx * 4 + xx, y = y_kb + vy * 8 + yy + 1, tmp = 1, tmp2 = (4 - vy) * 8 })
							table.insert(life_values, { x = x_kb + vx * 4 + xx, y = y_kb + vy * 8 + yy + 2, life = life })
						elseif xx == x_dray + 1 then
							ptype = pt.INWR
						elseif xx == x_dray + 2 then
							ptype = pt.PSCN
						end
					end
					local shift = xx - glyph_offset
					if shift >= 0 and shift <= 31 then
						if bitx.band(bitx.rshift(glyph[yy + 1] or 0, shift), 1) ~= 0 then
							dcolour = 0xFFFFFFFF
						end
					end
					part({ type = ptype, x = x_kb + vx * 4 + xx, y = y_kb + vy * 8 + yy, dcolour = dcolour })
				end
			end
		end

		local layout = {
			{ "`~", "1!", "2@", "3$", "4%", "5^", "6&", "7*", "8*", "9(", "0)", "-_", "=+",    "\8\24" },
			{ "\9\25", "qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "[{", "]}",   "\\|" },
			{             "aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", ";:", "'\"",  "\10\26" },
			{                "zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",<", ".>", "/?"                },
			{   "\17\28",   "\18\29",                  " \16"                 ,   "\19\30",   "\20\31" },
		}
		for i = 0, 13 do
			if i == 13 then
				emit_key(i * 2, 0, 4, layout[1][i + 1], { 0x0010, 0x0018, 0x3FFC, 0x3FFE, 0x3FFC, 0x0018, 0x0010, 0x0000 }, 0)
			else
				emit_key(i * 2, 0, 2, layout[1][i + 1])
			end
		end
		for i = 0, 13 do
			if i == 0 then
				emit_key(i * 2, 1, 3, layout[2][i + 1], { 0x040, 0x0C0, 0x1FE, 0x3FE, 0x1FE, 0x0C0, 0x040, 0x000 }, 0)
			else
				emit_key(i * 2 + 1, 1, i == 13 and 3 or 2, layout[2][i + 1])
			end
		end
		for i = 0, 11 do
			if i == 11 then
				emit_key(i * 2 + 4, 2, 4, layout[3][i + 1], { 0x3810, 0x3818, 0x3FFC, 0x3FFE, 0x1FFC, 0x0018, 0x0010, 0x0000 }, 0)
			else
				emit_key(i * 2 + 4, 2, 2, layout[3][i + 1])
			end
		end
		for i = 0, 9 do
			emit_key(i * 2 + 5, 3, 2, layout[4][i + 1])
		end
		emit_key( 0, 2,  4,            2, { 0x010, 0x038, 0x07C, 0x0FE, 0x038, 0x000, 0x038, 0x000 },  0)
		emit_key( 0, 3,  5,            1, { 0x010, 0x038, 0x07C, 0x0FE, 0x038, 0x038, 0x038, 0x000 },  0)
		emit_key(25, 3,  5,            1, { 0x010, 0x038, 0x07C, 0x0FE, 0x038, 0x038, 0x038, 0x000 }, 10)
		emit_key( 0, 4,  4, layout[5][1], { 0x03E, 0x07F, 0x073, 0x073, 0x063, 0x07F, 0x03E, 0x000 },  4)
		emit_key( 4, 4,  4, layout[5][2], { 0x03E, 0x07F, 0x063, 0x067, 0x067, 0x07F, 0x03E, 0x000 },  4)
		emit_key( 8, 4, 14, layout[5][3], { 0x000, 0x000, 0x000, 0x000, 0x000, 0x183, 0x1FF, 0x000 }, 23)
		emit_key(22, 4,  4, layout[5][4], { 0x03E, 0x07F, 0x063, 0x073, 0x073, 0x07F, 0x03E, 0x000 },  4)
		emit_key(26, 4,  4, layout[5][5], { 0x03E, 0x07F, 0x067, 0x067, 0x063, 0x07F, 0x03E, 0x000 },  4)
		for xx = -1, 119 do
			part({ type = pt.INSL, x = x_kb + xx, y = y_kb - 1, unstack = true, dcolour = 0xFF000000 })
			if xx % 8 == 3 then
				part({ type = pt.INSL, x = x_kb + xx, y = y_kb + 40, unstack = true, dcolour = 0xFF000000 })
			end
		end
		for yy = 0, 39 do
			part({ type = pt.INSL, x = x_kb - 1, y = y_kb + yy, unstack = true, dcolour = 0xFF000000 })
		end

		for i = old_parts_length + 1, #parts do
			local part = parts[i]
			for _, item in ipairs(life_values) do
				if part.x == item.x and part.y == item.y then
					part.life = item.life
				end
			end
		end

		do -- grab life
			local x = x_kb - 2
			local y = y_kb + 41
			cray(x - 4, y, x + 4, y, pt.INSL, 1, pt.PSCN)
			part({ type = pt.HEAC, x = x - 1, y = y })
			part({ type = pt.PSTN, x = x    , y = y, ctype = pt.HEAC, extend = math.huge })
			part({ type = pt.PSTN, x = x + 1, y = y, ctype = pt.HEAC, extend = math.huge, tmp = 1 })
			part({ type = pt.PSTN, x = x + 2, y = y, ctype = pt.HEAC, extend = 1 })
			solid_spark(x + 1, y + 1, -1, 0, pt.PSCN, true)
			solid_spark(x + 2, y + 1, -1, 0, pt.NSCN, true)
			part({ type = pt.DMND, x = x + 3, y = y })
			part({ type = pt.LSNS, x = x + 118, y = y, tmp = 1 })
			part({ type = pt.HEAC, x = x + 118, y = y })
			part({ type = pt.FILT, x = x + 119, y = y })
			cray(x + 125, y, x + 117, y, pt.SPRK, 150, pt.PSCN)
			ldtc(x + 121, y, x + 119, y)
			aray(x + 121, y, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x + 122, y = y })
			part({ type = pt.BRAY, x = x + 123, y = y })
			part({ type = pt.DTEC, x = x + 124, y = y })
			local grab_life_prev = part({ type = pt.FILT, x = x + 124, y = y + 1 })
			ldtc(x_kb - 5, y + 1, grab_life_prev.x, grab_life_prev.y)
			local grab_life = part({ type = pt.FILT, x = x_kb - 6, y = y + 1 })
			local grab_busstate = part({ type = pt.FILT, x = x_kb - 8, y = y + 1 })
			ldtc(x_kb - 7, y_kb + 3, x_kb - 3, y_kb - 1)
			local grab_busstate_prev = part({ type = pt.FILT, x = x_kb - 8, y = y_kb + 4 })
			ldtc(x_kb - 8, y, x_kb - 8, grab_busstate_prev.y)
			ldtc(x_kb + 7, y + 1, grab_life.x, y + 1)
			dray(x_kb + 7, y + 1, x_kb + 46, y + 1, 1, pt.PSCN)
			dray(x_kb + 7, y + 1, x_kb + 70, y + 1, 3, pt.PSCN)
			for x = x_kb + 70, x_kb + 72 do
				part({ type = pt.INSL, x = x, y = y + 1 })
			end
			dray(x_kb + 73, y + 1, x_kb + 12, y + 1, 1, pt.PSCN)
			part({ type = pt.FILT, x = x_kb + 8, y = y + 1 })
			ldtc(x_kb + 3, y + 1, grab_busstate.x, y + 1)
			dray(x_kb + 3, y + 1, x_kb + 47, y + 1, 1, pt.PSCN)
			part({ type = pt.FILT, x = x_kb + 4, y = y + 1 })
		end

		do -- indicators
			local y = y_kb + 43
			do
				local x = x_kb + 10
				local function emit_indicator(x, y_target, dcolour)
					for j = 0, 2 do
						part({ type = pt.LCRY, x = x + j, y = y - 1, dcolour = dcolour })
						for i = 0, 2 do
							dray(x + j, y, x + j, y_target + i, 1, false)
						end
					end
					for i = 0, 2 do
						cray(x_kb - 5 + i % 2 * 3, y_target + i, x, y_target + i, pt.SPRK, 3, pt.PSCN)
					end
				end
				emit_indicator(x     , y_kb + 18, 0xFFFF0000)
				emit_indicator(x +  4, y_kb + 26, 0xFF00FF00)
				emit_indicator(x + 68, y_kb + 34, 0xFFFFFF00)
				for i = 0, 6 do
					spark({ type = pt.INWR, x = x + i, y = y + 1 })
				end
				spark_row(x -  2, y + 1, x     , y + 1, pt.INWR, 7, 4)
				for i = 0, 2 do
					spark({ type = pt.INWR, x = x + 68 + i, y = y + 1 })
				end
				spark_row(x + 66, y + 1, x + 68, y + 1, pt.INWR, 3, 4)
			end

			local x_control = x_kb + 96
			local function emit_control(x_off, x_target, conductor)
				local x = x_control + x_off
				part ({ type = pt.LSNS, x = x + 2, y = y - 1, tmp = 3 })
				spark({ type = pt.PSCN, x = x + 1, y = y - 1, life = 2 })
				dray(x, y - 1, x_target, y - 1, 1, false)
				lsns_spark({ type = conductor, x = x - 1, y = y - 1, life = 3 }, 0, 1, 1, 1)
				spark({ type = conductor, x = x_target, y = y - 1, unstack = true, life = 2 })
			end
			emit_control( -5, x_kb + 77, pt.NSCN)
			emit_control(-10, x_kb + 77, pt.PSCN)
			emit_control(  5, x_kb + 13, pt.NSCN)
			emit_control(  0, x_kb + 13, pt.PSCN)
			emit_control( 15, x_kb +  9, pt.NSCN)
			emit_control( 10, x_kb +  9, pt.PSCN)
		end

		do
			local storage_remap = setmetatable({}, { __index = function(_, k)
				if k >= 16 then
					return 43 + (k - 16) * 5
				end
				return k
			end })
			plot.merge_parts(x_kb + 43, y_kb + 42, parts, kbdcore.get_parts(), storage_remap)
		end

		do -- bus
			local x = x_kb - 4
			local y = y_kb + 3
			for i = -3, 40 do
				part({ type = pt.FILT, x = x, y = y + i, ctype = 0x10000000 })
			end
			part({ type = pt.DTEC, x = x, y = y + 41 })

			local x_read = x_kb + 60
			local y_read = y_kb + 43
			aray(x_read, y_read, -1, 1, false)
			solid_spark(x_read - 2, y_read + 1, 1, 0, pt.METL, true)
			part({ type = pt.DTEC, x = x_read + 2, y = y_read, tmp2 = 2 })
			local read = part({ type = pt.FILT, x = x_read + 3, y = y_read })
			cray(x_read + 2, y_read, x_read + 2, y_read - 2, pt.SPRK, 1, pt.PSCN)
			part({ type = pt.DMND, x = x_read + 3, y = y_read - 3 })

			ldtc(x_read + 5, y_read, read.x, read.y)
			aray(x_read + 5, y_read, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_read + 6, y = y_read })
			part({ type = pt.BRAY, x = x_read + 7, y = y_read })
			local target = part({ type = pt.BRAY, x = x_kb - 3, y = y_read })
			dray(x_read + 8, y_read, target.x, target.y, 1, pt.PSCN)
		end

		do -- bus interface
			local old_parts_length = #parts
			local x_bi = x_kb - 11
			local y_bi = y_interface + 21
			local x_left = x_bi + 4
			local x_right = x_bi + 21
			x_bi_kbd_left, x_bi_kbd_right = x_left - 1, x_right
			part({ type = pt.FILT, x = x_left - 1, y = y_bi    , unstack = true, ctype = 0x10000000 })
			part({ type = pt.FILT, x = x_left - 1, y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
			part({ type = pt.FILT, x = x_left    , y = y_bi    , unstack = true, ctype = 0x10000000 })
			part({ type = pt.FILT, x = x_left    , y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
			part({ type = pt.FILT, x = x_right   , y = y_bi    , unstack = true, ctype = 0x10000000 })
			part({ type = pt.FILT, x = x_right   , y = y_bi + 1, unstack = true, ctype = 0xDEADBEEF })
			ldtc(x_right - 1, y_bi    , x_left, y_bi    )
			ldtc(x_right - 1, y_bi + 1, x_left, y_bi + 1)
			part({ type = pt.CRMC, x = x_right - 1, y = y_bi     })
			part({ type = pt.CRMC, x = x_right - 1, y = y_bi + 1 })
			for i = x_left - 1, x_right do
				part({ type = pt.FILT, x = i, y = y_bi + 2, unstack = true })
				part({ type = pt.FILT, x = i, y = y_bi + 3, unstack = true })
			end

			ldtc(x_left + 3, y_bi, x_left, y_bi, nil, 1)
			aray(x_left + 3, y_bi, -1, 0, pt.METL)
			part({ type = pt.FILT, x = x_left +  4, y = y_bi })
			part({ type = pt.STOR, x = x_left +  5, y = y_bi })
			part({ type = pt.FILT, x = x_left +  6, y = y_bi, tmp = 7, ctype = bitx.bor(0x10080000, base_address) })
			part({ type = pt.FILT, x = x_left +  7, y = y_bi, tmp = 1, ctype = 0x100FFF80 })
			part({ type = pt.FILT, x = x_left +  8, y = y_bi, ctype = 2 })
			part({ type = pt.DMND, x = x_left +  8, y = y_bi - 1 })
			part({ type = pt.DMND, x = x_left + 11, y = y_bi - 1 })
			part({ type = pt.BRAY, x = x_left + 13, y = y_bi - 1, ctype = 0x10000003, life = 3 })
			part({ type = pt.FILT, x = x_left + 10, y = y_bi - 1, ctype = 3 })
			part({ type = pt.FILT, x = x_left + 10, y = y_bi, ctype = 0x10000004 })
			part({ type = pt.DTEC, x = x_left + 12, y = y_bi })
			local ghost_1 = { x = x_left +  9, y = y_bi }
			local ghost_2 = { x = x_left + 11, y = y_bi }
			ldtc(x_left + 12, y_bi, ghost_2.x, ghost_2.y, nil, 1)
			lsns_spark({ type = pt.PSCN, x = x_left + 15, y = y_bi - 1, life = 3 }, -1, 1, -2, 1)
			cray(x_left + 14, y_bi, x_left + 14, y_bi + 2, pt.DTEC, 2, false)
			cray(x_left + 14, y_bi, x_left + 14, y_bi + 2, pt.DTEC, 2, false)
			part({ type = pt.CONV, x = x_left + 12, y = y_bi + 2, tmp = pt.INSL, ctype = pt.FILT })
			local tap_target_1 = part({ type = pt.INSL, x = x_left + 12, y = y_bi + 2 })
			local tap_target_2 = part({ type = pt.INSL, x = x_left + 11, y = y_bi + 3 })
			part({ type = pt.BRAY, x = x_left + 14, y = y_bi + 1, ctype = 0x10000008, life = 3 })
			cray(ghost_1.x + 5, y_bi + 5, ghost_1.x, ghost_1.y, pt.SPRK, 1, pt.PSCN)
			cray(ghost_2.x, y_bi + 5, ghost_2.x, ghost_2.y, pt.SPRK, 1, pt.PSCN)
			part({ type = pt.INSL, x = tap_target_1.x - 2, y = y_bi + 4 })
			dray(tap_target_1.x - 3, y_bi + 5, tap_target_1.x, tap_target_1.y, 1, pt.PSCN)
			dray(tap_target_2.x - 2, y_bi + 5, tap_target_2.x, tap_target_2.y, 1, pt.PSCN)
			for i = 1, 8 do
				part({ type = pt.FILT, x = x_left + 3, y = y_bi + i })
			end
			ldtc(x_left + 5, y_bi + 4, ghost_1.x, ghost_1.y, nil, 2)
			local state = part({ type = pt.FILT, x = x_left + 4, y = y_bi + 5 })
			ldtc(x_left + 4, y_bi + 7, state.x, state.y)
			part({ type = pt.FILT, x = x_left + 4, y = y_bi + 8 })
			aray(x_left + 2, y_bi + 1, -1, 0, pt.METL)
			for i = 4, 8 do
				part({ type = pt.STOR, x = x_left + i, y = y_bi + 1 })
			end
			part({ type = pt.BRAY, x = x_left +  9, y = y_bi + 1 })
			part({ type = pt.DMND, x = x_left + 10, y = y_bi + 1 })
			for i = 1, (y_keyboard - y_interface) do
				part({ type = pt.FILT, x = x_left + 3, y = y_bi + 8 + i, ctype = 0x10000000 })
				part({ type = pt.FILT, x = x_left + 4, y = y_bi + 8 + i, ctype = 2 })
			end

			if not unibody then
				for i = old_parts_length + 1, #parts do
					local part = parts[i]
					if part.y < y_keyboard + 26 then
						part.dcolour = 0xFF007F7F
						if part.type == pt.FILT then
							part.dcolour = 0xFF00FFFF
						end
					end
				end
			end
			if not unibody and (y_keyboard - y_interface) >= 2 then
				ucontext.frame(x_left, y_bi - 2, x_right - 1, y_bi + 7, 0, 1)
			end
		end

		if not unibody then
			local x1 = -padding
			local x2 = padding - 1 + chars_w
			local y1 = y_kb - 3
			local y2 = y_kb + 45
			ucontext.frame(x1, y1, x2, y2)
		end
	end

	if unibody then
		local x1 = -padding
		local x2 = padding - 1 + chars_w
		local y1 = -padding
		local y2 = y_kb + 45
		for x = x1 - 1, x2 + 1 do
			if x >= x_bi_kbd_left and x <= x_bi_kbd_right then
				-- skip
			elseif x >= x_bi_disp_left and x <= x_bi_disp_right then
				-- skip
			else
				for yy = 0, 3 do
					part({ type = pt.FILT, x = x, y = y_interface + 21 + yy })
				end
			end
		end
		ucontext.frame(x1, y1, x2, y2)
	end

	return parts
end

local function build(params, params_name)
	local interface_y = params.bus.y
	local have_screen = params.screen_y and true
	local have_keyboard = params.keyboard_y and true
	local chars_w, chars_h
	check.integer_range(params_name .. ".chars_nh", params.chars_nh, 12, 29)
	if have_screen then
		check.integer_range(params_name .. ".chars_nv", params.chars_nv, 4, 29)
		if params.single_pixel then
			if params.chars_nv < 8 then
				misc.user_error("%s specifies too few rows for compatibility with a single-pixel plotter", params_name .. ".chars_nv")
			end
			if params.chars_nh > 12 + (params.chars_nv - 8) * 4 then
				misc.user_error("%s and %s specify too many columns compared to the amount of rows for compatibility with a single-pixel plotter", params_name .. ".chars_nh", params_name .. ".chars_nv")
			end
		end
		if params.chars_nv > 12 + (params.chars_nh - 12) * 4 then
			misc.user_error("%s and %s specify too many rows compared to the amount of columns for compatibility with a single-pixel plotter", params_name .. ".chars_nv", params_name .. ".chars_nh")
		end
		chars_h = params.chars_nv * char_size
	end
	chars_w = params.chars_nh * char_size
	r3_check.base_address(params_name .. ".base_address", params.base_address, 0xFF80)
	local areas = {}
	local xoff
	local screen_padding = 22
	if params.x.which == "left" then
		xoff = params.x.value + screen_padding
	else
		xoff = params.x.value + 1 - screen_padding - chars_w
	end
	local yoff = 0
	if have_screen then
		if params.screen_y.which == "screen_top" then
			yoff = params.screen_y.value + screen_padding
		else
			yoff = params.screen_y.value + 1 - screen_padding - chars_h
		end
	end
	local keyboard_y = 0
	if have_keyboard then
		if params.keyboard_y.which == "keyboard_top" then
			keyboard_y = params.keyboard_y.value
		else
			keyboard_y = params.keyboard_y.value - 50
		end
	end
	local derived_params = {
		y_interface      = interface_y - yoff - 21,
		y_keyboard       = keyboard_y - 26 - yoff,
		have_screen      = have_screen,
		have_keyboard    = have_keyboard,
	}
	if have_screen then
		if interface_y - (chars_h + yoff + screen_padding) + 1 < 0 then
			misc.user_error("%s specifies too little distance from the bus", params_name .. "." .. params.screen_y.which)
		end
	end
	if have_keyboard then
		if keyboard_y - interface_y - 5 < 0 then
			misc.user_error("%s specifies too little distance from the bus", params_name .. "." .. params.keyboard_y.which)
		end
	end
	if not have_screen and not have_keyboard then
		misc.user_error("at least one of %s and %s must be specified", params_name .. ".screen_top/.screen_bottom", params_name .. ".keyboard_top/.keyboard_bottom")
	end
	if params.unibody then
		if not (have_screen and have_keyboard) then
			misc.user_error("%s requests a unibody configuration, which required both a screen and a keyboard", params_name .. ".unibody")
		end
	end
	local parts_internal = build_internal(params, derived_params)
	local parts = {}
	plot.merge_parts(xoff, yoff, parts, parts_internal)
	if params.unibody then
		table.insert(areas, {
			type = "solid",
			name = "body",
			x    = xoff - screen_padding,
			y    = yoff - screen_padding,
			w    = chars_w + 2 * screen_padding,
			h    = keyboard_y + 51 - (yoff - screen_padding),
		})
	else
		if have_screen then
			table.insert(areas, {
				type = "solid",
				name = "screen",
				x    = xoff - screen_padding,
				y    = yoff - screen_padding,
				w    = chars_w + 2 * screen_padding,
				h    = chars_h + 2 * screen_padding,
			})
			local interface = {
				type = "solid",
				name = "screen_interface",
				x    = xoff + chars_w - 11,
				y    = interface_y - 3,
				w    = 28,
				h    = 12,
			}
			table.insert(areas, interface)
			table.insert(params.bus.through_areas, interface)
			table.insert(areas, {
				type = "solid",
				name = "screen_local",
				x    = xoff + chars_w,
				y    = yoff + chars_h + screen_padding,
				w    = 4,
				h    = interface_y - (yoff + chars_h + screen_padding) - 3,
			})
		end
		if have_keyboard then
			table.insert(areas, {
				type = "solid",
				name = "keyboard",
				x    = xoff - screen_padding,
				y    = keyboard_y,
				w    = chars_w + 2 * screen_padding,
				h    = 51,
			})
			local interface = {
				type = "solid",
				name = "keyboard_interface",
				x    = xoff + chars_w / 2 - 68,
				y    = interface_y - 3,
				w    = 19,
				h    = 12,
			}
			table.insert(areas, interface)
			table.insert(params.bus.through_areas, interface)
			table.insert(areas, {
				type = "solid",
				name = "keyboard_local",
				x    = xoff + chars_w / 2 - 64,
				y    = interface_y + 9,
				w    = 2,
				h    = keyboard_y - interface_y - 9,
			})
		end
	end
	return {
		parts = parts,
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
		screen_y = {
			type     = "lowhigh",
			low      = "screen_top",
			high     = "screen_bottom",
			optional = true,
		},
		keyboard_y = {
			type     = "lowhigh",
			low      = "keyboard_top",
			high     = "keyboard_bottom",
			optional = true,
		},
		bus = {
			type = "cpu_bus",
		},
	}
end

return {
	build       = build,
	param_types = param_types,
	outputs     = outputs,
}
