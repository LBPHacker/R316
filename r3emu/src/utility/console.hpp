#pragma once

#include "singleton.hpp"

#include <thread>
#include <string>
#include <atomic>

namespace r3emu::utility
{
	class console : public singleton<console>
	{
		std::thread console_thread;
		static std::atomic<bool> running;

		static void run();
		static void callback(char *line);
		
	public:
		console();
		~console();
	};
}
