#pragma once

#include "peripheral.hpp"

#include <sdlstuff/texture.hpp>
#include <string>
#include <vector>
#include <memory>

namespace r3emu::ui
{
	class host_window;
	class font_texture;
}

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class bus;
	class screen_view;

	class screen : public peripheral
	{
		lua::state &L;
		std::string name;
		ui::host_window &hw;

		uint16_t mode;
		uint16_t colour;
		std::vector<uint16_t> memory;

		sdlstuff::texture buffer;
		std::unique_ptr<ui::font_texture> ft;

	public:
		screen(lua::state &L, std::string name, bus &bu, ui::host_window &hw);
		~screen();

		void pre_gather() final override;
		void gather(bool read, uint16_t addr, uint32_t &value) final override;
		void spread(bool write, uint16_t addr, uint32_t value) final override;

		friend class screen_view;

		enum
		{
			mode_char8x8 = 0,
			mode_4bit4x4 = 1,
			mode_1bit2x2 = 2
		};
	};
}
