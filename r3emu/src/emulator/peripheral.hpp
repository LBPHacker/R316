#pragma once

#include <cstdint>

namespace r3emu::emulator
{
	class peripheral
	{
	protected:
		peripheral();
		virtual ~peripheral();

	public:
		virtual void gather(bool read, uint16_t addr, uint32_t &value);
		virtual void spread(bool write, uint16_t addr, uint32_t value);
		virtual void pre_gather();
		virtual void mid_execute();
		virtual void post_spread();
	};
}
