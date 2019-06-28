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
}
