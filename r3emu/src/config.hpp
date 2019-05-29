#pragma once

#include <string>

namespace r3emu::config
{
	const int default_fps = 60;
	const int default_ups = 60;
	const int scale = 2;
	const std::string window_title = "r3emu";
	const std::string prompt_string = "r3emu> ";
	const std::string welcome_text =
		"================ r3emu ================\n"
		"Quick heads up for the UI:\n"
		" - press R to reset the core;\n"
		" - press S to start the core;\n"
		" - press Space to pause/unpause the simulation;\n"
		" - press F to pause and step a single cycle;\n"
		" - press Shift+F for a single subcycle.\n"
	;

	const unsigned char colour_default = 0xF0;
	const unsigned char colour_frame = 0xF7;
	const unsigned char colour_clear = colour_frame;
	const unsigned char colour_title = 0xF8;

	const enum
	{
		memory_size_2k = 11,
		memory_size_4k = 12,
		memory_size_8k = 13
	} memory_size = memory_size_2k;

	const int mm_base = (1 << memory_size) - 0x100;
	const int mm_gp_registers    = mm_base + 0x00;
	const int mm_flags           = mm_base + 0x08;
	const int mm_program_counter = mm_base + 0x09;
	const int mm_return_to       = mm_base + 0x0A;
	const int mm_last_output     = mm_base + 0x0B;
	const int mm_loop_count      = mm_base + 0x0C;
	const int mm_loop_from       = mm_base + 0x0D;
	const int mm_loop_to         = mm_base + 0x0E;
	const int mm_write_mask      = mm_base + 0x0F;

	const int mm_screen_base     = 0xF000;
	const int mm_screen_mode     = 0xF100;
	const int mm_screen_colour   = 0xF101;
}
