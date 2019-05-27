#include "frequency_counter.hpp"

namespace r3emu::utility
{
	void frequency_counter::reset()
	{
		tick_count = 0;
		last_count = 0;
		last_flush = SDL_GetTicks();
	}

	void frequency_counter::tick()
	{
		tick_count += 1;
		Uint32 current_tick = SDL_GetTicks();
		if (current_tick - last_flush >= 1000)
		{
			last_count = tick_count;
			tick_count = 0;
			last_flush = current_tick;
		}
	}

	int frequency_counter::get() const
	{
		return last_count;
	}
}
