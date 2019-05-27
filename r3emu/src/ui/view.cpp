#include "view.hpp"

#include "host_window.hpp"

namespace r3emu::ui
{
	view::view(int width_param, int height_param, std::string title_param, host_window &hw_param) :
		width(width_param), height(height_param), title(title_param), hw(hw_param)
	{
		hw.add_view(*this);
	}

	view::~view()
	{
	}
}
