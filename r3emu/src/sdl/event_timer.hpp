#pragma once

#include "timer.hpp"

namespace r3emu::sdl
{
	class event_timer : public timer
	{
	public:
		event_timer(Uint32 interval, Sint32 code);
	};
}
