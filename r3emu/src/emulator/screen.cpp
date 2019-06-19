#include "screen.hpp"

#include "../config.hpp"
#include "../ui/host_window.hpp"
#include "../ui/font_texture.hpp"
#include "../../data/colours.hpp"

namespace r3emu::emulator
{
	screen::screen(
		lua::state &L_param,
		std::string name_param,
		bus &bu_param,
		ui::host_window &hw_param
	) :
		peripheral(bu_param),
		L(L_param),
		name(name_param),
		hw(hw_param),
		memory(0x100),
		buffer(hw, 128, 128, true)
	{
		ft = std::make_unique<ui::font_texture>(hw);
	}

	screen::~screen()
	{
	}

	void screen::pre_gather()
	{
	}

	void screen::gather(bool read, uint16_t addr, uint32_t &value)
	{
		if (read)
		{
			if (addr >= config::mm_screen_buffer && addr < config::mm_screen_buffer + 0x100)
			{
				auto local_addr = addr - config::mm_screen_buffer;
				value = memory[local_addr];
			}
		}
	}

	void screen::spread(bool write, uint16_t addr, uint32_t value)
	{
		if (write)
		{
			if (addr >= config::mm_screen_buffer && addr < config::mm_screen_buffer + 0x100)
			{
				auto local_addr = addr - config::mm_screen_buffer;
				auto x = local_addr % 16;
				auto y = local_addr / 16;
				value ^= colour;
				memory[local_addr] = value;

				SDL_SetRenderTarget(hw, buffer);
				switch (mode)
				{
				case mode_char8x8:
					{
						unsigned char ch = value & 0xFF;
						unsigned char bg = (value >> 12) & 0xF;
						unsigned char fg = (value >>  8) & 0xF;
						SDL_SetRenderDrawColor(hw, ::colours[bg].r, ::colours[bg].g, ::colours[bg].b, 0xFF);
						SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_BLEND);
						SDL_SetTextureColorMod(*ft, ::colours[fg].r, ::colours[fg].g, ::colours[fg].b);
						SDL_Rect src, dest;
						dest.x = x * 8;
						dest.y = y * 8;
						dest.w = 8;
						dest.h = 8;
						src.x = (ch % 16) * 8;
						src.y = (ch / 16) * 8;
						src.w = 8;
						src.h = 8;
						SDL_RenderFillRect(hw, &dest);
						SDL_RenderCopy(hw, *ft, &src, &dest);
					}
					break;

				case mode_4bit4x4:
					x *= 8;
					y *= 8;
					{
						SDL_Rect rect;
						rect.w = 4;
						rect.h = 4;
						auto c = value;
						for (auto yy = 0; yy < 2; ++yy)
						{
							for (auto xx = 0; xx < 2; ++xx)
							{
								SDL_SetRenderDrawColor(
									hw,
									::colours[c & 0xF].r,
									::colours[c & 0xF].g,
									::colours[c & 0xF].b,
									0xFF
								);
								SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_NONE);
								rect.x = x + xx * 4;
								rect.y = y + yy * 4;
								SDL_RenderFillRect(hw, &rect);
								c >>= 4;
							}
						}
					}
					break;

				case mode_1bit2x2:
					x *= 8;
					y *= 8;
					{
						SDL_Rect rect;
						rect.w = 2;
						rect.h = 2;
						auto c = value;
						for (auto yy = 0; yy < 4; ++yy)
						{
							for (auto xx = 0; xx < 4; ++xx)
							{
								SDL_SetRenderDrawColor(
									hw,
									::colours[(c & 1) ? 0xF : 0x0].r,
									::colours[(c & 1) ? 0xF : 0x0].g,
									::colours[(c & 1) ? 0xF : 0x0].b,
									0xFF
								);
								SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_NONE);
								rect.x = x + xx * 2;
								rect.y = y + yy * 2;
								SDL_RenderFillRect(hw, &rect);
								c >>= 1;
							}
						}
					}
					break;
				}
			}

			switch (addr)
			{
			case config::mm_screen_mode:
				if (value & 0x8000)
				{
					unsigned char bg = (colour >> 12) & 0xF;
					SDL_SetRenderTarget(hw, buffer);
					SDL_SetRenderDrawColor(
						hw,
						::colours[bg].r,
						::colours[bg].g,
						::colours[bg].b,
						0xFF
					);
					SDL_SetTextureBlendMode(*ft, SDL_BLENDMODE_NONE);
					SDL_RenderFillRect(hw, NULL);
					value &= ~0x8000;
				}
				mode = value;
				break;

			case config::mm_screen_colour:
				colour = value;
				break;
			}
		}
	}
}
