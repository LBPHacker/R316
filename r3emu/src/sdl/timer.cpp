#include "timer.hpp"

#include "nice_error.hpp"

namespace r3emu::sdl
{
	timer::timer(callback cb_param) : cb(cb_param), active(false)
	{
	}

	timer::~timer()
	{
		if (active)
		{
			SDL_RemoveTimer(id);
		}
	}

	void timer::arm(Uint32 interval)
	{
		id = SDL_AddTimer(interval, wrapper, this);
		if (!id)
		{
			throw sdl::nice_error("SDL_AddTimer: ");
		}
		active = true;
	}

	Uint32 timer::wrapper(Uint32, void *param)
	{
		auto &tim = *static_cast<timer *>(param);
		tim.cb();
		tim.active = false;
		return 0;
	}
}
