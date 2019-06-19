#include "view.hpp"

#include "host_window.hpp"

namespace r3emu::ui
{
	view::view(
		int width_param,
		int height_param,
		int position_x_param,
		int position_y_param,
		std::string title_param,
		host_window &hw_param
	) :
		width(width_param),
		height(height_param),
		position_x(position_x_param),
		position_y(position_y_param),
		title(title_param),
		hw(hw_param)
	{
		hw.add_view(*this);
	}

	void view::write(int x, int y, std::string str, unsigned char bgfg)
	{
		hw.write(x + position_x + 1, y + position_y + 1, str, bgfg);
	}

	void view::write_16(int x, int y, int v, int c, unsigned char bgfg)
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

	void view::write_10(int x, int y, int v, int c, unsigned char bgfg)
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

	void view::write_2(int x, int y, int v, int c, unsigned char bgfg)
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

	view::~view()
	{
	}
}
