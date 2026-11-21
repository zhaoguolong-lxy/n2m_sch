#!/usr/bin/env bash
# Synthesize the arbiter and print PPA statistics.
# Requires oss-cad-suite bin/lib on PATH (DLLs).
#
# Usage: bash synth/run_synth.sh [fast|fair]
#
# Each shape runs in a fresh yosys process.  yosys' internal auto-index
# counter keeps growing across `design -reset`, which perturbs ABC's mapping
# and nudges the reported depth by +-1 level; fresh processes keep the
# numbers stable and reproducible.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-fast}"
case "$MODE" in
    fast)
        MODULE=fair_arbiter
        SRC="rtl/wfa_core.v rtl/fair_arbiter.v"
        ;;
    fair)
        MODULE=fair_arbiter_fair
        SRC="rtl/wfa_core.v rtl/fair_arbiter_fair.v"
        ;;
    sky130)
        MODULE=fair_arbiter
        SRC="rtl/wfa_core.v rtl/fair_arbiter.v"
        LIB="${SKY130_LIB:-D:/opencode/rtl_gen/pdk/sky130hd/sky130_fd_sc_hd__tt_025C_1v80.lib}"
        if [ ! -f "$LIB" ]; then
            echo "SKY130 Liberty not found: $LIB" >&2
            echo "Set SKY130_LIB to the .lib path (Windows path, e.g. D:/...)." >&2
            exit 2
        fi
        CONSTR="$(cygpath -w "$ROOT/synth/sky130.constr" 2>/dev/null \
                  || echo "$ROOT/synth/sky130.constr")"
        ;;
    *)
        echo "usage: $0 [fast|fair|sky130]" >&2
        exit 2
        ;;
esac

if [ "$MODE" = "sky130" ]; then
    for shape in ${SKY130_SHAPES:-8x8 10x10 9x11 11x9}; do
        n="${shape%x*}"
        m="${shape#*x}"
        echo "=== sky130 $shape ==="
        log="$(mktemp)"
        yosys -p "read_verilog -sv $SRC; chparam -set N $n -set M $m $MODULE; synth -top $MODULE; flatten; dfflibmap -liberty $LIB; abc -liberty $LIB -constr $CONSTR; opt_clean; stat" > "$log" 2>&1
        grep -E "^ +[0-9]+ +cells$" "$log" | tail -1 | sed 's/^/cells:/'
        grep -E "sky130_fd_sc_hd__a21oi_1" "$log" | tail -1 | sed 's/^/aoi21:/'
        grep "WireLoad" "$log" | tail -1 | sed 's/^ABC: //'
        rm -f "$log"
    done
    exit 0
fi

for shape in 8x8 10x10 9x11 11x9 16x16; do
    n="${shape%x*}"
    m="${shape#*x}"
    echo "=== $MODE $shape ==="
    yosys -p "read_verilog -sv $SRC; chparam -set N $n -set M $m $MODULE; synth -top $MODULE; flatten; stat; ltp -noff" 2>&1 \
        | grep -E "^ +[0-9]+ +cells$|Longest topological path"
done
