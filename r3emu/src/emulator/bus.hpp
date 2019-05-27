#pragma once

#include <cstdint>
#include <vector>
#include <string>

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class peripheral;

	class bus
	{
		std::vector<peripheral *> peripherals;
		lua::state &L;
		std::string name;

	public:
		bus(lua::state &L, std::string name);
		void add_peripheral(peripheral *per);

		void gather(bool read, uint16_t addr, uint32_t &value);
		void spread(bool write, uint16_t addr, uint32_t value);
		void pre_gather();
		void mid_execute();
		void post_spread();
	};
}
