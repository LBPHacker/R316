#include "bus.hpp"

#include "peripheral.hpp"

namespace r3emu::emulator
{
	bus::bus(lua::state &L_param, std::string name_param) : L(L_param), name(name_param)
	{
	}
	
	void bus::add_peripheral(peripheral *per)
	{
		peripherals.push_back(per);
	}

	void bus::gather(bool read, uint16_t addr, uint32_t &value)
	{
		for (auto *per : peripherals)
		{
			per->gather(read, addr, value);
		}
	}

	void bus::spread(bool write, uint16_t addr, uint32_t value)
	{
		for (auto *per : peripherals)
		{
			per->spread(write, addr, value);
		}
	}

	void bus::pre_gather()
	{
		for (auto *per : peripherals)
		{
			per->pre_gather();
		}
	}

	void bus::mid_execute()
	{
		for (auto *per : peripherals)
		{
			per->mid_execute();
		}
	}

	void bus::post_spread()
	{
		for (auto *per : peripherals)
		{
			per->post_spread();
		}
	}
}
