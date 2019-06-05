#!/usr/bin/env lua

-- * ---------------------------------------------------------------------------
-- * -- Configuration ----------------------------------------------------------
-- * ---------------------------------------------------------------------------
local MAX_INCLUDE_DEPTH = 100
local MAX_EXPANSION_DEPTH = 100
local MAX_EVAL_DEPTH = 100

local tpt = tpt
local env_copy = {}
for key, value in pairs(_G) do
	env_copy[key] = value
end
setfenv(1, setmetatable(env_copy, { __index = function()
	error("__index")
end, __newindex = function()
	error("__newindex")
end }))

-- * ---------------------------------------------------------------------------
-- * -- bit32 ------------------------------------------------------------------
-- * ---------------------------------------------------------------------------
local bit32_lshift
local bit32_rshift
local bit32_xor
local bit32_sub
local bit32_add
local bit32_div
local bit32_mod
local bit32_mul
local bit32_and
local bit32_or
local bit32_xor
do
	function bit32_lshift(a, b)
		if b >= 32 then
			return 0
		end
		return bit32_mul(a, 2 ^ b)
	end
	function bit32_rshift(a, b)
		if b >= 32 then
			return 0
		end
		return bit32_div(a, 2 ^ b)
	end
	function bit32_sub(a, b)
		local s = a - b
		if s < 0 then
			s = s + 0x100000000
		end
		return s
	end
	function bit32_add(a, b)
		local s = a + b
		if s >= 0x100000000 then
			s = s - 0x100000000
		end
		return s
	end
	local function divmod(a, b)
		local quo = math.floor(a / b)
		return quo, a - quo
	end
	function bit32_div(a, b)
		local quo, rem = divmod(a, b)
		return quo
	end
	function bit32_mod(a, b)
		local quo, rem = divmod(a, b)
		return rem
	end
	function bit32_mul(a, b)
		local ll = bit32_and(a, 0xFFFF) * bit32_and(b, 0xFFFF)
		local lh = bit32_and(a, 0xFFFF) * math.floor(b / 0x10000)
		local hl = math.floor(a / 0x10000) * bit32_and(b, 0xFFFF)
		return bit32_add(bit32_add(ll, lh * 0x10000), hl * 0x10000)
	end
	local function hasbit(a, b)
		return a % (b + b) >= b
	end
	function bit32_and(a, b)
		local curr = 1
		local out = 0
		for ix = 0, 31 do
			if hasbit(a, curr) and hasbit(b, curr) then
				out = out + curr
			end
			curr = curr * 2
		end
		return out
	end
	function bit32_or(a, b)
		local curr = 1
		local out = 0
		for ix = 0, 31 do
			if hasbit(a, curr) or hasbit(b, curr) then
				out = out + curr
			end
			curr = curr * 2
		end
		return out
	end
	function bit32_xor(a, b)
		local curr = 1
		local out = 0
		for ix = 0, 31 do
			if hasbit(a, curr) ~= hasbit(b, curr) then
				out = out + curr
			end
			curr = curr * 2
		end
		return out
	end
end

-- * ---------------------------------------------------------------------------
-- * -- printf -----------------------------------------------------------------
-- * ---------------------------------------------------------------------------
local printf
do
	printf = setmetatable({
		print = print,
		print_old = print,
		log_handle = false,
		colour = false,
		err_called = false
	}, { __call = function(self, ...)
		printf.print(string.format(...))
	end })
	function printf.debug(first, ...)
		local things = { tostring(first) }
		for ix_thing, thing in ipairs({ ... }) do
			table.insert(things, tostring(thing))
		end
		printf((printf.colour and "[r3asm] " or "[r3asm] [DD] ") .. "%s", table.concat(things, "\t"))
	end
	function printf.info(format, ...)
		printf((printf.colour and "\008l[r3asm]\008w " or "[r3asm] [II] ") .. format, ...)
	end
	function printf.warn(format, ...)
		printf((printf.colour and "\008o[r3asm]\008w " or "[r3asm] [WW] ") .. format, ...)
	end
	function printf.err(format, ...)
		printf((printf.colour and "\008t[r3asm]\008w " or "[r3asm] [EE] ") .. format, ...)
		printf.err_called = true
	end
	function printf.redirect(log_path)
		local handle = io.open(log_path, "w")
		if handle then
			printf.log_path = log_path
			printf.log_handle = handle
			printf.info("redirecting log to '%s'", printf.log_path)
			printf.print = function(str)
				printf.log_handle:write(str .. "\n")
			end
		else
			printf.warn("failed to open '%s' for writing, log not redirected", log_path)
		end
	end
	function printf.unredirect()
		if printf.log_handle then
			printf.log_handle:close()
			printf.log_handle = false
			printf.print = printf.print_old
			printf.info("closed log '%s'", printf.log_path)
		end
	end
	function printf.update_colour()
		printf.colour = tpt and not printf.log_handle
	end
	printf.update_colour()
