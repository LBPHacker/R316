#include "console.hpp"

#include "../config.hpp"

#include <sdlstuff/context.hpp>
#include <cstdlib>
#include <iostream>
#include <future>

#define _POSIX_C_SOURCE 200809L
#include <poll.h>
#include <unistd.h>

extern "C" {
#include <readline/readline.h>
#include <readline/history.h>
}

namespace r3emu::utility
{
	console::console()
	{
		running = true;
		console_thread = std::thread(run);
	}

	console::~console()
	{
		running = false;
		console_thread.join();
	}

	void console::callback(char *line)
	{
		if (line && !*line)
		{
			free(line);
			return;
		}

		std::promise<bool> process_input;

		SDL_Event event;
		SDL_zero(event);
		event.type = sdlstuff::context::sdl_event_type;
		event.user.code = sdlstuff::context::event_console_input;
		event.user.data1 = &process_input;
		event.user.data2 = nullptr;

		std::string input;
		if (line)
		{
			input = line;
			event.user.data2 = &input;
			::add_history(line);
			free(line);
		}

		SDL_PushEvent(&event);

		auto input_complete = process_input.get_future();
		input_complete.wait();
		if (input_complete.get())
		{
			rl_set_prompt(config::prompt_string.c_str());
		}
		else
		{
			rl_set_prompt((std::string(config::prompt_string.size() - 3, ' ') + ">> ").c_str());
		}
	}

	void console::run()
	{
		std::cout << config::welcome_text << std::endl;

		struct pollfd pfd[1];
		pfd[0].fd = STDIN_FILENO;
		pfd[0].events = POLLIN;

		rl_callback_handler_install(config::prompt_string.c_str(), callback);
		while (running)
		{
			if (poll(pfd, 1, 100) == 1)
			{
				rl_callback_read_char();
			}
		}
		rl_callback_handler_remove();
	}

	std::atomic<bool> console::running;
}
