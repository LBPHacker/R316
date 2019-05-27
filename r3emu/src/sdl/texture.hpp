#pragma once

#include <SDL.h>

namespace r3emu::sdl
{
	class texture
	{
		SDL_Texture *sdl_texture;

	public:
		texture(SDL_Renderer *renderer, int width, int height, bool target = false);
		~texture();

		operator SDL_Texture *() const;
	};
}
