#pragma once

#include <SDL.h>

namespace r3emu::utility
{
	class frequency_counter
	{
		Uint32 last_flush;
		int tick_count;
		int last_count;

	public:
		void reset();
		void tick();
		int get() const;
	};
}
