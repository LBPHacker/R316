#include "config.hpp"

#include "utility/console.hpp"
#include "ui/host_window.hpp"
#include "sdl/context.hpp"
#include "lua/state.hpp"

#include "emulator/bus.hpp"
#include "emulator/core.hpp"
#include "emulator/core_view.hpp"
#include "emulator/memory.hpp"
#include "emulator/simulation.hpp"
#include "emulator/screen.hpp"
#include "emulator/disassembler_view.hpp"
#include "emulator/screen_view.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <future>
#include <SDL.h>
#include <vector>
#include <fstream>
#include <sstream>
#include <chrono>

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
		bool complete = L.execute_incomplete("console", console_input_buffer);
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
	SDL_SetWindowTitle(hw, config::window_title.c_str());

	emulator::bus         bu (L, "bus");
	emulator::memory      mem(L, "mem");
	emulator::core        co (L, "core", bu, mem);
	emulator::simulation  sim(L, "sim", co);
	emulator::core_view   cv (L, "core_view", co, sim, hw, 0, 0);
	emulator::screen      scr(L, "screen", bu);
	emulator::screen_view sv (L, "screen_view", scr, hw, 17, 0);
	emulator::disassembler_view dis(L, "dis", mem, hw, 0, 17);

	hw.init_views();

	lua_newtable(L);
	unsigned int desired_fps = config::default_fps;
	L.set_ugly_func(&desired_fps, [](lua_State *L) -> int {
		auto *desired_fps = static_cast<unsigned int *>(lua_touserdata(L, lua_upvalueindex(1)));
		*desired_fps = luaL_checkinteger(L, 1);
		return 0;
	}, "set");
	lua_setglobal(L, "fps");

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

	using clock = std::chrono::high_resolution_clock;

	auto next_frame = clock::now();
	auto last_fps_at = clock::now();
	auto frame_count = 0U;
	SDL_Event event;
	bool running = true;
	while (running)
	{
		while (SDL_PollEvent(&event))
		{
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

					default:
						break;
					}
				}
			}
		}

		sim.update();
		L.global_callback("pre_draw");
		hw.draw();

		std::this_thread::sleep_until(next_frame);
		if (next_frame < clock::now())
		{
			next_frame = clock::now();
		}
		next_frame += std::chrono::nanoseconds(1000000000) / desired_fps;
		frame_count += 1;

		if (last_fps_at + std::chrono::seconds(1) < clock::now())
		{
			std::ostringstream ss;
			ss << config::window_title << " (" << frame_count << " FPS)";
			frame_count = 0U;
			SDL_SetWindowTitle(hw, ss.str().c_str());
			last_fps_at = clock::now();
		}
	}

	std::cout << std::endl;

	return 0;
}
