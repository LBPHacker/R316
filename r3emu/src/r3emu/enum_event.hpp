#pragma once

#include <sdlstuff/enum_event.hpp>

namespace r3emu
{
	enum event_types
	{
		event_console_input,
		event_render_frame,
		event_update_emulator
	};

	using enum_event = sdlstuff::enum_event<event_types>;
}
