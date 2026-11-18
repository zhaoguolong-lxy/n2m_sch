#!/usr/bin/env bash
# Run the complete fair_arbiter verification suite with Icarus Verilog.
# Requires oss-cad-suite bin/lib on PATH (DLLs and lib/ivl sub-tools).
#
# This is a LONG regression (tens of minutes): the maximality guarantee makes
# the DUT combinatorially deep, and the soak tests deliberately run thousands
# of cycles.  Run pieces individually while iterating.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p sim

echo "=== 1/7 main regression (22 configs, 17 scenarios) ==="
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp

echo "=== 2/7 maximality sweep (18 N/M shapes, WFA + random/adversarial) ==="
iverilog -g2012 -Wall -s tb_maximal_top -o sim/maximal.vvp rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp

echo "=== 3/7 randomized soak (4 shapes incl. 16x16, with backpressure) ==="
iverilog -g2012 -Wall -s tb_soak_top -o sim/soak.vvp rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp

echo "=== 4/7 10x10 20k-cycle soak (default config) ==="
iverilog -g2012 -Wall -s tb_soak10_top -o sim/soak10.vvp rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak10.vvp

echo "=== 5/7 reset / X-state checks ==="
iverilog -g2012 -s tb_x_check -o sim/xcheck.vvp rtl/fair_arbiter.v tb/tb_x_check.sv
vvp sim/xcheck.vvp

echo "=== 6/7 throughput benchmark (WFA, long run) ==="
iverilog -g2012 -Wall -s tb_perf_top -o sim/perf.vvp rtl/fair_arbiter.v tb/tb_perf.sv
vvp sim/perf.vvp

echo "=== 7/7 exhaustive algorithm-level WFA check ==="
python scripts/verify_wfa.py

echo "ALL CHECKS PASSED"
