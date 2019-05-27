#pragma once

#include "../sdl/texture.hpp"
#include "../sdl/window.hpp"
#include "../config.hpp"
#include "../utility/singleton.hpp"
#include "../utility/frequency_counter.hpp"

#include <vector>
#include <memory>

namespace r3emu::ui
{
	class view;
	class font_texture;

	class host_window : public sdl::window, public utility::singleton<host_window>
	{
		std::vector<view *> views;
		void add_view(view &v);
		std::unique_ptr<font_texture> ft;
		std::unique_ptr<sdl::texture> rt;

		int x_offs, y_offs;
		void init_render_target();
		void frame();

		utility::frequency_counter fq;

	public:
		host_window();
		~host_window();
		void init_views();
		void draw();

		void write(int x, int y, std::string str, unsigned char bgfg = config::colour_default);
		void write_16(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);
		void write_10(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);
		void write_2(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);

		int get_effective_fps() const;

		friend class view;
	};
}
