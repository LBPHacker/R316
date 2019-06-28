#pragma once

#include <vector>
#include <string>
#include <cstdint>

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class core;
	class disassembler_view;

	class memory
	{
		std::vector<uint32_t> data;
		lua::state &L;
		std::string name;

	public:
		memory(lua::state &L, std::string name);

		friend class core;
		friend class disassembler_view;
	};
}
