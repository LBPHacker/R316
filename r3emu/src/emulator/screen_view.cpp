#include "screen_view.hpp"

#include "../config.hpp"

#include "bus.hpp"
#include "screen.hpp"
#include "../ui/host_window.hpp"

namespace r3emu::emulator
{
	screen_view::screen_view(
		lua::state &L_param,
		std::string name_param,
		screen &scr_param,
		ui::host_window &hw_param,
		int x,
		int y
	) :
		view(16, 16, x, y, "Screen", hw_param),
		L(L_param),
		name(name_param),
		scr(scr_param)
	{
	}

	void screen_view::draw()
	{
		switch (scr.mode)
		{
		case screen::mode_char8x8:
			for (auto y = 0U; y < 16U; ++y)
			{
				for (auto x = 0U; x < 16U; ++x)
				{
					auto block = scr.blocks[y * 16 + x];
					write(x, y, std::string(1, block & 0xFF), block >> 8);
				}
			}
			break;

		case screen::mode_4bit4x4:
			break;

		case screen::mode_1bit2x2:
			break;
		}
	}
}
