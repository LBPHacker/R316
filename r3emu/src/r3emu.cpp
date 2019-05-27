#include "config.hpp"

#include "utility/console.hpp"
#include "ui/host_window.hpp"
#include "sdl/context.hpp"
#include "sdl/nice_error.hpp"
#include "sdl/event_timer.hpp"
#include "lua/state.hpp"

#include "emulator/bus.hpp"
#include "emulator/core.hpp"
#include "emulator/core_view.hpp"
#include "emulator/memory.hpp"
#include "emulator/simulation.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <future>
#include <SDL.h>
#include <vector>
#include <fstream>

using namespace r3emu;

bool handle_console_input(lua::state &L, SDL_Event &event)
{
	static std::string console_input_buffer;
	bool eof = false;
	auto *process_input = static_cast<std::promise<bool> *>(event.user.data1);
	auto *input = static_cast<std::string *>(event.user.data2);
	if (input)
	{
		console_input_buffer += *input + "\n";
		bool complete = L.execute("console", console_input_buffer);
		process_input->set_value(complete);
		if (complete)
		{
			console_input_buffer.clear();
		}
	}
	else
	{
		eof = true;
		std::cout << std::endl << "EOF" << std::endl;
		process_input->set_value(true);
	}
	return eof;
}

int main(int argc, char *argv[])
{
	std::vector<std::string> args(argv, argv + argc);

	sdl::context cx;
	lua::state L;
	utility::console cons;
	ui::host_window hw;

	sdl::event_timer render_timer(1000 / config::default_fps, sdl::context::event_render_frame);
	sdl::event_timer update_timer(1000 / config::default_ups, sdl::context::event_update_emulator);

	emulator::bus        bu (L, "bus");
	emulator::memory     mem(L, "mem");
	emulator::core       co (L, "core", bu, mem);
	emulator::simulation sim(L, "sim", co);
	emulator::core_view  cv (L, "core_view", co, sim, hw);

	hw.init_views();

	{
		std::string autorun_path("autorun.lua");
		if (args.size() >= 2)
		{
			autorun_path = args[1];
		}
		std::ifstream autorun(autorun_path);
		if (autorun)
		{
			L.execute(autorun_path, std::string((std::istreambuf_iterator<char>(autorun)), (std::istreambuf_iterator<char>())));
		}
	}

	SDL_Event event;
	bool running = true;
	while (running)
	{
		if (!SDL_WaitEvent(&event))
		{
			throw sdl::nice_error("SDL_WaitEvent");
		}

		switch (event.type)
		{
		case SDL_QUIT:
			running = false;
			break;

		case SDL_KEYDOWN:
			switch (event.key.keysym.sym)
			{
			case SDLK_SPACE:
				sim.toggle_pause();
				break;

			case SDLK_f:
				sim.step(event.key.keysym.mod & KMOD_SHIFT);
				break;

			case SDLK_s:
				co.request_start();
				break;

			case SDLK_r:
				co.request_reset();
				break;

			default:
				break;
			}
			break;

		default:
			if (event.type == sdl::context::sdl_event_type)
			{
				switch (event.user.code)
				{
				case sdl::context::event_console_input:
					if (handle_console_input(L, event))
					{
						running = false;
					}
					break;

				case sdl::context::event_render_frame:
					hw.draw();
					break;

				case sdl::context::event_update_emulator:
					sim.update();
					break;

				default:
					break;
				}
			}
		}
	}

	std::cout << std::endl;

	return 0;
}
