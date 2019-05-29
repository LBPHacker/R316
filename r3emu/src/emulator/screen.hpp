#pragma once

#include "peripheral.hpp"

#include <string>
#include <vector>

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

		struct screen_block
		{
			int ch;
			int bgfg;
		};
		std::vector<screen_block> blocks;

		uint16_t mode;
		uint16_t colour;

	public:
		screen(lua::state &L, std::string name, bus &bu);

		void pre_gather() final override;
		void spread(bool write, uint16_t addr, uint32_t value) final override;

		friend class screen_view;
	};
}
