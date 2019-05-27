#include "nice_error.hpp"

#include <SDL.h>

namespace r3emu::sdl
{
	nice_error::nice_error(std::string origin) :
		std::runtime_error(origin + ": " + SDL_GetError())
	{
	}
}
