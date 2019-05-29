#include "disassembler_view.hpp"

#include "memory.hpp"
#include "../ui/host_window.hpp"
#include "../config.hpp"
#include "../lua/state.hpp"

namespace r3emu::emulator
{
	disassembler_view::disassembler_view(
		lua::state &L_param,
		std::string name_param,
		memory &mem_param,
		ui::host_window &hw_param
	) :
		view(32, 16, "Disassembly", hw_param),
		L(L_param),
		name(name_param),
		mem(mem_param)
	{
		top = 0;
		highlight = 0;

		lua_newtable(L);

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *dis = static_cast<disassembler_view *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			dis->highlight = addr;
			return 0;
		}, "highlight");

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *dis = static_cast<disassembler_view *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			dis->top = addr;
			return 0;
		}, "show");

		lua_setglobal(L, name.c_str());
	}

	void disassembler_view::draw()
	{
		for (auto y = 0U; y < 16U; ++y)
		{
			uint16_t addr = (top + y) & ((1 << config::memory_size) - 1);
			uint32_t instr = mem.data[addr];
			auto colour_default = addr == highlight ? (0xFF - config::colour_default) : config::colour_default;
			auto colour_frame   = addr == highlight ? (0xFF - config::colour_frame  ) : config::colour_frame;
			hw.write_16(0, y, addr, 4, colour_frame);
			hw.write(4, y, " ", colour_default);
			hw.write_16(5, y, instr, 8, colour_default);
			hw.write(13, y, "                   ", colour_default);
		}
	}
}
