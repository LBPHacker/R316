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

		unsigned char colour_default;
		unsigned char colour_frame;

		void write_operand(int &x, int y, uint32_t operand);

	public:
		disassembler_view(
			lua::state &L,
			std::string name,
			memory &mem,
			ui::host_window &hw,
			int x,
			int y
		);

		void draw() final override;
	};
}
