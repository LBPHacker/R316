#pragma once

#include "peripheral.hpp"

#include <string>
#include <queue>

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class bus;

	class keyboard : public peripheral
	{
		lua::state &L;
		std::string name;

		std::string buffer;
		uint32_t current;

	public:
		keyboard(lua::state &L, std::string name, bus &bu);
		~keyboard();

		void post_spread() final override;
		void gather(bool read, uint16_t addr, uint32_t &value) final override;
		void spread(bool write, uint16_t addr, uint32_t value) final override;
	};
}
