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
    pipe)
        MODULE=fair_arbiter_pipe
        SRC="rtl/wfa_core_pipe.v rtl/fair_arbiter_pipe.v"
        ;;
    *)
        echo "usage: $0 [fast|fair|pipe]" >&2
        exit 2
        ;;
esac

for shape in 8x8 10x10 9x11 11x9 16x16; do
    n="${shape%x*}"
    m="${shape#*x}"
    echo "=== $MODE $shape ==="
    yosys -p "read_verilog -sv $SRC; chparam -set N $n -set M $m $MODULE; synth -top $MODULE; flatten; stat; ltp -noff" 2>&1 \
        | grep -E "^ +[0-9]+ +cells$|Longest topological path"
done
