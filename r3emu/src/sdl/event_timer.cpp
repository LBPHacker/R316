#include "event_timer.hpp"

#include "context.hpp"

namespace r3emu::sdl
{
	event_timer::event_timer(Sint32 code) :
		timer([code]() {
			SDL_Event event;
			SDL_zero(event);
			event.type = sdl::context::sdl_event_type;
			event.user.code = code;
			SDL_PushEvent(&event);
		})
	{
	}
}
