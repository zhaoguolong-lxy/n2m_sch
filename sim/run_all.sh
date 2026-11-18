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

echo "=== 1/8 main regression (22 configs, 17 scenarios) ==="
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp

echo "=== 2/8 strict single-source / single-destination fairness ==="
iverilog -g2012 -Wall -s tb_fairness_top -o sim/fairness.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp

echo "=== 3/8 maximality sweep (18 N/M shapes, WFA + random/adversarial) ==="
iverilog -g2012 -Wall -s tb_maximal_top -o sim/maximal.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp

echo "=== 4/8 randomized soak (4 shapes incl. 16x16, with backpressure) ==="
iverilog -g2012 -Wall -s tb_soak_top -o sim/soak.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp

echo "=== 5/8 10x10 20k-cycle soak (default config) ==="
iverilog -g2012 -Wall -s tb_soak10_top -o sim/soak10.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak10.vvp

echo "=== 6/8 reset / X-state checks ==="
iverilog -g2012 -s tb_x_check -o sim/xcheck.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_x_check.sv
vvp sim/xcheck.vvp

echo "=== 7/8 throughput benchmark (WFA, long run) ==="
iverilog -g2012 -Wall -s tb_perf_top -o sim/perf.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_perf.sv
vvp sim/perf.vvp

echo "=== 8/8 exhaustive algorithm-level WFA check ==="
python scripts/verify_wfa.py

echo "ALL CHECKS PASSED"
