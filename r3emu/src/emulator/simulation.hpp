#pragma once

#include <string>

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class core;

	class simulation
	{
		bool paused;
		bool request_cycle;
		bool request_subcycle;

		lua::state &L;
		std::string name;
		core &co;

	public:
		simulation(lua::state &L, std::string name, core &co);

		void step(bool subcycle);
		void toggle_pause();
		void update();
		bool is_paused() const;
	};
}
