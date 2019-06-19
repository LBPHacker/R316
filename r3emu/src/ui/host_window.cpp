#include "host_window.hpp"

#include "view.hpp"
#include "font_texture.hpp"
#include "../../data/colours.hpp"

#include <map>

namespace r3emu::ui
{
	host_window::host_window()
	{
		ft = std::make_unique<font_texture>(*this);
	}

	host_window::~host_window()
	{
	}

	void host_window::init_render_target()
	{
		int min_x = 1000000000;
		int min_y = 1000000000;
		int max_x = -1000000000;
		int max_y = -1000000000;
		for (auto v : views)
		{
			int left = v->position_x;
			int top = v->position_y;
			int right = v->position_x + v->width + 1;
			int bottom = v->position_y + v->height + 1;
			if (min_x >   left) min_x =   left;
			if (min_y >    top) min_y =    top;
			if (max_x <  right) max_x =  right;
			if (max_y < bottom) max_y = bottom;
		}

		int width = max_x - min_x + 1;
		int height = max_y - min_y + 1;

		global_offs_x = -min_x;
		global_offs_y = -min_y;
		width *= 8;
		height *= 8;

		rt = std::make_unique<sdl::texture>(*this, width, height, true);
		SDL_SetWindowSize(*this, width * config::scale, height * config::scale);
	}

	void host_window::frame()
	{
		struct position
		{
			int x, y;

			bool operator <(position const &other) const
			{
				if (x < other.x) return  true;
				if (x > other.x) return false;
				if (y < other.y) return  true;
				if (y > other.y) return false;
				return false;
			}
		};

		std::map<position, int> borders;
		for (auto v : views)
		{
			for (auto y = v->position_y + 1; y < v->position_y + v->height + 1; ++y)
			{
				borders[position{ v->position_x               , y }] |= 0x5; // up and down
				borders[position{ v->position_x + v->width + 1, y }] |= 0x5; // up and down
			}
			for (auto x = v->position_x + 1; x < v->position_x + v->width + 1; ++x)
			{
				borders[position{ x, v->position_y                 }] |= 0xA; // left and right
				borders[position{ x, v->position_y + v->height + 1 }] |= 0xA; // left and right
			}
			borders[position{ v->position_x, v->position_y }] |= 0xC; // down and right
			borders[position{ v->position_x + v->width + 1, v->position_y }] |= 0x6; // down and left
			borders[position{ v->position_x, v->position_y + v->height + 1 }] |= 0x9; // up and right
			borders[position{ v->position_x + v->width + 1, v->position_y + v->height + 1 }] |= 0x3; // up and left
		}

		for (auto &pair : borders)
		{
			static const char *border_strings[16] = {
				"\x20", "\xF9", "\xF8", "\x9B",
				"\xFB", "\x83", "\x93", "\xAB",
				"\xFA", "\x97", "\x81", "\xBB",
				"\x8F", "\xA3", "\xB3", "\xCB"
			};
			write(pair.first.x, pair.first.y, border_strings[pair.second], config::colour_frame);
		}

		for (auto v : views)
		{
			write(v->position_x + 1, v->position_y, v->title, config::colour_title);
		}
	}

	void host_window::init_views()
	{
		init_render_target();

		SDL_SetRenderTarget(*this, *rt);
		unsigned char bg = config::colour_clear >> 4;
		SDL_SetRenderDrawColor(*this, ::colours[bg].r, ::colours[bg].g, ::colours[bg].b, 0xFF);
		SDL_RenderClear(*this);

		frame();
	}

	void host_window::add_view(view &v)
	{
		views.push_back(&v);
	}

	void host_window::draw()
	{
		SDL_SetRenderTarget(*this, *rt);
		for (auto v : views)
		{
			v->draw();
		}

		SDL_SetRenderTarget(*this, NULL);
		SDL_RenderClear(*this);
		SDL_RenderCopy(*this, *rt, NULL, NULL);
		SDL_RenderPresent(*this);
	}

	void host_window::write(int x, int y, std::string str, unsigned char bgfg)
	{
		unsigned char bg = bgfg >> 4;
		unsigned char fg = bgfg & 0xF;
		SDL_SetRenderDrawColor(*this, ::colours[bg].r, ::colours[bg].g, ::colours[bg].b, 0xFF);
		SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_BLEND);
		SDL_SetTextureColorMod(*ft, ::colours[fg].r, ::colours[fg].g, ::colours[fg].b);
		SDL_Rect src, dest;
		dest.x = (global_offs_x + x) * 8;
		dest.y = (global_offs_y + y) * 8;
		dest.w = 8;
		dest.h = 8;
		src.w = 8;
		src.h = 8;
		for (unsigned char ch : str)
		{
			src.x = (ch % 16) * 8;
			src.y = (ch / 16) * 8;
			SDL_RenderFillRect(*this, &dest);
			SDL_RenderCopy(*this, *ft, &src, &dest);
			dest.x += 8;
			x += 1;
		}
	}

	void host_window::rect(int x, int y, int w, int h, unsigned char c)
	{
		SDL_SetRenderDrawColor(*this, ::colours[c & 0xF].r, ::colours[c & 0xF].g, ::colours[c & 0xF].b, 0xFF);
		SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_NONE);
		SDL_Rect rect;
		rect.x = global_offs_x * 8 + x;
		rect.y = global_offs_y * 8 + y;
		rect.w = w;
		rect.h = h;
		SDL_RenderFillRect(*this, &rect);
	}

	void host_window::copy(int x, int y, int w, int h, sdl::texture &tex)
	{
		SDL_Rect rect;
		rect.x = global_offs_x * 8 + x;
		rect.y = global_offs_y * 8 + y;
		rect.w = w;
		rect.h = h;
		SDL_RenderCopy(*this, tex, NULL, &rect);
	}
}
