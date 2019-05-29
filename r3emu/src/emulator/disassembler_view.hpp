#pragma once

#include "../ui/view.hpp"

#include <string>

namespace r3emu::ui
{
	class host_window;
}

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class memory;

	class disassembler_view : public ui::view
	{
		lua::state &L;
		std::string name;
		memory &mem;

		int top;
		int highlight;

	public:
		disassembler_view(lua::state &L_param, std::string name_param, memory &mem_param, ui::host_window &hw);

		void draw() final override;
	};
}
