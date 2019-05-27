#pragma once

#include "../ui/view.hpp"

#include <SDL.h>
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
	class core;
	class simulation;

	class core_view : public ui::view
	{
		lua::state &L;
		std::string name;
		core &co;
		simulation &sim;

		int fps, ups;
		Uint32 last_fps_ups_tick;

	public:
		core_view(lua::state &L, std::string name, core &co, simulation &sim, ui::host_window &hw);

		void draw() final override;
		void frame() final override;
	};
}
