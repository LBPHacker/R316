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
setfenv(1, setmetatable(env_copy, {__index = function()
	error("__index")
end, __newindex = function()
	error("__newindex")
end}))

local PATH_SEP
do
	local package_config = {}
	for conf in package.config:gmatch("[^\n]+") do
		table.insert(package_config, conf)
	end
	PATH_SEP = package_config[1]
end

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
	}, {__call = function(self, ...)
		self.print(string.format(...))
	end})
	function printf:debug(first, ...)
		local things = {tostring(first)}
		for ix_thing, thing in ipairs({...}) do
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

local function resolve_relative(base, relative)
	local dir = file_path:match("^(.+)" .. package_config[1] .. "[^" .. package_config[1] .. "]+$")
	return dir or (file_path .. package_config[1] .. "..")
end

--------------------------------------------------------------------------------
---- Tokenisation --------------------------------------------------------------
--------------------------------------------------------------------------------
local tokenise
do
	-- * The transition table is consulted whenever a new character is consumed
	--   from the line. This may result in a state change.
	-- * State changes occur when the transition table points to a state
	--   different from the currently active state. The transition table is
	--   consulted on these occasions as well, possibly yielding more state
	--   changes.
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
		for ix, ix_trans in ipairs(transition_list) do
			add_transition(ix_trans[1], ix_trans[2])
		end
		return tbl
	end

	transition.push = transitions({
		{        "'", { consume =  true, state = "quote1"       }},
		{       "\"", { consume =  true, state = "quote2"       }},
		{    "[;\n]", { consume = false, state = "done"         }},
		{        ",", { consume = false, state = "comma"        }},
		{    "[0-9]", { consume =  true, state = "number"       }},
		{"[_A-Za-z]", { consume =  true, state = "identifier"   }},
		{"[%[%]%(%)%+%-%*/%%:%?&#<>=!^~%.{}\\|@$]", { consume = false, state = "punctuator" }},
	})
	transition.identifier = transitions({
		{"[_A-Za-z0-9]", { consume =  true, state = "identifier" }},
		{         false, { consume = false, state = "push"       }},
	})
	transition.number = transitions({
		{"[_A-Za-z0-9]", { consume =  true, state = "number" }},
		{         false, { consume = false, state = "push"   }},
	})
	transition.quote1 = transitions({
		{ "'", { consume = true, state = "push"         }},
		{"\n", { error = "unfinished character literal" }},
	})
	transition.quote2 = transitions({
		{"\"", { consume = true, state = "push"      }},
		{"\n", { error = "unfinished string literal" }},
	})
	transition.comma = transitions({
		{",", { consume = true, state = "push" }},
	})
	transition.punctuator = transitions({
		{".", { consume = true, state = "push" }},
	})

	function tokenise(line)
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
				table.insert(tokens, {
					type = old_state,
					value = line:sub(token_begin, token_end)
				})
			end
		end
		if #tokens >= 2 and tokens[1].type == "punctuator" and tokens[1].value == "%" and tokens[2].type == "identifier" then
			table.remove(tokens, 1)
			tokens[1].type = "directive"
		elseif #tokens >= 1 and tokens[1].type == "identifier" then
			tokens[1].type = "verb"
		end
		return true, tokens
	end
end

--------------------------------------------------------------------------------
---- Preprocessing -------------------------------------------------------------
--------------------------------------------------------------------------------
local preprocess
do
	local include_stack = {}
	local function preprocess_failf(...)
		printf:err(...)
		for ix = #include_stack, 1, -1 do
			printf:info("  included from %s:%i", include_stack[ix].path, include_stack[ix].line)
		end
		failf("preprocessing stage failed, bailing")
	end
	function preprocess(path)
		if #include_stack > MAX_INCLUDE_DEPTH then
			preprocess_failf("max include depth reached while including '%s'", path)
		end
		local handle = io.open(path, "r")
		if not handle then
			preprocess_failf("failed to open '%s' for reading", path)
		end

		local line_number = 0
		for line in handle:lines() do
			line_number = line_number + 1
			local ok, tokens, err = tokenise(line)
			if ok then
				printf:info("line %i:", line_number)
				for ix, ix_token in ipairs(tokens) do
					printf:info("  %s [%s]", ix_token.value, ix_token.type)
				end
			else
				preprocess_failf("%s:%i:%i: %s", path, line_number, tokens, err)
			end
		end
		handle:close()
	end
end

--------------------------------------------------------------------------------
---- Putting it all together ---------------------------------------------------
--------------------------------------------------------------------------------
local args = {...}
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
			local key_value = type(arg) == "string" and {arg:match("^([^=]+)=(.+)$")}
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

	do
		local log_path = named_args.log or unnamed_args[3]
		if log_path then
			printf:redirect(tostring(log_path))
		end
	end

	local root_source_path = named_args.source or unnamed_args[1] or failf("no source specified")
	root_source_path = tostring(root_source_path)

	local commands = preprocess(root_source_path)

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
