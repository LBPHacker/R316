#pragma once

#include <SDL.h>

namespace r3emu::sdl
{
	class window
	{
		SDL_Window *sdl_window;
		SDL_Renderer *sdl_renderer;

	public:
		window();
		~window();

		operator SDL_Window *() const;
		operator SDL_Renderer *() const;
	};
}
