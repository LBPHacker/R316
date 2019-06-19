#include "core.hpp"

#include "memory.hpp"
#include "bus.hpp"
#include "../config.hpp"

#include <iomanip>
#include <iostream>

namespace r3emu::emulator
{
	core::core(lua::state &L_param, std::string name_param, bus &bu_param, memory &mem_param) :
		L(L_param),
		name(name_param),
		bu(bu_param),
		mem(mem_param)
	{
		gp_registers    = mem.data.data() + config::mm_core_gp_registers;
		flags           = mem.data.data() + config::mm_core_flags;
		program_counter = mem.data.data() + config::mm_core_program_counter;
		last_output     = mem.data.data() + config::mm_core_last_output;
		// loop_count      = mem.data.data() + config::mm_core_loop_count; // LOOPCONTROL
		// loop_from       = mem.data.data() + config::mm_core_loop_from; // LOOPCONTROL
		// loop_to         = mem.data.data() + config::mm_core_loop_to; // LOOPCONTROL
		write_mask      = mem.data.data() + config::mm_core_write_mask;

		cycle = 0;
		subcycle = 0;
		start_requested = false;
		reset_requested = false;
		skip_subcycle = false;
		reset();
	}

	void core::start()
	{
		start_requested = false;
		halted = false;
	}

	void core::request_start()
	{
		start_requested = true;
	}

	void core::reset()
	{
		reset_requested = false;
		*program_counter = 0;
		// *loop_count = 0; // LOOPCONTROL
		halted = true;
	}

	void core::request_reset()
	{
		reset_requested = true;
	}

	void core::do_cycle()
	{
		while (subcycle < 4)
		{
			exec_subcycle();
		}		
		finish_cycle();
	}
	
	void core::finish_cycle()
	{
		subcycle = 0;
		skip_subcycle = false;
		cycle += 1;
		if (reset_requested)
		{
			reset();
		}
		if (start_requested)
		{
			start();
		}
	}

	void core::do_subcycle()
	{
		exec_subcycle();
		if (subcycle == 4)
		{
			finish_cycle();
		}
	}

	void core::exec_subcycle()
	{
		if (!halted)
		{
			sc_decode();
			if (!skip_subcycle)
			{
				sc_gather();
				sc_execute();
				sc_spread();
				sc_branch();
			}
		}
		subcycle += 1;
	}
	
	void core::sc_decode()
	{
		swap_op_1_2 = false;
		mem_op[0] = false;
		mem_addr[0] = 0;
		mem_op[1] = false;
		mem_addr[1] = 0;
		mem_op[2] = false;
		mem_addr[2] = 0;
		incr_set = 0;
		decr_set = 0;
		wrbk_set = 0;
		jump = false;
		write_op_0 = false;

		uint32_t instruction = 0x20000000U | (mem.data[*program_counter & ((1 << config::memory_size) - 1)] & 0x1FFFFFFFU);

		if (instruction & 0x00800000U)
		{
			swap_op_1_2 = true;
		}

		if (instruction & 0x00400000U)
		{
			sc_bind_regop(0, instruction >> 16);
			sc_bind_regop(2, instruction >> 16);
			op[1] = instruction & 0xFFFFU;
		}
		else if (instruction & 0x00008000U)
		{
			sc_bind_regop(0, instruction >> 16);
			sc_bind_regop(2, instruction >> 8);
			op[1] = (instruction & 0x00FFU) | ((instruction & 0x00004000U) ? 0xFF00 : 0x0000);
		}
		else if (!(instruction & 0x00004000U))
		{
			sc_bind_regop(0, instruction >> 16);
			sc_bind_regop(1, instruction);
			sc_bind_regop(2, instruction >> 8);
		}
		else if (instruction & 0x00002000U)
		{
			sc_bind_regop(0, instruction >> 16);
			sc_bind_regop(2, instruction >> 16);
			mem_op[1] = true;
			mem_addr[1] = instruction & 0x1FFFU;
			mem_op[0] = mem_op[1];
			mem_addr[0] = mem_addr[1];
			wrbk_set = 0;
		}
		else
		{
			sc_bind_regop(0, instruction >> 16);
			sc_bind_regop(2, instruction >> 16);
			mem_op[1] = true;
			mem_addr[1] = instruction & 0x1FFFU;
		}

		jump_cond = (instruction & 0x000F0000U) >> 16;
		oper = (instruction & 0x1F000000U) >> 24;

		if (subcycle && (
			(mem_op[0] && mem_addr[0] >= (1 << config::memory_size)) ||
			(mem_op[1] && mem_addr[1] >= (1 << config::memory_size)) ||
			(mem_op[2] && mem_addr[2] >= (1 << config::memory_size))
		))
		{
			skip_subcycle = true;
		}
	}
	
