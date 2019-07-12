#pragma once

#include <string>

namespace r3emu::config
{
	const unsigned int default_fps = 60U;
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

	const unsigned char colour_default = 0xF0U;
	const unsigned char colour_frame = 0xF7U;
	const unsigned char colour_clear = colour_frame;
	const unsigned char colour_title = 0xF8U;

	const enum
	{
		memory_size_2k = 11,
		memory_size_4k = 12,
		memory_size_8k = 13
	} memory_size = memory_size_2k;

	const int mm_core_base            = (1 << memory_size) - 0x100;
	const int mm_core_gp_registers    = mm_core_base + 0x00;
	const int mm_core_flags           = mm_core_base + 0x08;
	const int mm_core_program_counter = mm_core_base + 0x09;
	const int mm_core_last_output     = mm_core_base + 0x0B;
	// const int mm_core_loop_count      = mm_core_base + 0x0C; // LOOPCONTROL
	// const int mm_core_loop_from       = mm_core_base + 0x0D; // LOOPCONTROL
	// const int mm_core_loop_to         = mm_core_base + 0x0E; // LOOPCONTROL
	const int mm_core_write_mask      = mm_core_base + 0x0F;

	const int mm_screen_base   = 0x1C00;
	const int mm_screen_buffer = mm_screen_base + 0x000;
	const int mm_screen_colour = mm_screen_base + 0x100;
	const int mm_screen_mode   = mm_screen_base + 0x101;

	const int mm_keyboard_input = 0x1F00;
}
