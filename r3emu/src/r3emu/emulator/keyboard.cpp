#include "keyboard.hpp"

#include "../config.hpp"
#include "../ui/host_window.hpp"
#include "../ui/font_texture.hpp"
#include "../colours.hpp"
#include "../lua/state.hpp"

namespace r3emu::emulator
{
	keyboard::keyboard(
		lua::state &L_param,
		std::string name_param,
		bus &bu_param
	) :
		peripheral(bu_param),
		L(L_param),
		name(name_param)
	{
		lua_newtable(L);

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *kbd = static_cast<keyboard *>(lua_touserdata(L, lua_upvalueindex(1)));
			kbd->buffer = luaL_checkstring(L, 1);
			return 0;
		}, "set_buffer");

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *kbd = static_cast<keyboard *>(lua_touserdata(L, lua_upvalueindex(1)));
			lua_pushstring(L, kbd->buffer.c_str());
			return 1;
		}, "get_buffer");

		lua_setglobal(L, name.c_str());

		current = 0;
	}

	keyboard::~keyboard()
	{
	}

	void keyboard::post_spread()
	{
		if (!current && !buffer.empty())
		{
			current = buffer[0];
			buffer = buffer.substr(1);
		}
	}

	void keyboard::gather(bool read, uint16_t addr, uint32_t &value)
	{
		if (read)
		{
			if (addr == config::mm_keyboard_input)
			{
				value = current;
			}
		}
	}

	void keyboard::spread(bool write, uint16_t addr, uint32_t value)
	{
		if (write)
		{
			if (addr == config::mm_keyboard_input)
			{
				current = value;
			}
		}
	}
}
