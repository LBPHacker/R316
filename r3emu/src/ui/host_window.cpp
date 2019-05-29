#include "host_window.hpp"

#include "view.hpp"
#include "font_texture.hpp"
#include "../../data/colours.hpp"

namespace r3emu::ui
{
	const unsigned char box_thick_dr = '\x8F';
	const unsigned char box_thick_dl = '\x93';
	const unsigned char box_thick_ur = '\x97';
	const unsigned char box_thick_ul = '\x9B';
	const unsigned char box_thick_rl = '\x81';
	const unsigned char box_thick_ud = '\x83';
	const unsigned char box_thick_url = '\xBB';
	const unsigned char box_thick_drl = '\xB3';
	const unsigned char box_thick_udr = '\xA3';
	const unsigned char box_thick_udl = '\xAB';

	host_window::host_window()
	{
		SDL_SetWindowTitle(*this, config::window_title.c_str());

		ft = std::make_unique<font_texture>(*this);

		fq.reset();
	}

	host_window::~host_window()
	{
	}

	void host_window::init_render_target()
	{
		int width = 1;
		int height = 0;
		for (auto v : views)
		{
			width += v->width + 1;
			if (height < v->height)
			{
				height = v->height;
			}
		}
		height += 2;
		width *= 8;
		height *= 8;

		rt = std::make_unique<sdl::texture>(*this, width, height, true);
		SDL_SetWindowSize(*this, width * config::scale, height * config::scale);
	}

	void host_window::frame()
	{
		y_offs = 1;
		x_offs = 1;
		std::string top_row(1, box_thick_dr);
		int last_height = -1;
		for (auto v : views)
		{
			top_row += std::string(v->width, box_thick_rl) + std::string(1, box_thick_drl);

			for (auto y = 0; y < (v->height < last_height ? last_height : v->height); ++y)
			{
				write(-1, y, std::string(1, box_thick_ud), config::colour_frame);
			}
			if (last_height == -1)
			{
				write(-1, v->height, std::string(1, box_thick_ur), config::colour_frame);
			}
			else if (last_height == v->height)
			{
				write(-1, v->height, std::string(1, box_thick_url), config::colour_frame);
			}
			else
			{
				write(-1, v->height, std::string(1, v->height < last_height ? box_thick_udr : box_thick_ur), config::colour_frame);
				write(-1, last_height, std::string(1, v->height < last_height ? box_thick_ul : box_thick_udl), config::colour_frame);
			}
			last_height = v->height;

			write(0, v->height, std::string(v->width, box_thick_rl), config::colour_frame);

			x_offs += v->width + 1;
		}
		for (auto y = 0; y < last_height; ++y)
		{
			write(-1, y, std::string(1, box_thick_ud), config::colour_frame);
		}
		write(-1, last_height, std::string(1, box_thick_ul), config::colour_frame);
		y_offs = 0;
		x_offs = 0;

		*(top_row.end() - 1) = box_thick_dl;
		write(0, 0, top_row, config::colour_frame);

		x_offs = 1;
		for (auto v : views)
		{
			write(0, 0, v->title, config::colour_title);
			x_offs += v->width + 1;
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
		fq.tick();

		SDL_SetRenderTarget(*this, *rt);

		y_offs = 1;
		x_offs = 1;
		for (auto v : views)
		{
			v->draw();
			x_offs += v->width + 1;
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
		dest.x = (x + x_offs) * 8;
		dest.y = (y + y_offs) * 8;
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

	void host_window::write_16(int x, int y, int v, int c, unsigned char bgfg)
	{
		std::string str(c, '?');
		static const char base16[] = "0123456789ABCDEF";
		for (auto it = str.rbegin(); it != str.rend(); ++it)
		{
			*it = base16[v % 16];
			v /= 16;
		}
		write(x, y, str, bgfg);
	}

	void host_window::write_10(int x, int y, int v, int c, unsigned char bgfg)
	{
		std::string str(c, '?');
		static const char base10[] = "0123456789";
		for (auto it = str.rbegin(); it != str.rend(); ++it)
		{
			*it = base10[v % 10];
			v /= 10;
		}
		write(x, y, str, bgfg);
	}

	void host_window::write_2(int x, int y, int v, int c, unsigned char bgfg)
	{
		std::string str(c, '?');
		static const char base2[] = "01";
		for (auto it = str.rbegin(); it != str.rend(); ++it)
		{
			*it = base2[v % 2];
			v /= 2;
		}
		write(x, y, str, bgfg);
	}

	int host_window::get_effective_fps() const
	{
		return fq.get();
	}
}
