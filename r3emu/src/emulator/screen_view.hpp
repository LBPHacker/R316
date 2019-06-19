#pragma once

#include "../ui/view.hpp"

#include <string>

namespace r3emu::ui
{
	class host_window;
}

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class screen;

	class screen_view : public ui::view
	{
		lua::state &L;
		std::string name;
		screen &scr;

	public:
		screen_view(
			lua::state &L,
			std::string name,
			screen &scr,
			ui::host_window &hw,
			int x,
			int y
		);

		void draw() final override;
	};
}
