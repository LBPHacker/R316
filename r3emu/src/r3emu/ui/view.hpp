#pragma once

#include <string>

#include "../config.hpp"

namespace r3emu::sdlstuff
{
	class texture;
}

namespace r3emu::ui
{
	class host_window;

	class view
	{
	protected:
		int width, height;
		int position_x, position_y;
		std::string title;
		host_window &hw;

		view(int width, int height, int position_x, int position_y, std::string title, host_window &hw);
		virtual ~view();

	public:
		virtual void draw() = 0;

		void write(int x, int y, std::string str, unsigned char bgfg = config::colour_default);
		void rect(int x, int y, int w, int h, unsigned char c = config::colour_default);
		void copy(int x, int y, int w, int h, sdlstuff::texture &tex);
		void write_16(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);
		void write_10(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);
		void write_2(int x, int y, int v, int c, unsigned char bgfg = config::colour_default);

		friend class host_window;
	};
}
