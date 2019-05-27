#include "texture.hpp"

#include "nice_error.hpp"

namespace r3emu::sdl
{
	texture::texture(SDL_Renderer *renderer, int width, int height, bool target)
	{
		sdl_texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB32, target ? SDL_TEXTUREACCESS_TARGET : SDL_TEXTUREACCESS_STREAMING, width, height);
		if (!sdl_texture)
		{
			throw sdl::nice_error("SDL_CreateTexture");
		}
	}

	texture::~texture()
	{
		SDL_DestroyTexture(sdl_texture);
	}

	texture::operator SDL_Texture *() const
	{
		return sdl_texture;
	}
}
