#!/usr/bin/env lua

local MAX_INCLUDE_DEPTH = 100
local MAX_EXPANSION_DEPTH = 100
local MAX_EVAL_DEPTH = 100

local RESERVED_DEFINED  = "_Defined"
local RESERVED_DW       = "_Dw"
local RESERVED_IDENTITY = "_Identity"
local RESERVED_ORG      = "_Org"
local RESERVED_UNIQUE   = "_Unique"

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

	-- * Get arguments. Some of those may not be strings when r3asm is run inside TPT.
	local named_args = {}
	local unnamed_args = {}
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
			return quo, a - quo * b
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
			local lh = bit32_and(bit32_and(a, 0xFFFF) * math.floor(b / 0x10000), 0xFFFF)
			local hl = bit32_and(math.floor(a / 0x10000) * bit32_and(b, 0xFFFF), 0xFFFF)
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

	local function parse_parameter_list(expanded, first, last)
		local parameters = {}
		local parameter_buffer = {}
		local function flush_parameter()
			parameters[parameter_cursor] = parameter_buffer
			parameter_buffer = {}
		end
		local parameter_cursor = 0
		if first <= last then
			parameter_cursor = 1
			for ix = first, last do
				if expanded[ix]:punctuator(",") then
					flush_parameter()
					parameter_cursor = parameter_cursor + 1
				else
					table.insert(parameter_buffer, expanded[ix])
				end
			end
			flush_parameter()
		end
		return parameters
	end

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
		function token_i:charlit(...)
			return self:is("charlit", ...)
		end
		function token_i:number()
			return self:is("number")
		end
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
		function token_i:parse_number()
			local str = self.value
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
		function token_i:point(other)
			other.sline = self.sline
			other.soffs = self.soffs
			return setmetatable(other, token_mt)
		end
		function token_i:blamef_after(report, format, ...)
			self.sline:blamef_after(report, self, format, ...)
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

	local evaluate
	do
		local operator_funcs = {
			[">="] = { params = { "number", "number" }, does = function(a, b) return (a >= b) and 1 or 0 end },
			["<="] = { params = { "number", "number" }, does = function(a, b) return (a <= b) and 1 or 0 end },
			[">" ] = { params = { "number", "number" }, does = function(a, b) return (a >  b) and 1 or 0 end },
			["<" ] = { params = { "number", "number" }, does = function(a, b) return (a <  b) and 1 or 0 end },
			["=="] = { params = { "number", "number" }, does = function(a, b) return (a == b) and 1 or 0 end },
			["~="] = { params = { "number", "number" }, does = function(a, b) return (a ~= b) and 1 or 0 end },
			["&&"] = { params = { "number", "number" }, does = function(a, b) return (a ~= 0 and b ~= 0) and 1 or 0 end },
			["||"] = { params = { "number", "number" }, does = function(a, b) return (a ~= 0 or  b ~= 0) and 1 or 0 end },
			["!" ] = { params = { "number"           }, does = function(a) return (a == 0) and 1 or 0 end },
			["~" ] = { params = { "number"           }, does = function(a) return bit32_xor(a, 0xFFFFFFFF) end },
			["<<"] = { params = { "number", "number" }, does = bit32_lshift },
			[">>"] = { params = { "number", "number" }, does = bit32_rshift },
			["-" ] = { params = { "number", "number" }, does =    bit32_sub },
			["+" ] = { params = { "number", "number" }, does =    bit32_add },
			["/" ] = { params = { "number", "number" }, does =    bit32_div },
			["%" ] = { params = { "number", "number" }, does =    bit32_mod },
			["*" ] = { params = { "number", "number" }, does =    bit32_mul },
			["&" ] = { params = { "number", "number" }, does =    bit32_and },
			["|" ] = { params = { "number", "number" }, does =     bit32_or },
			["^" ] = { params = { "number", "number" }, does =    bit32_xor },
			[RESERVED_DEFINED] = { params = { "alias" }, does = function(a) return a and 1 or 0 end },
			[RESERVED_IDENTITY] = { params = { "number" }, does = function(a) return a end },
		}
		local operators = {}
		for key in pairs(operator_funcs) do
			table.insert(operators, key)
		end
		table.sort(operators, function(a, b)
			return #a > #b
		end)

		local function evaluate_composite(composite)
			if composite.type == "number" then
				return composite.value
			end
			return composite.operator.does(function(ix)
				return evaluate_composite(composite.operands[ix])
			end)
		end

		function evaluate(tokens, cursor, last, aliases)
			local stack = {}

			local function apply_operator(operator_name)
				local operator = operator_funcs[operator_name]
				if #stack < #operator.params then
					return false, cursor, ("operator takes %i operands, %i supplied"):format(#operator.params, #stack)
				end
				local max_depth = 0
				local operands = {}
				for ix = #stack - #operator.params + 1, #stack do
					if max_depth < stack[ix].depth then
						max_depth = stack[ix].depth
					end
					table.insert(operands, stack[ix])
					stack[ix] = nil
				end
				if max_depth > MAX_EVAL_DEPTH then
					return false, cursor, "maximum evaluation depth reached"
				end
				for ix = 1, #operands do
					if operator.params[ix] == "number" then
						if operands[ix].type == "number" then
							operands[ix] = operands[ix].value
						elseif operands[ix].type == "alias" then
							local alias = operands[ix].value
							if alias then
								local ok, number = alias[1]:parse_number()
								operands[ix] = (#alias == 1 and ok) and number or 1
							else
								operands[ix] = 0
							end
						else
							return false, operands[ix].position, ("operand %i is %s, should be number"):format(ix, operands[ix].type)
						end
					elseif operator.params[ix] == "alias" then
						if operands[ix].type == "alias" then
							operands[ix] = operands[ix].value
						else
							return false, operands[ix].position, ("operand %i is %s, should be alias"):format(ix, operands[ix].type)
						end
					end
				end
				table.insert(stack, {
					type = "number",
					value = operator.does(unpack(operands)),
					position = cursor,
					depth = max_depth + 1
				})
			end

			while cursor <= last do
				if tokens[cursor]:number() then
					local ok, number = tokens[cursor]:parse_number()
					if not ok then
						return false, cursor, ("invalid number: %s"):format(number)
					end
					table.insert(stack, {
						type = "number",
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
							if (relative > last)
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
					apply_operator(found)
					cursor = cursor + #found
				elseif tokens[cursor]:identifier() and operator_funcs[tokens[cursor].value] then
					apply_operator(tokens[cursor].value)
				elseif token[cursor]:identifier() then
					table.insert(stack, {
						type = "alias",
						value = aliases[token[cursor].value] or false,
						position = cursor,
						depth = 1
					})
					cursor = cursor + 1
				else
					return false, cursor, "not a number, an identifier or an operator"
				end
			end

			apply_operator(RESERVED_IDENTITY)
			if #stack > 1 then
				return false, stack[2].position, "excess value"
			end
			if #stack < 1 then
				return false, 1, "no value"
			end
			return true, stack[1].value
		end
	end

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
		function preprocess(path)
			local lines = {}
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
			local function undef(identifier)
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
					local parameters_passed = {}
					for ix, ix_param in ipairs(parse_parameter_list(expanded, 2, #expanded)) do
						parameters_passed[macro.params[ix] or false] = ix_param
					end
					if #macro.params ~= parameter_cursor then
						expanded[1]:blamef(printf.err, "macro '%s' invoked with %i parameters, expects %i", expanded[1].value, parameter_cursor, #macro.params)
						preprocess_fail()
					end
					macro_invocation_unique = macro_invocation_unique + 1
					parameters_passed[RESERVED_UNIQUE] = ("_%i_"):format(macro_invocation_unique)
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
									local ok, result, err = evaluate(tokens, 4, #tokens, aliases)
									if not ok then
										tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
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
									undef(tokens[3])
								end

							elseif tokens[2].value == "if" then
								local ok, result, err = evaluate(tokens, 3, #tokens, aliases)
								if not ok then
									tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
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
									local ok, result, err = evaluate(tokens, 3, #tokens, aliases)
									if not ok then
										tokens[result]:blamef(printf.err, "evaluation failed: %s", err)
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

			return lines
		end
	end

	local resolve_instructions
	do
		local builtin_entities = {
			["r0"] = { type = "register", offset = 0 }
			-- TODO
		}
		local builtin_mnemonics = {
			["mov"] = {
				["register , register"  ] = { length = 1, emit = function() end },
				["register , number"    ] = { length = 1, emit = function() end },
				["register , [ number ]"] = { length = 1, emit = function() end },
			}
			-- TODO
		}

		function resolve_instructions(lines)
			local label_context = {}
			local output_pointer = 0
			local to_emit = {}
			local labels = {}

			local hooks = {}
			hooks[RESERVED_ORG] = function(hook_token, parameters)
				-- * Maybe put this in a nice type-checking wrapper for hooks?
				if #parameters < 1 then
					hook_token:blamef_after(printf.err, "expected origin")
					return
				end
				if #parameters > 1 then
					parameters[1][#parameters[1]]:blamef_after(printf.err, "excess parameters")
					return
				end
				local org_pack = parameters[1]
				if #org_pack > 1 then
					org_pack[2]:blamef(printf.err, "excess tokens")
					return
				end
				local org = org_pack[1]
				if not org:number() then
					org:blamef(printf.err, "not a number")
					return
				end
				local ok, number = org:parse_number()
				if not ok then
					org:blamef(printf.err, "invalid number: %s", number)
					return
				end
				output_pointer = number
			end
			hooks[RESERVED_DW] = function(hook_token, parameters)
				-- TODO
			end

			local known_identifiers = {}
			for key in pairs(builtin_entities) do
				known_identifiers[key] = true
			end
			for key in pairs(builtin_mnemonics) do
				known_identifiers[key] = true
			end
			for key in pairs(hooks) do
				known_identifiers[key] = true
			end

			for _, tokens in ipairs(lines) do
				local line_failed = false

				if not line_failed then
					local cursor = #tokens
					while cursor >= 1 do
						if tokens[cursor]:stringlit() then
							while cursor > 1 and tokens[cursor - 1]:stringlit() do
								tokens[cursor - 1].value = tokens[cursor - 1].value .. tokens[cursor].value
								table.remove(tokens, cursor)
								cursor = cursor - 1
							end
						elseif tokens[cursor]:charlit() then
							while cursor > 1 and tokens[cursor - 1]:charlit() do
								tokens[cursor - 1].value = tokens[cursor - 1].value .. tokens[cursor].value
								table.remove(tokens, cursor)
								cursor = cursor - 1
							end
						elseif tokens[cursor]:identifier() and not known_identifiers[tokens[cursor].value] then
							while cursor > 1 and tokens[cursor - 1]:identifier() and not known_identifiers[tokens[cursor - 1].value] do
								tokens[cursor - 1].value = tokens[cursor - 1].value .. tokens[cursor].value
								table.remove(tokens, cursor)
								cursor = cursor - 1
							end
							while cursor > 1 and tokens[cursor - 1]:punctuator(".") do
								tokens[cursor - 1].value = "." .. tokens[cursor].value
								tokens[cursor - 1].type = "identifier"
								table.remove(tokens, cursor)
								cursor = cursor - 1
							end
							tokens[cursor].type = "label"
						end
						cursor = cursor - 1
					end
				end

				if not line_failed then
					local cursor = 1
					while cursor <= #tokens do
						if tokens[cursor]:punctuator("{") then
							local brace_end = cursor + 1
							local last
							while brace_end <= #tokens do
								if tokens[brace_end]:punctuator("}") then
									last = brace_end
									break
								end
							end
							if not last then
								tokens[cursor]:blamef(printf.err, "unfinished evalation block")
								line_failed = true
								break
							end
							local eval_tokens = {}
							for ix = cursor + 1, last - 1 do
								table.remove(eval_tokens, tokens[ix])
							end
							for _ = cursor + 1, last do
								table.remove(tokens, cursor + 1)
							end
							tokens[cursor].type = "evaluation"
							tokens[cursor].value = eval_tokens
						end
						cursor = cursor + 1
					end
				end

				if not line_failed then
					if #tokens == 2 and tokens[1]:is("label") and not known_identifiers[tokens[1].value] and tokens[2]:punctuator(":") then
						local dots, rest = tokens[1].value:match("^(%.*)(.+)$")
						local level = #dots
						if level > #label_context then
							tokens[1]:blamef(printf.err, "level %i label declaration without preceding level %i label declaration", level, level - 1)
							line_failed = true
						else
							for ix = level + 1, #label_context do
								label_context[ix] = nil
							end
							label_context[level + 1] = rest
							labels[table.concat(label_context, ".")] = output_pointer
						end
					elseif #tokens >= 1 and tokens[1]:identifier() and builtin_mnemonics[tokens[1].value] then
						local canonical_form = {}
						local parameters = {}
						for ix = 2, #tokens do
							if tokens[ix]:is("number") or tokens[ix]:is("label") or tokens[ix]:is("evaluation") then
								table.insert(canonical_form, "number")
								if tokens[ix]:is("label") then
									local dots, rest = tokens[ix].value:match("^(%.*)(.+)$")
									local level = #dots
									if level > #label_context then
										tokens[ix]:blamef(printf.err, "level %i label reference without preceding level %i label declaration", level, level - 1)
										line_failed = true
									else
										tokens[ix].value = table.concat(label_context, ".", 1, level) .. "." .. rest
									end
								end
								table.insert(parameters, tokens[ix])
							elseif tokens[ix]:identifier() and builtin_entities[tokens[ix].value] then
								table.insert(canonical_form, builtin_entities[tokens[ix].value].type)
								table.insert(parameters, builtin_entities[tokens[ix].value])
							elseif tokens[ix]:punctuator() then
								table.insert(canonical_form, tokens[ix].value)
							else
								tokens[ix]:blamef(printf.err, "not a number, a label, an evaluation block or any other known entity", level, level - 1)
								line_failed = true
								break
							end
						end
						if not line_failed then
							local canonical_str = table.concat(canonical_form, " ")
							local operand_patterns = builtin_mnemonics[tokens[1].value]
							local desc = operand_patterns[canonical_str]
							if desc then
								local overwrites = {}
								for ix = output_pointer, output_pointer + desc.length - 1 do
									local overwritten = to_emit[ix]
									if overwritten then
										overwrites[overwritten] = true
									end
								end
								if next(overwrites) then
									local overwritten_count = 0
									for _ in pairs(overwrites) do
										overwritten_count = overwritten_count + 1
									end
									tokens[1]:blamef(printf.warn, "opcode emitted here (offs 0x%X, size %i) overwrites the following %i opcodes:", output_pointer, desc.length, overwritten_count)
									for overwritten in pairs(overwrites) do
										overwritten.emitted_by:blamef(printf.info, "opcode emitted here (offs 0x%X, size %i)", overwritten.offset, overwritten.length)
									end
								end
								to_emit[output_pointer] = {
									emit = desc.emit,
									offset = output_pointer,
									length = desc.length,
									parameters = parameters,
									emitted_by = tokens[1]
								}
								to_emit[output_pointer].head = to_emit[output_pointer]
								for ix = output_pointer + 1, output_pointer + desc.length - 1 do
									to_emit[ix] = {
										head = to_emit[output_pointer]
									}
								end
								output_pointer = output_pointer + desc.length
							else
								tokens[1]:blamef(printf.err, "invalid operand list")
								line_failed = true
							end
						end
					elseif #tokens >= 1 and tokens[1]:identifier() and hooks[tokens[1].value] then
						hooks[tokens[1].value](tokens[1], parse_parameter_list(tokens, 2, #tokens))
					else
						tokens[1]:blamef(printf.err, "expected label declaration, instruction or hook invocation")
					end
				end
			end
			if printf.err_called then
				failf("instruction resolution stage failed, bailing")
			end

			return to_emit, labels
		end
	end

	local emit_opcodes
	do
		function emit_opcodes(to_emit, labels)
			local opcodes = {}
			-- TODO

			return opcodes
		end
	end

	local root_source_path = tostring(named_args.source or unnamed_args[1] or failf("no source specified"))
	local lines = preprocess(root_source_path)
	local to_emit, labels = resolve_instructions(lines)
	local opcodes = emit_opcodes(to_emit, labels)

	local target = named_args.target or unnamed_args[2]
	if type(target) == "table" then
		for ix, ix_opcode in ipairs(opcodes) do
			target[ix] = ix_opcode
		end
	else
		failf("you'll have to wait until I build the R3 for this feature to work")
	end

	-- TODO: actually flash opcodes into FILT (prerequisite: build R3)

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
