#include "font_texture.hpp"

#include "../../data/font.hpp"

namespace r3emu::ui
{
	font_texture::font_texture(SDL_Renderer *renderer) :
		sdl::texture(renderer, 128, 128)
	{
		void *data;
		int pitch;
		SDL_LockTexture(*this, NULL, &data, &pitch);
		char *pixels = static_cast<char *>(data);
		for (auto y = 0; y < 128; ++y)
		{
			for (auto x = 0; x < 128; ++x)
			{
				pixels[0] = (::font[(y / 8) * 16 + (x / 8)][y % 8] & (1 << (x % 8))) != 0 ? '\xFF' : '\x00';
				pixels[1] = pixels[2] = pixels[3] = '\xFF';
				pixels += 4;
			}
		}
		SDL_UnlockTexture(*this);
	}
}
