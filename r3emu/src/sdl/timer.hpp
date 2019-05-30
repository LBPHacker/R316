#pragma once

#include <functional>
#include <SDL.h>

namespace r3emu::sdl
{
	class timer
	{
		using callback = std::function<void ()>;
		callback cb;
		bool active;
		SDL_TimerID id;

		static Uint32 wrapper(Uint32 interval, void *param);

	public:
		timer(callback cb);
		~timer();

		void arm(Uint32 interval);
	};
}
