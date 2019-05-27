#include "timer.hpp"

#include "nice_error.hpp"

namespace r3emu::sdl
{
	timer::timer(Uint32 interval, callback cb_param) : cb(cb_param)
	{
		id = SDL_AddTimer(interval, wrapper, this);
		if (!id)
		{
			throw sdl::nice_error("SDL_AddTimer: ");
		}
	}

	timer::~timer()
	{
		SDL_RemoveTimer(id);
	}

	Uint32 timer::wrapper(Uint32 interval, void *param)
	{
		static_cast<timer *>(param)->cb();
		return interval;
	}
}
