#pragma once

#include "singleton.hpp"
#include "local_event.hpp"

#include <thread>
#include <string>
#include <atomic>

namespace r3emu::utility
{
	class console : public singleton<console>
	{
		std::thread console_thread;
		static std::atomic<bool> running;
		static int event_type;

		static void run();
		static void callback(char *line);

		local_event const &local_ev;
		
	public:
		console(local_event const &local_ev);
		~console();
	};
}
