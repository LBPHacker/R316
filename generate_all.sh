#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

# this script requires that submodules be checked out, i.e. git submodule update --init
# set SPAGHETTI_INSTALL_DIR if spaghetti is installed somewhere where luajit can't find it by default
if [[ ! -z "${SPAGHETTI_INSTALL_DIR:-}" ]]; then
	export LUA_CPATH="$SPAGHETTI_INSTALL_DIR/?.so"
fi

function generate() {
	luajit TPT-Script-Manager/modulepack.lua modulepack.build.conf:spaghetti/modulepack.build.conf run "$1" plot none build "$2"
}
generate "r3.comp.cpu.core core_type=m" r3/comp/cpu/core/generated_m.lua
generate "r3.comp.cpu.core core_type=s" r3/comp/cpu/core/generated_s.lua
generate "r3.comp.cpu.core core_type=f" r3/comp/cpu/core/generated_f.lua
generate "r3.comp.cpu.rread"            r3/comp/cpu/rread/generated.lua
generate "r3.comp.terminal.core"        r3/comp/terminal/core/generated.lua
generate "r3.comp.terminal.kbdcore"     r3/comp/terminal/kbdcore/generated.lua
