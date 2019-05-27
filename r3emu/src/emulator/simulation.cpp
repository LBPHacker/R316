#include "simulation.hpp"

#include "core.hpp"

namespace r3emu::emulator
{
	simulation::simulation(lua::state &L_param, std::string name_param, core &co_param) :
		L(L_param),
		name(name_param),
		co(co_param)
	{
		paused = true;
		request_cycle = false;
		request_subcycle = false;
		
		fq.reset();
	}

	void simulation::step(bool subcycle)
	{
		if (subcycle)
		{
			request_subcycle = true;
		}
		else
		{
			request_cycle = true;
		}
		paused = true;
	}

	void simulation::toggle_pause()
	{
		paused = !paused;
	}

	void simulation::update()
	{
		fq.tick();
		// Uint32 current_tick = SDL_GetTicks();
		// effective_ups = 1000 / (current_tick - last_tick);
		// last_tick = current_tick;

		if (paused)
		{
			if (request_cycle)
			{
				co.do_cycle();
			}
			else if (request_subcycle)
			{
				co.do_subcycle();
			}
		}
		else
		{
			co.do_cycle();
		}
		request_subcycle = false;
		request_cycle = false;
	}

	bool simulation::is_paused() const
	{
		return paused;
	}

	int simulation::get_effective_ups() const
	{
		return fq.get();
	}
}
