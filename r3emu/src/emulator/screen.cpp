#include "screen.hpp"

#include "../config.hpp"

#include <iostream>

namespace r3emu::emulator
{
	screen::screen(lua::state &L_param, std::string name_param, bus &bu_param) :
		peripheral(bu_param), L(L_param), name(name_param), blocks(0x100)
	{
	}

	void screen::pre_gather()
	{
	}

	void screen::spread(bool write, uint16_t addr, uint32_t value)
	{
		if (write)
		{
			if (addr >= config::mm_screen_buffer && addr < config::mm_screen_buffer + 0x100)
			{
				value |= colour;
				auto &block = blocks[addr - config::mm_screen_buffer];
				block.ch = value & 0x00FF;
				block.bgfg = (value & 0xFF00) >> 8;
			}

			switch (addr)
			{
			case config::mm_screen_mode:
				mode = value;
				break;

			case config::mm_screen_colour:
				colour = value;
				break;
			}
		}
	}
}
