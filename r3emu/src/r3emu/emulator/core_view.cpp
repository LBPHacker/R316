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
		ui::host_window &hw_param,
		int x,
		int y
	) :
		view(16, 16, x, y, "Core & Sim", hw_param),
		L(L_param),
		name(name_param),
		co(co_param),
		sim(sim_param)
	{
	}

	void core_view::draw()
	{
		std::string rx_str("R?");
		for (auto i = 0; i < 8; ++i)
		{
			rx_str[1] = '0' + i;
			write(0, i, rx_str, config::colour_frame);
		}

		write(9, 0, "PC", config::colour_frame);
		write(9, 1, "WM", config::colour_frame);
		write(9, 2, "LI", config::colour_frame);
		write(9, 3, "LO", config::colour_frame);
		write(9, 5, "NBLSZOC", config::colour_frame);
		write(9, 8, "#    /", config::colour_frame);
		write(0, 9, "MC", config::colour_frame);
		write(0, 10, "LC", config::colour_frame);
		write(0, 11, "LF", config::colour_frame);
		write(0, 12, "LT", config::colour_frame);
		write(9, 10, "SC", config::colour_frame);
		write(9, 11, "RS", config::colour_frame);
		write(9, 12, "RR", config::colour_frame);
		write(0, 14, "Core is", config::colour_frame);
		write(0, 15, "Sim. is", config::colour_frame);
		
		for (auto i = 0; i < 8; ++i)
		{
			write_16(3, i, co.gp_registers[i], 4);
		}

		write_16(12, 0, *co.program_counter, 4);
		write_16(12, 1, *co.write_mask & 0x1FFF, 4);
		write_16(12, 2, *co.last_input, 4);
		write_16(12, 3, *co.last_output, 4);
		write_2(9, 6, *co.flags >> 1, 7);
		write_16(10, 8, co.cycle, 4);
		write_16(15, 8, co.subcycle, 1);
		write_16(3, 9, *co.pml_carries, 4);
		write_16(3, 10, *co.loop_count, 4);
		write_16(3, 11, *co.loop_from, 4);
		write_16(3, 12, *co.loop_to, 4);
		write(12, 10, co.skip_subcycle ? "SKIP" : "TAKE");
		write(12, 11, co.start_requested ? "REQU" : "NOPE");
		write(12, 12, co.reset_requested ? "REQU" : "NOPE");
		write(8, 14, co.halted ? "stopped!" : "running!");
		write(8, 15, sim.is_paused() ? "stopped!" : "running!");
	}
}
