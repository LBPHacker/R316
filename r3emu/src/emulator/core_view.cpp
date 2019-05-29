#include "core_view.hpp"

#include "core.hpp"
#include "simulation.hpp"
#include "../ui/host_window.hpp"

namespace r3emu::emulator
{
	core_view::core_view(
		lua::state &L_param,
		std::string name_param,
		core &co_param,
		simulation &sim_param,
		ui::host_window &hw_param
	) :
		view(16, 16, "Core & Sim", hw_param),
		L(L_param),
		name(name_param),
		co(co_param),
		sim(sim_param)
	{
		ups = 0;
		fps = 0;
		last_fps_ups_tick = SDL_GetTicks();
	}

	void core_view::draw()
	{
		std::string rx_str("R?");
		for (auto i = 0; i < 8; ++i)
		{
			rx_str[1] = '0' + i;
			hw.write(0, i, rx_str, config::colour_frame);
		}

		hw.write(9, 0, "PC", config::colour_frame);
		hw.write(9, 1, "WM", config::colour_frame);
		hw.write(9, 2, "LO", config::colour_frame);
		hw.write(9, 4, "NBLSZOC", config::colour_frame);
		hw.write(9, 7, "#    /", config::colour_frame);
		hw.write(0, 9, "LC", config::colour_frame);
		hw.write(0, 10, "LF", config::colour_frame);
		hw.write(0, 11, "LT", config::colour_frame);
		hw.write(9, 9, "SC", config::colour_frame);
		hw.write(9, 10, "RS", config::colour_frame);
		hw.write(9, 11, "RR", config::colour_frame);
		hw.write(0, 13, "FPS      UPS", config::colour_frame);
		hw.write(0, 14, "Core is", config::colour_frame);
		hw.write(0, 15, "Sim. is", config::colour_frame);
		
		for (auto i = 0; i < 8; ++i)
		{
			hw.write_16(3, i, co.gp_registers[i], 4);
		}

		Uint32 current_tick = SDL_GetTicks();
		if (current_tick - last_fps_ups_tick >= 1000)
		{
			ups = sim.get_effective_ups();
			fps = hw.get_effective_fps();
			last_fps_ups_tick = current_tick;
		}

		hw.write_16(12, 0, *co.program_counter, 4);
		hw.write_16(12, 1, *co.write_mask & 0x1FFF, 4);
		hw.write_16(12, 2, *co.last_output, 4);
		hw.write_2(9, 5, *co.flags >> 1, 7);
		hw.write_16(10, 7, co.cycle, 4);
		hw.write_16(15, 7, co.subcycle, 1);
		hw.write_16(3, 9, *co.loop_count, 4);
		hw.write_16(3, 10, *co.loop_from, 4);
		hw.write_16(3, 11, *co.loop_to, 4);
		hw.write(12, 9, co.skip_subcycle ? "SKIP" : "TAKE");
		hw.write(12, 10, co.start_requested ? "REQU" : "NOPE");
		hw.write(12, 11, co.reset_requested ? "REQU" : "NOPE");
		hw.write_10(4, 13, fps, 3);
		hw.write_10(13, 13, ups, 3);
		hw.write(8, 14, co.halted ? "stopped!" : "running!");
		hw.write(8, 15, sim.is_paused() ? "stopped!" : "running!");
	}
}
