#pragma once

#include <lua.hpp>
#include <string>

namespace r3emu::lua
{
	class state
	{
		lua_State *L;

	public:
		state();
		~state();

		operator lua_State *() const;
		void set_ugly_func(void *upv, lua_CFunction func, std::string const &name);
		void global_callback(std::string const &name);
		void execute(std::string const &chunk, std::string const &code);
		bool execute_incomplete(std::string const &chunk, std::string const &code);
	};
}
