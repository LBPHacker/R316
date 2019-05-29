#include "memory.hpp"

#include "../config.hpp"
#include "../lua/state.hpp"

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
			mem->data[addr] = value;
			return 0;
		}, "write");

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *mem = static_cast<memory *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			lua_pushinteger(L, mem->data[addr]);
			return 1;
		}, "read");

		lua_setglobal(L, name.c_str());
	}
}
