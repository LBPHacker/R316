project('r3emu', 'cpp', version: '0.1.0')

executable('r3emu', sources: [
	'src/r3emu/colours.cpp',
	'src/r3emu/font.cpp',
	'src/r3emu/emulator/bus.cpp',
	'src/r3emu/emulator/core.cpp',
	'src/r3emu/emulator/core_view.cpp',
	'src/r3emu/emulator/disassembler_view.cpp',
	'src/r3emu/emulator/memory.cpp',
	'src/r3emu/emulator/peripheral.cpp',
	'src/r3emu/emulator/screen.cpp',
	'src/r3emu/emulator/screen_view.cpp',
	'src/r3emu/emulator/simulation.cpp',
	'src/r3emu/lua/state.cpp',
	'src/r3emu/r3emu.cpp',
	'src/r3emu/ui/font_texture.cpp',
	'src/r3emu/ui/host_window.cpp',
	'src/r3emu/ui/view.cpp',
	'src/r3emu/utility/console.cpp',
], dependencies: [
	subproject('sdlstuff').get_variable('sdlstuff_dep'),
	dependency('luajit'),
	dependency('threads'),
	dependency('libedit'),
])
