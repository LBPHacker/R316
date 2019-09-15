#pragma once

#include <sdlstuff/enum_event.hpp>

namespace r3emu::utility
{
	enum local_event_types
	{
		event_console_input,
		event_render_frame,
		event_update_emulator
	};

	using local_event = sdlstuff::enum_event<local_event_types>;
}
