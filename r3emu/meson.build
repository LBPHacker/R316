project('r3emu', 'cpp')

sdl2_dep = dependency('sdl2')
luajit_dep = dependency('luajit')
thread_dep = dependency('threads')
libedit = dependency('libedit')

client_exec = executable('r3emu', sources: [
	'data/colours.cpp',
	'data/font.cpp',
	'src/emulator/bus.cpp',
	'src/emulator/core.cpp',
	'src/emulator/core_view.cpp',
	'src/emulator/memory.cpp',
	'src/emulator/peripheral.cpp',
	'src/emulator/simulation.cpp',
	'src/lua/state.cpp',
	'src/r3emu.cpp',
	'src/sdl/context.cpp',
	'src/sdl/event_timer.cpp',
	'src/sdl/nice_error.cpp',
	'src/sdl/texture.cpp',
	'src/sdl/timer.cpp',
	'src/sdl/window.cpp',
	'src/ui/font_texture.cpp',
	'src/ui/host_window.cpp',
	'src/ui/view.cpp',
	'src/utility/console.cpp',
	'src/utility/frequency_counter.cpp',
], dependencies: [sdl2_dep, luajit_dep, thread_dep, libedit])
