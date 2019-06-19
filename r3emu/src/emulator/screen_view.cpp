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
		copy(0, 0, 128, 128, scr.buffer);
	}
}
