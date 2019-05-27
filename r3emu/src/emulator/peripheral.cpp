#include "peripheral.hpp"

namespace r3emu::emulator
{
	peripheral::peripheral()
	{
	}

	peripheral::~peripheral()
	{
	}

	void peripheral::gather(bool, uint16_t, uint32_t &)
	{
	}

	void peripheral::spread(bool, uint16_t, uint32_t)
	{
	}
	
	void peripheral::pre_gather()
	{
	}
	
	void peripheral::mid_execute()
	{
	}
	
	void peripheral::post_spread()
	{
	}
}
