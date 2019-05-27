#include "context.hpp"

#include "nice_error.hpp"

#include <string>

namespace r3emu::sdl
{
	context::context()
	{
		if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0)
		{
			throw sdl::nice_error("SDL_Init");
		}

		sdl_event_type = SDL_RegisterEvents(1);
	}

	context::~context()
	{
		SDL_Quit();
	}

	Uint32 context::sdl_event_type;
}
