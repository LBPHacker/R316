#include "memory.hpp"

#include "../config.hpp"
#include "../lua/state.hpp"

#include <iostream>
#include <iomanip>

namespace r3emu::emulator
{
	memory::memory(lua::state &L_param, std::string name_param) :
		data(1 << config::memory_size),
		L(L_param),
		name(name_param)
	{
		lua_newtable(L);

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *mem = static_cast<memory *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			uint32_t value = luaL_checkinteger(L, 2);
			if (addr < (1 << config::memory_size))
			{
				mem->data[addr] = value;
			}
			else
			{
				luaL_error(L, "out-of-bounds write: data[0x%04X] = 0x%08X", addr, value);
			}
			return 0;
		}, "write");

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *mem = static_cast<memory *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			if (addr < (1 << config::memory_size))
			{
				lua_pushinteger(L, mem->data[addr]);
				return 1;
			}
			else
			{
				luaL_error(L, "out-of-bounds read: return data[0x%04X]", addr);
			}
			return 0;
		}, "read");

		lua_setglobal(L, name.c_str());
	}
}