end
local function print(...)
	printf.debug(...)
end

local function failf(...)
	printf.err(...)
	error(failf)
end

local args = { ... }
xpcall(function()

-- * ---------------------------------------------------------------------------
-- * -- Convenience functions --------------------------------------------------
-- * ---------------------------------------------------------------------------

	local function resolve_relative(base_with_file, relative)
		local components = {}
		local parent_depth = 0
		for component in (base_with_file .. "/../" .. relative):gmatch("[^/]+") do
			if component == ".." then
				if #components > 0 then
					components[#components] = nil
				else
					parent_depth = parent_depth + 1
				end
			elseif component ~= "." then
				table.insert(components, component)
			end
		end
		for _ = 1, parent_depth do
			table.insert(components, 1, "..")
		end
		return table.concat(components, "/")
	end

-- * ---------------------------------------------------------------------------
-- * -- Tokenisation -----------------------------------------------------------
-- * ---------------------------------------------------------------------------
	local tokenise
	do
		local token_i = {}
		local token_mt = { __index = token_i }
		function token_i:is(type, value)
			return self.type == type and (not value or self.value == value)
		end
		function token_i:punctuator(...)
			return self:is("punctuator", ...)
		end
		function token_i:identifier(...)
			return self:is("identifier", ...)
		end
		function token_i:stringlit(...)
			return self:is("stringlit", ...)
		end
		function token_i:comma()
			return self:is("punctuator", ",")
		end
		function token_i:number()
			return self:is("number")
		end
		function token_i:point(other)
			other.sline = self.sline
			other.soffs = self.soffs
			return setmetatable(other, token_mt)
		end
		function token_i:blamef(report, format, ...)
			report("%s:%i:%i: " .. format, self.sline.path, self.sline.line, self.soffs, ...)
			self.sline:dump_itop()
			if self.expanded_from then
				self.expanded_from:blamef(printf.info, "expanded from this")
			end
		end
		function token_i:expand_by(other)
			local clone = setmetatable({}, token_mt)
			for key, value in pairs(self) do
				clone[key] = value
			end
			clone.expanded_from = other
			return clone
		end

		local transition = {}
		local all_8bit = ""
		for ix = 0, 255 do
			all_8bit = all_8bit .. string.char(ix)
		end
		local function transitions(transition_list)
			local tbl = {}
			local function add_transition(cond, action)
				if type(cond) == "string" then
					for ch in all_8bit:gmatch(cond) do
						tbl[ch:byte()] = action
					end
				else
					tbl[cond] = action
				end
			end
			for _, ix_trans in ipairs(transition_list) do
				add_transition(ix_trans[1], ix_trans[2])
			end
			return tbl
		end

		transition.push = transitions({
			{         "'", { consume =  true, state = "charlit"    }},
			{        "\"", { consume =  true, state = "stringlit"  }},
			{     "[;\n]", { consume = false, state = "done"       }},
			{     "[0-9]", { consume =  true, state = "number"     }},
			{ "[_A-Za-z]", { consume =  true, state = "identifier" }},
			{ "[%[%]%(%)%+%-%*/%%:%?&#<>=!^~%.{}\\|@$,`]", { consume = false, state = "punctuator" }},
		})
		transition.identifier = transitions({
			{ "[_A-Za-z0-9]", { consume =  true, state = "identifier" }},
			{          false, { consume = false, state = "push"       }},
		})
		transition.number = transitions({
			{ "[_A-Za-z0-9]", { consume =  true, state = "number" }},
			{          false, { consume = false, state = "push"   }},
		})
		transition.charlit = transitions({
			{  "'", { consume = true, state = "push"         }},
			{ "\n", { error = "unfinished character literal" }},
		})
		transition.stringlit = transitions({
			{ "\"", { consume = true, state = "push"      }},
			{ "\n", { error = "unfinished string literal" }},
		})
		transition.punctuator = transitions({
			{ ".", { consume = true, state = "push" }},
		})

		local whitespace = {
			["\f"] = true,
			["\n"] = true,
			["\r"] = true,
			["\t"] = true,
			["\v"] = true,
			[" "] = true
		}

		function tokenise(sline)
			local line = sline.str .. "\n"
			local tokens = {}
			local state = "push"
			local token_begin
			local cursor = 1
			while cursor <= #line do
				local ch = line:byte(cursor)
				if state == "push" and whitespace[ch] and #tokens > 0 then
					tokens[#tokens].whitespace_follows = true
				end
				local old_state = state
				local transition_info = transition[state][ch] or transition[state][false]
				local consume = true
				if transition_info then
					if transition_info.error then
						return false, cursor, transition_info.error
					end
					state = transition_info.state
					consume = transition_info.consume
				end
				if consume then
					cursor = cursor + 1
				end
				if state == "done" then
					break
				end
				if old_state == "push" and state ~= "push" then
					token_begin = cursor
					if consume then
						token_begin = token_begin - 1
					end
				end
				if old_state ~= "push" and state == "push" then
					local token_end = cursor - 1
					table.insert(tokens, setmetatable({
						type = old_state,
						value = line:sub(token_begin, token_end),
						sline = sline,
						soffs = token_begin
					}, token_mt))
				end
			end
			if #tokens > 0 then
				tokens[#tokens].whitespace_follows = true
			end
			return true, tokens
		end
	end

-- * ---------------------------------------------------------------------------
-- * -- Evaluation -------------------------------------------------------------
-- * ---------------------------------------------------------------------------

	local evaluate
	do
		local operators = {
			">=", "<=", "==", "!=", "<<", ">>",
			"~", "-", "+", "!", "/", "%", "<", ">",
			"*", "&", "|", "^", "&&", "||"
		}
		table.sort(operators, function(a, b)
			return #a > #b
		end)
		local operator_funcs = {
			[">="] = { pops = 2, does = function(get) return                (get(1) >= get(2)) and 1 or 0 end },
			["<="] = { pops = 2, does = function(get) return                (get(1) <= get(2)) and 1 or 0 end },
			[">" ] = { pops = 2, does = function(get) return                (get(1) >  get(2)) and 1 or 0 end },
			["<" ] = { pops = 2, does = function(get) return                (get(1) <  get(2)) and 1 or 0 end },
			["=="] = { pops = 2, does = function(get) return                (get(1) == get(2)) and 1 or 0 end },
			["!="] = { pops = 2, does = function(get) return                (get(1) ~= get(2)) and 1 or 0 end },
			["&&"] = { pops = 2, does = function(get) return ((get(1) ~= 0) and (get(2) ~= 0)) and 1 or 0 end },
			["||"] = { pops = 2, does = function(get) return ((get(1) ~= 0)  or (get(2) ~= 0)) and 1 or 0 end },
			["!" ] = { pops = 1, does = function(get) return                     (get(1) == 0) and 1 or 0 end },
			["<<"] = { pops = 2, does = function(get) return                 bit32_lshift(get(1), get(2)) end },
			[">>"] = { pops = 2, does = function(get) return                 bit32_rshift(get(1), get(2)) end },
			["~" ] = { pops = 1, does = function(get) return                bit32_xor(get(1), 0xFFFFFFFF) end },
			["-" ] = { pops = 2, does = function(get) return                    bit32_sub(get(1), get(2)) end },
			["+" ] = { pops = 2, does = function(get) return                    bit32_add(get(1), get(2)) end },
			["/" ] = { pops = 2, does = function(get) return                    bit32_div(get(1), get(2)) end },
			["%" ] = { pops = 2, does = function(get) return                    bit32_mod(get(1), get(2)) end },
			["*" ] = { pops = 2, does = function(get) return                    bit32_mul(get(1), get(2)) end },
			["&" ] = { pops = 2, does = function(get) return                    bit32_and(get(1), get(2)) end },
			["|" ] = { pops = 2, does = function(get) return                     bit32_or(get(1), get(2)) end },
			["^" ] = { pops = 2, does = function(get) return                    bit32_xor(get(1), get(2)) end },
		}

		local function parse_number_base(str, base)
			local out = 0
			for ix = #str, 1, -1 do
				local pos = base:find(str:sub(ix, ix))
				if not pos then
					return false, ("invalid digit at position %i"):format(ix)
				end
				out = out * #base + (pos - 1)
				if out >= 0x100000000 then
					return false, "unsigned 32-bit overflow"
				end
			end
			return true, out
		end
		local function parse_number(str)
			if str:match("^0[Xx][0-9A-Fa-f]+$") then
				return parse_number_base(str:sub(3):lower(), "0123456789abcdef")
			elseif str:match("^[0-9A-Fa-f]+[Hh]$") then
				return parse_number_base(str:sub(1, -2), "0123456789abcdef")
			elseif str:match("^0[Bb][0-1]+$") then
				return parse_number_base(str:sub(3), "01")
			elseif str:match("^0[Oo][0-7]+$") then
				return parse_number_base(str:sub(3), "01234567")
			elseif str:match("^[0-9]+$") then
				return parse_number_base(str, "0123456789")
			end
			return false, "notation not recognised"
		end
		local function evaluate_composite(composite)
			if composite.type == "constant" then
				return composite.value
			end
			return composite.operator.does(function(ix)
				return evaluate_composite(composite.operands[ix])
			end)
		end
		function evaluate(tokens)
			local stack = {}
			do
				local cursor = 1
				while cursor <= #tokens do
					if tokens[cursor]:number() then
						local ok, number = parse_number(tokens[cursor].value)
						if not ok then
							return false, cursor, ("invalid number: %s"):format(number)
						end
						table.insert(stack, {
							type = "constant",
							value = number,
							position = cursor,
							depth = 1
						})
						cursor = cursor + 1
					elseif tokens[cursor]:punctuator() then
						local found
						for _, known_operator in ipairs(operators) do
							local matches = true
							for pos, ch in known_operator:gmatch("()(.)") do
								local relative = cursor + pos - 1
								if (relative > #tokens)
								or (pos < #known_operator and not tokens[cursor].whitespace_follows)
								or (not tokens[cursor]:punctuator(ch)) then
									matches = false
									break
								end
							end
							if matches then
								found = known_operator
								break
							end
						end
						if not found then
							return false, cursor, "unknown operator"
						end
						local operator = operator_funcs[found]
						if #stack < operator.pops then
							return false, cursor, ("operator takes %i operands, %i supplied"):format(operator.pops, #stack)
						end
						local max_depth = 0
						local operands = {}
						for ix = #stack - operator.pops + 1, #stack do
							if max_depth < stack[ix].depth then
								max_depth = stack[ix].depth
							end
							table.insert(operands, stack[ix])
							stack[ix] = nil
						end
						if max_depth > MAX_EVAL_DEPTH then
							return false, cursor, "maximum evaluation depth reached"
						end
						table.insert(stack, {
							type = "composite",
							operands = operands,
							operator = operator,
							position = cursor,
							depth = max_depth + 1
						})
						cursor = cursor + #found
					end
				end
			end
			if #stack > 1 then
				return false, stack[2].position, "excess value"
			end
			return true, evaluate_composite(stack[1])
		end
	end

-- * ---------------------------------------------------------------------------
-- * -- Preprocessing ----------------------------------------------------------
-- * ---------------------------------------------------------------------------
	local preprocess
	do
		local function reserved_identifier(str)
			return str:find("^_[_A-Z]") and true
		end

		local source_line_i = {}
		local source_line_mt = { __index = source_line_i }
		function source_line_i:dump_itop()
			local included_from = self.itop
			while included_from do
				printf.info("  included from %s:%i", included_from.path, included_from.line)
				included_from = included_from.next
			end
		end
		function source_line_i:blamef(report, format, ...)
			report("%s:%i: " .. format, self.path, self.line, ...)
			self:dump_itop()
		end
		function source_line_i:blamef_after(report, token, format, ...)
			report("%s:%i:%i " .. format, self.path, self.line, token.soffs + #token.value, ...)
			self:dump_itop()
		end

		local macro_invocation_unique = 0
		function preprocess(path, lines)
			local include_top = false
			local include_depth = 0

			local function preprocess_fail()
				failf("preprocessing stage failed, bailing")
			end

			local aliases = {}
			local function expand_aliases(tokens, first, last, depth)
				local expanded = {}
				for ix = first, last do
					local alias = tokens[ix]:identifier() and aliases[tokens[ix].value]
					if alias then
						if depth > MAX_EXPANSION_DEPTH then
							tokens[ix]:blamef(printf.err, "maximum expansion depth reached while expanding alias '%s'", tokens[ix].value)
							preprocess_fail()
						end
						for _, token in ipairs(expand_aliases(alias, 1, #alias, depth + 1, tokens[ix])) do
							table.insert(expanded, token:expand_by(tokens[ix]))
						end
					else
						table.insert(expanded, tokens[ix])
					end
				end
				return expanded
			end
			local function define(identifier, tokens, first, last)
				if aliases[identifier.value] then
					identifier:blamef(printf.err, "alias '%s' is defined", identifier.value)
					preprocess_fail()
				end
				local alias = {}
				for ix = first, last do
					table.insert(alias, tokens[ix])
				end
				aliases[identifier.value] = alias
			end
			local function undefine(identifier)
				if not aliases[identifier.value] then
					identifier:blamef(printf.err, "alias '%s' is not defined", identifier.value)
					preprocess_fail()
				end
				aliases[identifier.value] = nil
			end

			local macros = {}
			local defining_macro = false
			local function expand_macro(tokens, depth)
				local expanded = expand_aliases(tokens, 1, #tokens, depth + 1)
				local macro = expanded[1]:identifier() and macros[expanded[1].value]
				if macro then
					if depth > MAX_EXPANSION_DEPTH then
						expanded[1]:blamef(printf.err, "maximum expansion depth reached while expanding macro '%s'", expanded[1].value)
						preprocess_fail()
					end
					local expanded_lines = {}
					local parameter_cursor = 0
					local parameters_passed = {}
					local parameter_buffer = {}
					local function flush_parameter()
						parameters_passed[macro.params[parameter_cursor] or false] = parameter_buffer
						parameter_buffer = {}
					end
					if #expanded > 1 then
						parameter_cursor = 1
						for ix = 2, #expanded do
							if expanded[ix]:comma() then
								flush_parameter()
								parameter_cursor = parameter_cursor + 1
							else
								table.insert(parameter_buffer, expanded[ix])
							end
						end
						flush_parameter()
					end
					if #macro.params ~= parameter_cursor then
						expanded[1]:blamef(printf.err, "macro '%s' invoked with %i parameters, expects %i", expanded[1].value, parameter_cursor, #macro.params)
						preprocess_fail()
					end
					macro_invocation_unique = macro_invocation_unique + 1
					parameters_passed["_Unique"] = ("_%i_"):format(macro_invocation_unique)
					local old_aliases = {}
					for param, value in pairs(parameters_passed) do
						old_aliases[param] = aliases[param]
						aliases[param] = value
					end
					for _, line in ipairs(macro) do
						for _, expanded_line in ipairs(expand_macro(line.tokens, depth + 1)) do
							local cloned_line = {}
							for _, token in ipairs(expanded_line) do
								table.insert(cloned_line, token:expand_by(expanded[1]))
							end
							table.insert(expanded_lines, cloned_line)
						end
					end
					for param, value in pairs(parameters_passed) do
						aliases[param] = old_aliases[param]
					end
					return expanded_lines
				else
					return { expanded }
				end
			end
			local function macro(identifier, tokens, first, last)
				if macros[identifier.value] then
					identifier:blamef(printf.err, "macro '%s' is defined", identifier.value)
					preprocess_fail()
				end
				local params = {}
				local params_assoc = {}
				for ix = first, last, 2 do
					if not tokens[ix]:identifier() then
						tokens[ix]:blamef(printf.err, "expected parameter name")
						preprocess_fail()
					end
					if reserved_identifier(tokens[ix].value) then
						tokens[ix]:blamef(printf.err, "reserved identifier")
						preprocess_fail()
					end
					if params_assoc[tokens[ix].value] then
						tokens[ix]:blamef(printf.err, "duplicate parameter")
						preprocess_fail()
					end
					params_assoc[tokens[ix].value] = true
					table.insert(params, tokens[ix].value)
					if ix == last then
						break
					end
					if not tokens[ix + 1]:punctuator(",") then
						tokens[ix + 1]:blamef(printf.err, "expected comma")
						preprocess_fail()
					end
				end
				defining_macro = {
					params = params,
					name = identifier.value
				}
			end
			local function endmacro()
				macros[defining_macro.name] = defining_macro
				defining_macro = false
			end
			local function unmacro(identifier)
				if not macros[identifier.value] then
					identifier:blamef(printf.err, "macro '%s' is not defined", identifier.value)
					preprocess_fail()
				end
				macros[identifier.value] = nil
			end

			local condition_stack = { {
				condition = true,
				seen_else = false,
				been_true = true,
				opened_by = false
			} }

			local function include(path, lines, req)
				if include_depth > MAX_INCLUDE_DEPTH then
					req:blamef(printf.err, "maximum include depth reached while including '%s'", path)
					preprocess_fail()
				end
				local handle = io.open(path, "r")
				if not handle then
					req:blamef(printf.err, "failed to open '%s' for reading", path)
					preprocess_fail()
				end

				local line_number = 0
				for line in handle:lines() do
					line_number = line_number + 1
					local sline = setmetatable({
						path = path,
						line = line_number,
						itop = include_top,
						str = line
					}, source_line_mt)
					local ok, tokens, err = tokenise(sline)
					if not ok then
						printf.err("%s:%i:%i: %s", sline.path, sline.line, tokens, err)
						preprocess_fail()
					end
					if #tokens >= 1 and tokens[1]:punctuator("%") then
						if #tokens >= 2 and tokens[2]:identifier() then

							if tokens[2].value == "include" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected path")
										preprocess_fail()
									elseif not tokens[3]:stringlit() then
										tokens[3]:blamef(printf.err, "expected path")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									local relative_path = tokens[3].value:gsub("^\"(.*)\"$", "%1")
									local resolved_path = resolve_relative(path, relative_path)
									include_top = {
										path = path,
										line = line_number,
										next = include_top
									}
									include_depth = include_depth + 1
									include(resolved_path, lines, sline)
									include_depth = include_depth - 1
									include_top = include_top.next
								end

							elseif tokens[2].value == "warning" or tokens[2].value == "error" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected message")
										preprocess_fail()
									elseif not tokens[3]:stringlit() then
										tokens[3]:blamef(printf.err, "expected message")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									local err = tokens[3].value:gsub("^\"(.*)\"$", "%1")
									if tokens[2].value == "error" then
										printf.err("%s:%i: %%error: %s", path, line_number, err)
										preprocess_fail()
									else
										printf.warn("%s:%i: %%warning: %s", path, line_number, err)
									end
								end

							elseif tokens[2].value == "eval" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									if reserved_identifier(tokens[3].value) then
										tokens[3]:blamef(printf.err, "reserved identifier")
										preprocess_fail()
									end
									local expanded = expand_aliases(tokens, 4, #tokens, 0)
									local ok, result, err = evaluate(expanded)
									if not ok then
										expanded[result]:blamef(printf.err, "evaluation failed: %s", err)
										preprocess_fail()
									end
									define(tokens[3], { tokens[3]:point({
										type = "number",
										value = tostring(result)
									}) }, 1, 1)
								end

							elseif tokens[2].value == "define" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									if reserved_identifier(tokens[3].value) then
										tokens[3]:blamef(printf.err, "reserved identifier")
										preprocess_fail()
									end
									if #tokens == 3 then
										define(tokens[3], { tokens[3]:point({
											type = "number",
											value = "1"
										}) }, 1, 1)
									else
										define(tokens[3], tokens, 4, #tokens)
									end
								end

							elseif tokens[2].value == "undef" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected alias name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected alias name")
										preprocess_fail()
									end
									if reserved_identifier(tokens[3].value) then
										tokens[3]:blamef(printf.err, "reserved identifier")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									undefine(tokens[3])
								end

							elseif tokens[2].value == "if" then
								local expanded = expand_aliases(tokens, 3, #tokens, 0)
								local ok, result, err = evaluate(expanded)
								if not ok then
									expanded[result]:blamef(printf.err, "evaluation failed: %s", err)
									preprocess_fail()
								end
								local evals_to_true = result ~= 0
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "ifdef" then
								if #tokens < 3 then
									sline:blamef_after(printf.err, tokens[2], "expected alias name")
									preprocess_fail()
								elseif not tokens[3]:identifier() then
									tokens[3]:blamef(printf.err, "expected alias name")
									preprocess_fail()
								end
								if #tokens > 3 then
									tokens[4]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								local evals_to_true = aliases[tokens[3].value] and true
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "ifndef" then
								if #tokens < 3 then
									sline:blamef_after(printf.err, tokens[2], "expected alias name")
									preprocess_fail()
								elseif not tokens[3]:identifier() then
									tokens[3]:blamef(printf.err, "expected alias name")
									preprocess_fail()
								end
								if #tokens > 3 then
									tokens[4]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								local evals_to_true = not aliases[tokens[3].value] and true
								condition_stack[#condition_stack + 1] = {
									condition = evals_to_true,
									seen_else = false,
									been_true = evals_to_true,
									opened_by = tokens[2]
								}

							elseif tokens[2].value == "else" then
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%else")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].seen_else then
									tokens[2]:blamef(printf.err, "%%else after %%else")
									preprocess_fail()
								end
								condition_stack[#condition_stack].seen_else = true
								if condition_stack[#condition_stack].been_true then
									condition_stack[#condition_stack].condition = false
								else
									condition_stack[#condition_stack].condition = true
									condition_stack[#condition_stack].been_true = true
								end

							elseif tokens[2].value == "elif" then
								if #tokens > 2 then
									tokens[3]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%elif")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].seen_else then
									tokens[2]:blamef(printf.err, "%%elif after %%else")
									preprocess_fail()
								end
								if condition_stack[#condition_stack].been_true then
									condition_stack[#condition_stack].condition = false
								else
									local expanded = expand_aliases(tokens, 3, #tokens, 0)
									local ok, result, err = evaluate(expanded)
									if not ok then
										expanded[result]:blamef(printf.err, "evaluation failed: %s", err)
										preprocess_fail()
									end
									local evals_to_true = result ~= 0
									condition_stack[#condition_stack].condition = evals_to_true
									condition_stack[#condition_stack].been_true = evals_to_true
								end

							elseif tokens[2].value == "endif" then
								if #tokens > 2 then
									tokens[3]:blamef(printf.err, "expected end of line")
									preprocess_fail()
								end
								if #condition_stack == 1 then
									tokens[2]:blamef(printf.err, "unpaired %%endif")
									preprocess_fail()
								end
								condition_stack[#condition_stack] = nil

							elseif tokens[2].value == "macro" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected macro name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected macro name")
										preprocess_fail()
									end
									if reserved_identifier(tokens[3].value) then
										tokens[3]:blamef(printf.err, "reserved identifier")
										preprocess_fail()
									end
									if defining_macro then
										tokens[2]:blamef(printf.err, "%%macro after %%macro")
										preprocess_fail()
									end
									macro(tokens[3], tokens, 4, #tokens)
								end
								
							elseif tokens[2].value == "endmacro" then
								if condition_stack[#condition_stack].condition then
									if #tokens > 2 then
										tokens[3]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									if not defining_macro then
										tokens[2]:blamef(printf.err, "unpaired %%endmacro")
										preprocess_fail()
									end
									endmacro()
								end

							elseif tokens[2].value == "unmacro" then
								if condition_stack[#condition_stack].condition then
									if #tokens < 3 then
										sline:blamef_after(printf.err, tokens[2], "expected macro name")
										preprocess_fail()
									elseif not tokens[3]:identifier() then
										tokens[3]:blamef(printf.err, "expected macro name")
										preprocess_fail()
									end
									if reserved_identifier(tokens[3].value) then
										tokens[3]:blamef(printf.err, "reserved identifier")
										preprocess_fail()
									end
									if #tokens > 3 then
										tokens[4]:blamef(printf.err, "expected end of line")
										preprocess_fail()
									end
									unmacro(tokens[3])
								end

							else
								tokens[2]:blamef(printf.err, "unknown preprocessing directive")
								preprocess_fail()

							end
						end
					else
						if condition_stack[#condition_stack].condition and #tokens > 0 then
							if defining_macro then
								table.insert(defining_macro, {
									sline = sline,
									tokens = tokens
								})
							else
								for _, line in ipairs(expand_macro(tokens, 0)) do
									table.insert(lines, line)
								end
							end
						end
					end
				end
				handle:close()
			end

			include(path, lines, { blamef = function(self, report, ...)
				report(...)
			end })
			if #condition_stack > 1 then
				condition_stack[#condition_stack].opened_by:blamef(printf.err, "unfinished conditional block")
				preprocess_fail()
			end
		end
	end

-- * ---------------------------------------------------------------------------
-- * -- Everything else --------------------------------------------------------
-- * ---------------------------------------------------------------------------

	local named_args = {}
	local unnamed_args = {}
	-- * Get arguments. Some of those may not be strings when r3asm is run inside TPT.
	if #args == 1 and type(args[1]) == "table" then
		for ix_arg, arg in ipairs(args) do
			table.insert(unnamed_args, arg)
		end
		for key, arg in pairs(args) do
			if type(key) ~= "number" then
				unnamed_args[key] = arg
			end
		end
	else
		for ix_arg, arg in ipairs(args) do
			local key_value = type(arg) == "string" and { arg:match("^([^=]+)=(.+)$") }
			if key_value and key_value[1] then
				if named_args[key_value[1]] then
					printf.warn("argument #%i overrides earlier specification of %s", ix_arg, key_value[1])
				end
				named_args[key_value[1]] = key_value[2]
			else
				table.insert(unnamed_args, arg)
			end
		end
	end

	local log_path = named_args.log or unnamed_args[3]
	if log_path then
		printf.redirect(tostring(log_path))
	end

	local root_source_path = named_args.source or unnamed_args[1] or failf("no source specified")
	root_source_path = tostring(root_source_path)

	local lines = {}
	preprocess(root_source_path, lines)
	for _, ix_line in ipairs(lines) do
		for _, ix_token in ipairs(ix_line) do
			ix_token:blamef(printf.info, "%s [%s]", ix_token.value, ix_token.type)
		end
	end

	-- local target_cpu = named_args.target or unnamed_args[2]
	-- target_cpu = target_cpu and tonumber(target_cpu)


end, function(err)

	if err ~= failf then
		-- * Dang.
		printf.err("error: %s", tostring(err))
		printf.info("%s", debug.traceback())
		printf.info("this is an assembler bug, tell LBPHacker!")
		printf.info("https://github.com/LBPHacker/R316")
	end

end)

printf.unredirect()
printf.info("done")
