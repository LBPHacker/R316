#!/usr/bin/env lua

--------------------------------------------------------------------------------
---- Configuration -------------------------------------------------------------
--------------------------------------------------------------------------------
local MAX_INCLUDE_DEPTH = 100

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

--------------------------------------------------------------------------------
---- printf --------------------------------------------------------------------
--------------------------------------------------------------------------------
local printf
do
	printf = setmetatable({
		print = print,
		print_old = print,
		log_handle = false,
		colour = false,
		err_called = false
	}, { __call = function(self, ...)
		self.print(string.format(...))
	end })
	function printf:debug(first, ...)
		local things = { tostring(first) }
		for ix_thing, thing in ipairs({ ... }) do
			table.insert(things, tostring(thing))
		end
		self((self.colour and "[r3asm] " or "[r3asm] [DD] ") .. "%s", table.concat(things, "\t"))
	end
	function printf:info(format, ...)
		self((self.colour and "\008l[r3asm]\008w " or "[r3asm] [II] ") .. format, ...)
	end
	function printf:warn(format, ...)
		self((self.colour and "\008o[r3asm]\008w " or "[r3asm] [WW] ") .. format, ...)
	end
	function printf:err(format, ...)
		self((self.colour and "\008t[r3asm]\008w " or "[r3asm] [EE] ") .. format, ...)
		self.err_called = true
	end
	function printf:redirect(log_path)
		local handle = io.open(log_path, "w")
		if handle then
			self.log_path = log_path
			self.log_handle = handle
			self:info("redirecting log to '%s'", self.log_path)
			self.print = function(str)
				self.log_handle:write(str .. "\n")
			end
		else
			self:warn("failed to open '%s' for writing, log not redirected", log_path)
		end
	end
	function printf:unredirect()
		if self.log_handle then
			self.log_handle:close()
			self.log_handle = false
			self.print = self.print_old
			self:info("closed log '%s'", self.log_path)
		end
	end
	function printf:update_colour()
		self.colour = tpt and not self.log_handle
	end
	printf:update_colour()
end

-- * This prevents me from using print.
local print = nil

--------------------------------------------------------------------------------
---- Convenience functions -----------------------------------------------------
--------------------------------------------------------------------------------
local function failf(...)
	printf:err(...)
	error(failf)
end

local function resolve_relative(base_with_file, relative)
	local components = {}
	local parent_depth = 0
	for component in (base_with_file .. "/../" .. relative):gmatch("[^/]+") do
		if component == "." then
			-- nothing
		elseif component == ".." then
			if #components > 0 then
				components[#components] = nil
			else
				parent_depth = parent_depth + 1
			end
		else
			table.insert(components, component)
		end
	end
	for _ = 1, parent_depth do
		table.insert(components, 1, "..")
	end
	return table.concat(components, "/")
end

--------------------------------------------------------------------------------
---- Arguments -----------------------------------------------------------------
--------------------------------------------------------------------------------
local named_args = {}
local unnamed_args = {}
local populate_args
do
	local args = { ... }
	function populate_args()
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
						printf:warn("argument #%i overrides earlier specification of %s", ix_arg, key_value[1])
					end
					named_args[key_value[1]] = key_value[2]
				else
					table.insert(unnamed_args, arg)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
---- Tokenisation --------------------------------------------------------------
--------------------------------------------------------------------------------
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
	function token_i:blamef(failf, format, ...)
		failf("%s:%i:%i: " .. format, self.path, self.line, self.char, ...)
	end
	function token_i:blamef_after(failf, format, ...)
		failf("%s:%i:%i: " .. format, self.path, self.line, self.char + #self.value, ...)
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
		{ "[%[%]%(%)%+%-%*/%%:%?&#<>=!^~%.{}\\|@$,]", { consume = false, state = "punctuator" }},
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

	function tokenise(line, path, line_number)
		line = line .. "\n"
		local tokens = {}
		local state = "push"
		local token_begin
		local cursor = 1
		while cursor <= #line do
			local ch = line:byte(cursor)
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
					path = path,
					line = line_number,
					char = token_begin
				}, token_mt))
			end
		end
		return true, tokens
	end
