#pragma once

#include <SDL.h>

namespace r3emu::sdl
{
	class context
	{
	public:
		context();
		~context();

		enum events
		{
			event_console_input,
			event_render_frame,
			event_update_emulator
		};

		static Uint32 sdl_event_type;
	};
}
