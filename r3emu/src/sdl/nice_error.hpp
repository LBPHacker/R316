#pragma once

#include <stdexcept>

namespace r3emu::sdl
{
	class nice_error : public std::runtime_error
	{
	public:
		nice_error(std::string origin);
	};
}
