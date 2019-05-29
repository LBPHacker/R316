#pragma once

#include <string>

namespace r3emu::ui
{
	class host_window;

	class view
	{
	protected:
		int width, height;
		std::string title;
		host_window &hw;

		view(int width, int height, std::string title, host_window &hw);
		virtual ~view();

	public:
		virtual void draw() = 0;

		friend class host_window;
	};
}
