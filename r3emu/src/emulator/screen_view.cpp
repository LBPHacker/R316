#include "screen_view.hpp"

#include "bus.hpp"
#include "screen.hpp"
#include "../ui/host_window.hpp"

namespace r3emu::emulator
{
	screen_view::screen_view(
		lua::state &L_param, std::string name_param, screen &scr_param, ui::host_window &hw_param
	) :
		view(16, 16, "Screen", hw_param),
		L(L_param),
		name(name_param),
		scr(scr_param)
	{
	}

	void screen_view::draw()
	{
		for (auto y = 0U; y < 16U; ++y)
		{
			for (auto x = 0U; x < 16U; ++x)
			{
				auto &block = scr.blocks[y * 16 + x];
				hw.write(x, y, std::string(1, block.ch), block.bgfg);
			}
		}
	}
}
