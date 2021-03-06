#pragma once

#include "../config.hpp"
#include "../utility/singleton.hpp"

#include <sdlstuff/texture.hpp>
#include <sdlstuff/window.hpp>
#include <vector>
#include <memory>

namespace r3emu::ui
{
	class view;
	class font_texture;

	class host_window : public sdlstuff::window, public utility::singleton<host_window>
	{
		std::vector<view *> views;
		void add_view(view &v);
		std::unique_ptr<font_texture> ft;
		std::unique_ptr<sdlstuff::texture> rt;

		int global_offs_x, global_offs_y;
		void init_render_target();
		void frame();

	public:
		host_window();
		~host_window();
		void init_views();
		void draw();

		void write(int x, int y, std::string str, unsigned char bgfg = config::colour_default);
		void rect(int x, int y, int w, int h, unsigned char c);
		void copy(int x, int y, int w, int h, sdlstuff::texture &tex);

		friend class view;
	};
}
