#include "core.hpp"

#include "memory.hpp"
#include "bus.hpp"
#include "../config.hpp"

#include <iostream>

namespace r3emu::emulator
{
	core::core(lua::state &L_param, std::string name_param, bus &bu_param, memory &mem_param) :
		L(L_param),
		name(name_param),
		bu(bu_param),
		mem(mem_param)
	{
		gp_registers    = mem.data.data() + config::mm_gp_registers;
		flags           = mem.data.data() + config::mm_flags;
		program_counter = mem.data.data() + config::mm_program_counter;
		write_mask      = mem.data.data() + config::mm_write_mask;
		last_output     = mem.data.data() + config::mm_last_output;
		loop_count      = mem.data.data() + config::mm_loop_count;
		loop_from       = mem.data.data() + config::mm_loop_from;
		loop_to         = mem.data.data() + config::mm_loop_to;

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
		halted = true;
	}

	void core::request_reset()
	{
		reset_requested = true;
	}

	void core::do_cycle()
	{
		if (!halted)
		{
			while (subcycle < 4)
			{
				exec_subcycle();
			}
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
		if (!halted)
		{
			exec_subcycle();
			if (subcycle == 4)
			{
				finish_cycle();
			}
		}
	}

	void core::exec_subcycle()
	{
		sc_decode();
		if (!skip_subcycle)
		{
			sc_gather();
			sc_execute();
			sc_spread();
			sc_branch();
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

		uint32_t instruction = 0x20000000U | (mem.data[*program_counter] & 0x1FFFFFFFU);

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
			mem_addr[offs] = (gp_registers[7] & 0xFFFFU) + (instruction % 0x20) - 0x10;
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
		uint32_t bus_buffer;
		bu.pre_gather();
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
		auto to_write = ((*write_mask & 0x1FFF) << 16) | op[0];

		if (mem_op[0])
		{
			mem.data[mem_addr[0]] = to_write;
		}

		uint16_t bus_addr = 0;
		if (mem_op[0])
		{
			bus_addr = mem_addr[0];
		}
		bu.spread(mem_op[0], bus_addr, to_write);
		bu.post_spread();

		for (auto i = 0U; i < 8U; ++i)
		{
			if (wrbk_set & (1 << i))
			{
				gp_registers[i] = op[0];
			}
			if (incr_set & (1 << i))
			{
				gp_registers[i] += 1;
			}
			if (decr_set & (1 << i))
			{
				gp_registers[i] -= 1;
			}
			gp_registers[i] &= 0xFFFFU;
		}
	}

	void core::sc_branch()
	{
		*last_output = op[0];

		*program_counter += 1;

		*program_counter &= 0xFFFFU;
		*loop_count &= 0xFFFFU;
		*loop_from &= 0xFFFFU;
		*loop_to &= 0xFFFFU;
		if (*loop_count && *program_counter == *loop_from)
		{
			*program_counter = *loop_to;
			*loop_count -= 1;
		}

		if (jump && ((*flags >> (jump_cond >> 1)) & 1) == (jump_cond & 1))
		{
			*program_counter = op[2];
		}

		*program_counter &= 0xFFFFU;
		*last_output &= 0xFFFFU;
		*write_mask &= 0x1FFFU;
		*flags &= 0xFFU;
	}

	void core::oper_mov()
	{
		op[0] = op[2];
	}

	void core::oper_jcc()
	{
		jump = true;
	}

	void core::oper_nyi()
	{
		std::cerr << "oper_nyi called" << std::endl;
	}
	
	void core::sc_execute()
	{
		bu.mid_execute();

		static void (core::*oper_table[0x20])() = {
			&core::oper_mov,
			&core::oper_jcc,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi,
			&core::oper_nyi
		};

		(this->*oper_table[oper])();
	}
}
