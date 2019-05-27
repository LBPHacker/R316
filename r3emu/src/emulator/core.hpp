#pragma once

#include <cstdint>
#include <string>

namespace r3emu::lua
{
	class state;
}

namespace r3emu::emulator
{
	class bus;
	class memory;
	class core_view;

	class core
	{
		void exec_subcycle();
		void reset();
		void start();
		void finish_cycle();

		lua::state &L;
		std::string name;
		bus &bu;
		memory &mem;

		void sc_fetch();
		void sc_decode();
		void sc_gather();
		void sc_execute();
		void sc_spread();
		void sc_branch();

		void sc_bind_regop(int op, uint32_t instruction);

		uint32_t *gp_registers;
		uint32_t *flags;
		uint32_t *program_counter;
		uint32_t *write_mask;
		uint32_t *last_output;

		uint32_t *loop_count;
		uint32_t *loop_from;
		uint32_t *loop_to;

		uint16_t op[3];
		bool mem_op[3];
		uint16_t mem_addr[3];
		bool swap_op_1_2;
		uint32_t jump_cond;
		uint8_t incr_set, decr_set, wrbk_set;
		uint32_t oper;
		bool jump;

		int cycle;
		int subcycle;
		bool halted;
		bool start_requested;
		bool reset_requested;
		bool skip_subcycle;

		void oper_mov();
		void oper_jcc();
		void oper_nyi();

	public:
		core(lua::state &L, std::string name, bus &bu, memory &mem);

		void request_start();
		void request_reset();
		void do_cycle();
		void do_subcycle();

		friend class core_view;
	};
}
