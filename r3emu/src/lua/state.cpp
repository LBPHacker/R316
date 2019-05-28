#include "state.hpp"

#include <stdexcept>
#include <iostream>

namespace r3emu::lua
{
	state::state()
	{
		L = luaL_newstate();
		if (!L)
		{
			throw std::runtime_error("luaL_newstate returned 0");
		}
		luaL_openlibs(L);
	}

	state::~state()
	{
		lua_close(L);
	}
	
	state::operator lua_State *() const
	{
		return L;
	}

	void state::execute(std::string const &chunk, std::string const &code)
	{
		if (luaL_loadbuffer(L, code.data(), code.size(), chunk.c_str()) || lua_pcall(L, 0, 0, 0))
		{
			std::cerr << lua_tostring(L, -1) << std::endl;
			lua_pop(L, 1);
		}
	}

	bool state::execute_incomplete(std::string const &chunk, std::string const &code)
	{
		bool complete = true;
		if (luaL_loadbuffer(L, code.data(), code.size(), chunk.c_str()))
		{
			std::string err(lua_tostring(L, -1));
			if (err.find("<eof>") != err.npos)
			{
				complete = false;
			}
			else
			{
				std::cerr << err << std::endl;
			}
			lua_pop(L, 1);
		}
		else if (lua_pcall(L, 0, 0, 0))
		{
			std::cerr << lua_tostring(L, -1) << std::endl;
			lua_pop(L, 1);
		}
		return complete;
	}
}