	void core::sc_bind_regop(int offs, uint32_t instruction)
	{
		auto reg = instruction % 8;
		if (instruction & 0x20U)
		{
			mem_op[offs] = true;
			mem_addr[offs] = (gp_registers[7] & 0xFFFFU) + (instruction % 0x10) + ((instruction & 0x10) ? 0xFFF0U : 0x0000U);
		}
		else if (instruction & 0x10U)
		{
			if (instruction & 0x08U)
			{
				mem_op[offs] = true;
				mem_addr[offs] = (gp_registers[reg] & 0xFFFFU) - 1;
				decr_set |= 1 << reg;
			}
			else
			{
				mem_op[offs] = true;
				mem_addr[offs] = (gp_registers[reg] & 0xFFFFU);
				incr_set |= 1 << reg;
			}
		}
		else
		{
			if (instruction & 0x08U)
			{
				if (reg == 7)
				{
					op[offs] = *last_output;
				}
				else
				{
					mem_op[offs] = true;
					mem_addr[offs] = (gp_registers[reg] & 0xFFFFU);
				}
			}
			else
			{
				op[offs] = (gp_registers[reg] & 0xFFFFU);
				if (offs == 0)
				{
					wrbk_set |= 1 << reg;
				}
			}
		}
	}

	void core::sc_gather()
	{
		bu.pre_gather();

		*program_counter += 1;
		*program_counter &= 0xFFFFU;

		uint32_t bus_buffer;
		uint16_t bus_addr = 0;
		if (mem_op[1])
		{
			bus_addr = mem_addr[1];
		}
		else if (mem_op[2])
		{
			bus_addr = mem_addr[2];
		}
		bu.gather(mem_op[1] || mem_op[2], bus_addr, bus_buffer);

		if (mem_op[1])
		{
			if (mem_addr[1] >= (1 << config::memory_size))
			{
				op[1] = bus_buffer;
			}
			else
			{
				op[1] = mem.data[mem_addr[1]];
			}
		}
		if (mem_op[2])
		{
			if (mem_addr[2] >= (1 << config::memory_size))
			{
				op[2] = bus_buffer;
			}
			else
			{
				op[2] = mem.data[mem_addr[2]];
			}
		}

		if (swap_op_1_2)
		{
			auto temp = op[1];
			op[1] = op[2];
			op[2] = temp;
		}
	}

	void core::sc_spread()
	{
		uint16_t reg_temp[8];
		for (auto i = 0U; i < 8U; ++i)
		{
			reg_temp[i] = gp_registers[i];
		}

		auto to_write = ((*write_mask & 0x1FFF) << 16) | op[0];

		uint16_t bus_addr = 0;
		if (mem_op[0])
		{
			bus_addr = mem_addr[0];
		}
		bu.spread(mem_op[0] && write_op_0, bus_addr, to_write);

		if (write_op_0)
		{
			if (mem_op[0] && mem_addr[0] < (1 << config::memory_size))
			{
				mem.data[mem_addr[0]] = to_write;
			}

			for (auto i = 0U; i < 8U; ++i)
			{
				if (wrbk_set & (1 << i))
				{
					gp_registers[i] = op[0];
				}
			}

			*last_output = op[0];
		}

		for (auto i = 0U; i < 8U; ++i)
		{
			if (incr_set & (1 << i))
			{
				gp_registers[i] = reg_temp[i] + 1;
			}
			if (decr_set & (1 << i))
			{
				gp_registers[i] = reg_temp[i] - 1;
			}
			gp_registers[i] &= 0xFFFFU;
		}

		bu.post_spread();
	}

	void core::sc_branch()
	{
		if (jump && (((*flags | flag_true) >> (jump_cond >> 1)) & 1) == (jump_cond & 1))
		{
			*program_counter = jump_to;
		}

		// *loop_count &= 0xFFFFU; // LOOPCONTROL
		// *loop_from &= 0xFFFFU; // LOOPCONTROL
		// *loop_to &= 0xFFFFU; // LOOPCONTROL

		// if (*loop_count && *program_counter == *loop_from) // LOOPCONTROL
		// { // LOOPCONTROL
		// 	*loop_count -= 1; // LOOPCONTROL
		// 	*loop_count &= 0xFFFFU; // LOOPCONTROL
		// 	if (*loop_count) // LOOPCONTROL
		// 	{ // LOOPCONTROL
		// 		*program_counter = *loop_to; // LOOPCONTROL
		// 	} // LOOPCONTROL
		// } // LOOPCONTROL

		*program_counter &= 0xFFFFU;
		*last_output &= 0xFFFFU;
		*write_mask &= 0x1FFFU;
		*flags &= 0xFFU;
	}

	void core::update_secondary_flags()
	{
		*flags = (*flags & ~flag_lower) | ((bool(*flags & flag_sign) != bool(*flags | flag_overflow)) ? flag_lower : 0);
		*flags = (*flags & ~flag_below_equal) | ((*flags & (flag_carry | flag_zero)) ? flag_below_equal : 0);
		*flags = (*flags & ~flag_not_greater) | ((*flags & (flag_lower | flag_zero)) ? flag_not_greater : 0);
	}

