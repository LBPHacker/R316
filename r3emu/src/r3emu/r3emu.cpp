#include "config.hpp"

#include "utility/console.hpp"
#include "utility/local_event.hpp"
#include "ui/host_window.hpp"
#include "lua/state.hpp"

#include "emulator/bus.hpp"
#include "emulator/core.hpp"
#include "emulator/core_view.hpp"
#include "emulator/memory.hpp"
#include "emulator/simulation.hpp"
#include "emulator/screen.hpp"
#include "emulator/disassembler_view.hpp"
#include "emulator/screen_view.hpp"
#include "emulator/keyboard.hpp"

#include <sdlstuff/context.hpp>
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

bool handle_console_input(lua::state &L, SDL_Event const &ev)
{
	static std::string console_input_buffer;
	bool eof = false;
	auto *process_input = static_cast<std::promise<bool> *>(ev.user.data1);
	auto *input = static_cast<std::string *>(ev.user.data2);
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

	sdlstuff::context cx;
	lua::state L;
	utility::local_event local_ev;
	utility::console cons(local_ev);
	ui::host_window hw;
	SDL_SetWindowTitle(hw, config::window_title.c_str());

	emulator::bus         bu (L, "bus");
	emulator::memory      mem(L, "mem");
	emulator::core        co (L, "core", bu, mem);
	emulator::simulation  sim(L, "sim", co);
	emulator::core_view   cv (L, "core_view", co, sim, hw, 0, 0);
	emulator::keyboard    kbd(L, "keyboard", bu);
	emulator::screen      scr(L, "screen", bu, hw);
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
	SDL_Event ev;
	bool running = true;
	while (running)
	{
		while (SDL_PollEvent(&ev))
		{
			switch (ev.type)
			{
			case SDL_QUIT:
				running = false;
				break;

			case SDL_KEYDOWN:
				switch (ev.key.keysym.sym)
				{
				case SDLK_SPACE:
					sim.toggle_pause();
					break;

				case SDLK_f:
					sim.step(ev.key.keysym.mod & KMOD_SHIFT);
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
				if (ev.type == local_ev.sdl_event_type())
				{
					switch (ev.user.code)
					{
					case utility::event_console_input:
						if (handle_console_input(L, ev))
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