end

local function blame_token(report, tokens, ix, ...)
	if tokens[ix] then
		tokens[ix]:blamef(report, ...)
	else
		tokens[ix - 1]:blamef_after(report, ...)
	end
end

--------------------------------------------------------------------------------
---- Preprocessing -------------------------------------------------------------
--------------------------------------------------------------------------------
local preprocess
do
	function preprocess(path, lines)
		local include_stack = {}

		local parent_failf = failf
		local function failf(...)
			printf:err(...)
			for ix = #include_stack, 1, -1 do
				printf:info("  included from %s:%i", include_stack[ix].path, include_stack[ix].line)
			end
			parent_failf("preprocessing stage failed, bailing")
		end

		local function include(path, lines)
			if #include_stack > MAX_INCLUDE_DEPTH then
				failf("max include depth reached while including '%s'", path)
			end
			local handle = io.open(path, "r")
			if not handle then
				failf("failed to open '%s' for reading", path)
			end

			local line_number = 0
			for line in handle:lines() do
				line_number = line_number + 1
				local ok, tokens, err = tokenise(line, path, line_number)
				if not ok then
					failf("%s:%i:%i: %s", path, line_number, tokens, err)
				end
				if #tokens >= 1 and tokens[1]:punctuator("%") then
					if #tokens >= 2 and tokens[2]:identifier() then

						if tokens[2].value == "include" then
							if not (#tokens >= 3 and tokens[3]:stringlit()) then
								blame_token(failf, tokens, 3, "expected path (string literal)")
							end
							local relative_path = tokens[3].value:gsub("^\"(.*)\"$", "%1")
							local resolved_path = resolve_relative(path, relative_path)
							include_stack[#include_stack + 1] = {
								path = path,
								line = line_number
							}
							include(resolved_path, lines)
							include_stack[#include_stack] = nil

						elseif tokens[2].value == "warning" or tokens[2].value == "error" then
							if not (#tokens >= 3 and tokens[3]:stringlit()) then
								blame_token(failf, tokens, 3, "expected message (string literal)")
							end
							local err = tokens[3].value:gsub("^\"(.*)\"$", "%1")
							if tokens[2].value == "error" then
								failf("%s:%i: %s: %s", path, line_number, tokens[2].value, err)
							else
								printf:warn("%s:%i: %s: %s", path, line_number, tokens[2].value, err)
							end

						else
							blame_token(failf, tokens, 2, "unknown preprocessing directive")

						end
					end
				else
					table.insert(lines, {
						path = path,
						line = line_number,
						tokens = tokens
					})
				end
			end
			handle:close()
		end

		include(path, lines)
	end
end

--------------------------------------------------------------------------------
---- Everything else -----------------------------------------------------------
--------------------------------------------------------------------------------
xpcall(function()

	populate_args()

	local log_path = named_args.log or unnamed_args[3]
	if log_path then
		printf:redirect(tostring(log_path))
	end

	local root_source_path = named_args.source or unnamed_args[1] or failf("no source specified")
	root_source_path = tostring(root_source_path)

	local lines = {}
	preprocess(root_source_path, lines)
	for _, ix_line in ipairs(lines) do
		printf:info("%s:%i:", ix_line.path, ix_line.line)
		for _, ix_token in ipairs(ix_line.tokens) do
			printf:info("  %s [%s]", ix_token.value, ix_token.type)
		end
	end

	-- local target_cpu = named_args.target or unnamed_args[2]
	-- target_cpu = target_cpu and tonumber(target_cpu)


end, function(err)
	
	if err ~= failf then
		-- * Dang.
		printf:err("error: %s", tostring(err))
		printf:info("traceback:\n  %s", debug.traceback():gsub("\n", "\n  "))
		printf:info("this is an assembler bug, tell LBPHacker!")
		printf:info("https://github.com/LBPHacker/R316")
	end

end)

printf:unredirect()
printf:info("done")
