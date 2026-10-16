#!/bin/bash
# Bitslice TX gating bench (Vivado xsim): see tb.v. Usage: ./run.sh [TX_GATING] [SELF_CALIBRATE]
#   source /path/to/Vivado/<version>/settings64.sh first.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${XILINX_VIVADO:-}" ]; then echo "XILINX_VIVADO is not set: source settings64.sh first" >&2; exit 1; fi
gating="${1:-ENABLE}"; selfcal="${2:-ENABLE}"
work="$here/xsim_work"; mkdir -p "$work"; cd "$work"
xvlog -sv "$here/tb.v" "$XILINX_VIVADO/data/verilog/src/glbl.v" > xvlog.out
xelab -timescale 1ps/1ps -L unisims_ver -L secureip -generic_top "TX_GATING=$gating" -generic_top "SELF_CAL=$selfcal" \
    tb glbl -s spike > xelab.out
xsim spike -R > sim.log 2>&1 || true
grep -E "RESULT|ERROR" sim.log xvlog.out xelab.out | grep -v "XSIM 43-3431" | sed "s|^sim.log:||"
