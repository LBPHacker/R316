#include "window.hpp"

#include "context.hpp"
#include "nice_error.hpp"

namespace r3emu::sdl
{
	window::window()
	{
		if (SDL_CreateWindowAndRenderer(1, 1, 0, &sdl_window, &sdl_renderer))
		{
			throw sdl::nice_error("SDL_CreateWindowAndRenderer");
		}
	}

	window::~window()
	{
		SDL_DestroyRenderer(sdl_renderer);
		SDL_DestroyWindow(sdl_window);
	}

	window::operator SDL_Window *() const
	{
		return sdl_window;
	}

	window::operator SDL_Renderer *() const
	{
		return sdl_renderer;
	}
}
