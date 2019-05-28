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
		uint32_t *return_to;
		uint32_t *last_output;

		uint32_t *loop_count;
		uint32_t *loop_from;
		uint32_t *loop_to;
		
		uint32_t *write_mask;

		uint16_t op[3];
		bool mem_op[3];
		uint16_t mem_addr[3];
		bool swap_op_1_2;
		uint32_t jump_cond;
		uint8_t incr_set, decr_set, wrbk_set;
		uint32_t oper;
		bool jump;
		bool write_op_0;

		int cycle;
		int subcycle;
		bool halted;
		bool start_requested;
		bool reset_requested;
		bool skip_subcycle;

		const uint32_t flag_true        = 1 << 0;
		const uint32_t flag_carry       = 1 << 1;
		const uint32_t flag_overflow    = 1 << 2;
		const uint32_t flag_zero        = 1 << 3;
		const uint32_t flag_sign        = 1 << 4;
		const uint32_t flag_lower       = 1 << 5;
		const uint32_t flag_below_equal = 1 << 6;
		const uint32_t flag_not_greater = 1 << 7;

		void update_secondary_flags();
		void update_secondary_flags_zs();

	public:
		core(lua::state &L, std::string name, bus &bu, memory &mem);

		void request_start();
		void request_reset();
		void do_cycle();
		void do_subcycle();

		friend class core_view;
	};
}
