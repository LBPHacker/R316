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
		bool execute(std::string const &chunk, std::string const &code);
	};
}