	void core::update_secondary_flags_zs()
	{
		*flags = (*flags & ~flag_sign) | ((op[0] & 0x8000U) ? flag_sign : 0);
		*flags = (*flags & ~flag_zero) | (!op[0] ? flag_zero : 0);
		update_secondary_flags();
	}
	
	void core::sc_execute()
	{
		bu.mid_execute();

		switch (oper % 0x20)
		{
		case 0x01: // call
			jump = true;
			jump_cond = 1;
			jump_to = op[2];
			op[2] = *program_counter;
			[[fallthrough]];
		case 0x00: // mov
			write_op_0 = true;
			op[0] = op[2];
			break;

		case 0x02: // jcc
			jump = true;
			jump_to = op[2];
			break;

		case 0x03: // hlt
			halted = true;
			break;

		case 0x04: // bsf
		case 0x05: // bsr
		case 0x06: // zsf
		case 0x07: // zsr
			if (oper & 0x02)
			{
				op[2] ^= 0xFFFFU;
			}
			if (op[2])
			{
				if (oper & 0x01)
				{
					op[0] = 15;
					while (!((op[2] >> op[0]) & 1))
					{
						op[0] -= 1;
					}
				}
				else
				{
					op[0] = 0;
					while (!((op[2] >> op[0]) & 1))
					{
						op[0] += 1;
					}
				}
			}
			else
			{
				op[0] = 0xFFFFU;
			}
			update_secondary_flags_zs();
			write_op_0 = true;
			break;

		case 0x08: // xor
			op[0] = op[1] ^ op[2];
			update_secondary_flags_zs();
			write_op_0 = true;
			break;

		case 0x09: // or
			op[0] = op[1] | op[2];
			update_secondary_flags_zs();
			write_op_0 = true;
			break;

		case 0x0A: // and
			write_op_0 = true;
			[[fallthrough]];
		case 0x1A: // test
			op[0] = op[1] & op[2];
			update_secondary_flags_zs();
			break;

		case 0x0B: // andn
			write_op_0 = true;
			[[fallthrough]];
		case 0x1B: // tstn
			op[0] = op[1] & (op[2] ^ 0xFFFFU);
			update_secondary_flags_zs();
			break;

		case 0x0C: // add
		case 0x0D: // adc
		case 0x0E: // sub
		case 0x0F: // sbb
			write_op_0 = true;
			[[fallthrough]];
		case 0x1E: // cmp
		case 0x1F: // cmpc
			{
				uint16_t carry = ((oper & 0x01) && (*flags & (1 << flag_carry))) ? 1 : 0;
				if (oper & 0x02)
				{
					op[1] ^= 0xFFFFU;
				}
				op[0] = carry + op[1] + op[2];
				uint32_t carry_16 = (uint32_t(carry) + op[1] + op[2]) >> 16;
				uint32_t carry_15 = (uint32_t(carry) + (op[1] & 0x7FFFU) + (op[2] & 0x7FFFU)) >> 15;
				if (oper & 0x02)
				{
					op[0] ^= 0xFFFFU;
				}
				*flags = (*flags & ~flag_carry) | (carry_16 ? flag_carry : 0);
				*flags = (*flags & ~flag_overflow) | ((carry_16 ^ carry_15) ? flag_overflow : 0);
			}
			update_secondary_flags_zs();
			break;

		case 0x10: // mak
		case 0x11: // ext
		case 0x12: // mak1
		case 0x13: // ext1
		case 0x14: // scl
		case 0x15: // scr
		case 0x16: // rol
		case 0x17: // ror
			{
				uint16_t shift_in_from;
				switch (oper & 0x06)
				{
				case 0x00:
					shift_in_from = 0x0000U;
					break;

				case 0x02:
					shift_in_from = 0xFFFFU;
					break;
					
				case 0x04:
					shift_in_from = *last_output;
					break;
					
				case 0x06:
					shift_in_from = op[1];
					break;
				}

				uint16_t mask = 0xFFFFU >> ((op[2] & 0xF0) >> 4);
				uint16_t shift = op[2] & 0x0F;
				if (oper & 0x01)
				{
					op[0] = ((op[1] >> shift) | (shift_in_from << (16 - shift))) & mask;
				}
				else
				{
					op[0] = ((op[1] << shift) | (shift_in_from >> (16 - shift))) & mask;
				}
			}
			update_secondary_flags_zs();
			write_op_0 = true;
			break;

		case 0x18: // ???
		case 0x19: // ???
		case 0x1C: // ???
		case 0x1D: // ???
			std::cerr << "0x";
			std::cerr << std::hex << std::uppercase << std::setw(2) << std::setfill('0'); // aka %02X
			std::cerr << oper << ": nyi" << std::endl;
			break;
		}
	}
}
