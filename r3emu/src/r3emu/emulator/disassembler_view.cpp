#include "disassembler_view.hpp"

#include "memory.hpp"
#include "../ui/host_window.hpp"
#include "../config.hpp"
#include "../lua/state.hpp"

#include <sstream>

namespace r3emu::emulator
{
	disassembler_view::disassembler_view(
		lua::state &L_param,
		std::string name_param,
		memory &mem_param,
		ui::host_window &hw_param,
		int x,
		int y
	) :
		view(33, 16, x, y, "Disassembly", hw_param),
		L(L_param),
		name(name_param),
		mem(mem_param)
	{
		top = 0;
		highlight = 0;

		lua_newtable(L);

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *dis = static_cast<disassembler_view *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			dis->highlight = addr;
			return 0;
		}, "highlight");

		L.set_ugly_func(this, [](lua_State *L) -> int {
			auto *dis = static_cast<disassembler_view *>(lua_touserdata(L, lua_upvalueindex(1)));
			uint16_t addr = luaL_checkinteger(L, 1);
			dis->top = addr;
			return 0;
		}, "show");

		lua_setglobal(L, name.c_str());
	}

	void disassembler_view::draw()
	{
		static char const *mnemonics_displayed[0x20] = {
			"MOV ", "CALL", "JMP ", "HLT ", "BSF ", "BSR ", "ZSF ", "ZSR ",
			"MAKS", "EXTS", "SCLS", "SCRS", "CMP ", "CMPC", "TEST", "TSTN",
			"MAK1", "EXT1", "ROL ", "ROR ", "ADD ", "ADC ", "XOR ", "OR  ",
			"MAK ", "EXT ", "SCL ", "SCR ", "SUB ", "SBB ", "AND ", "ANDN",
		};
		
		static uint32_t has_operands[0x20] = {
			 5,  4,  4,  0,  5,  5,  5,  5,
			 6,  6,  6,  6,  6,  6,  6,  6,
			 7,  7,  7,  7,  7,  7,  7,  7,
			 7,  7,  7,  7,  7,  7,  7,  7,
		};

		static char const *conditions_displayed[0x10] = {
			"N  ", "   ", "NB ", "B  ", "NO ", "O  ", "NE ", "E  ",
			"NS ", "S  ", "NL ", "L  ", "NBE", "BE ", "NLE", "LE ",
		};

		for (auto y = 0; y < height; ++y)
		{
			uint16_t addr = (top + y) & ((1 << config::memory_size) - 1);
			uint32_t instr = mem.data[addr];

			colour_default = config::colour_default;
			colour_frame = config::colour_frame;
			if (addr == highlight)
			{
				colour_default ^= 0xFF;
				colour_frame ^= 0xFF;
			}

			int x = 10;
			write_16(0, y, addr, 4, colour_frame);
			write(4, y, "      ", colour_default);
			if (instr & 0x1FFFFFFFU)
			{
				write(5, y, mnemonics_displayed[(instr & 0x1F000000U) >> 24], colour_default);
				if ((instr & 0x1F000000U) == 0x02000000U && (instr & 0x000F0000U) != 0x00010000U)
				{
					write(6, y, conditions_displayed[(instr & 0x000F0000U) >> 16], colour_default);
				}
					
				uint32_t op[3];
				if (instr & 0x00400000U)
				{
					op[0] = (instr >> 16) & 0x3FU;
					op[1] = (instr & 0xFFFFU) | 0x10000000U;
					op[2] = (instr >> 16) & 0x3FU;
				}
				else if (instr & 0x00008000U)
				{
					op[0] = (instr >> 16) & 0x3FU;
					op[1] = (instr & 0x00FFU) | ((instr & 0x00004000U) ? 0xFF00 : 0x0000) | 0x10000000U;
					op[2] = (instr >> 8) & 0x3FU;
				}
				else if (!(instr & 0x00004000U))
				{
					op[0] = (instr >> 16) & 0x3FU;
					op[1] = instr & 0x3FU;
					op[2] = (instr >> 8) & 0x3FU;
				}
				else if (instr & 0x00002000U)
				{
					op[0] = (instr & 0x1FFFU) | 0x20000000U;
					op[2] = (instr >> 16) & 0x3FU;
					op[1] = (instr & 0x1FFFU) | 0x20000000U;
				}
				else
				{
					op[0] = (instr >> 16) & 0x3FU;
					op[1] = (instr & 0x1FFFU) | 0x20000000U;
					op[2] = (instr >> 16) & 0x3FU;
				}
				if (instr & 0x00800000U)
				{
					uint32_t temp = op[1];
					op[1] = op[2];
					op[2] = temp;
				}

				uint32_t operands = has_operands[(instr & 0x1F000000U) >> 24];

				if (instr == 0x22011700U)
				{
					write(5, y, "RET ", colour_default);
					operands = 0;
				}

				switch (operands & 7)
				{
				case 1:
				case 3:
				case 5:
				case 7:
					write_operand(x, y, op[0]);
					if ((operands & 2) && op[0] != op[1])
					{
						write(x, y, ", ", colour_default); x += 2;
						write_operand(x, y, op[1]);
					}
					if (operands & 4)
					{
						write(x, y, ", ", colour_default); x += 2;
						write_operand(x, y, op[2]);
					}
					break;

				case 0:
					break;

				case 2:
				case 6:
					write_operand(x, y, op[1]);
					if (operands & 4)
					{
						write(x, y, ", ", colour_default); x += 2;
						write_operand(x, y, op[2]);
					}
					break;

				case 4:
					write_operand(x, y, op[2]);
					break;
				}
			}
			else
			{
				write(5, y, "NOP ", colour_default);
			}
			write(x, y, std::string(width - x, ' '), colour_default);
		}
	}

	void disassembler_view::write_operand(int &x, int y, uint32_t operand)
	{
		switch (operand >> 28)
		{
		case 0:
			{
				uint32_t reg = operand % 8;
				if (operand & 0x20U)
				{
					write(x, y, "[S???]", colour_default); x += 6;
					if (operand & 0x10)
					{
						write(x - 4, y, "-", colour_default);
						write_16(x - 3, y, 0x10 - operand % 0x10, 2, colour_default);
					}
					else
					{
						write(x - 4, y, "+", colour_default);
						write_16(x - 3, y, operand % 0x10, 2, colour_default);
					}
				}
				else if (operand & 0x10U)
				{
					if (operand & 0x08U)
					{
						write(x, y, "[--R?]", colour_default);
						write_16(x + 4, y, reg, 1, colour_default); x += 6;
					}
					else
					{
						write(x, y, "[R?++]", colour_default);
						write_16(x + 2, y, reg, 1, colour_default); x += 6;
					}
				}
				else
				{
					if (operand & 0x08U)
					{
						if (reg == 7)
						{
							write(x, y, "LO", colour_default); x += 2;
						}
						else
						{
							write(x, y, "[R?]", colour_default);
							write_16(x + 2, y, reg, 1, colour_default); x += 4;
						}
					}
					else
					{
						write(x, y, "R?", colour_default);
						write_16(x + 1, y, reg, 1, colour_default); x += 2;
					}
				}
			}
			break;

		case 1:
			write_16(x, y, operand, 4, colour_default); x += 4;
			break;

		case 2:
			write(x, y, "[", colour_default); x += 1;
			write_16(x, y, operand, 4, colour_default); x += 4;
			write(x, y, "]", colour_default); x += 1;
			break;
		}
	}
}
