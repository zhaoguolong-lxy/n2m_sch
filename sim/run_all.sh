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

echo "=== 1/13 main regression (17 configs, 17 scenarios) ==="
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp

echo "=== 2/13 strict single-source / single-destination fairness ==="
iverilog -g2012 -Wall -s tb_fairness_top -o sim/fairness.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp

echo "=== 3/13 fair-variant main regression (17 configs, iSLIP first + WFA fill) ==="
iverilog -g2012 -Wall -DFAIR_DUT -s tb_top -o sim/sim_fair.vvp rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fair_arbiter.sv
vvp sim/sim_fair.vvp

echo "=== 4/13 fair-variant strict fairness ==="
iverilog -g2012 -Wall -s tb_fairness_fair_top -o sim/fairness_fair.vvp rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fairness_fair.sv
vvp sim/fairness_fair.vvp

echo "=== 5/13 maximality sweep (11 shapes, max 10x10, random/adversarial) ==="
iverilog -g2012 -Wall -s tb_maximal_top -o sim/maximal.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp

echo "=== 6/13 randomized soak (3 shapes, max 10x10, with backpressure) ==="
iverilog -g2012 -Wall -s tb_soak_top -o sim/soak.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp

echo "=== 7/13 10x10 20k-cycle soak (default config) ==="
iverilog -g2012 -Wall -s tb_soak10_top -o sim/soak10.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak10.vvp

echo "=== 8/13 reset / X-state checks ==="
iverilog -g2012 -s tb_x_check -o sim/xcheck.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_x_check.sv
vvp sim/xcheck.vvp

echo "=== 9/13 throughput benchmark (WFA, long run) ==="
iverilog -g2012 -Wall -s tb_perf_top -o sim/perf.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_perf.sv
vvp sim/perf.vvp

echo "=== 10/13 exhaustive algorithm-level WFA check ==="
python scripts/verify_wfa.py

echo "=== 11/13 multi-source fairness model (WFA vs fair) ==="
python scripts/fairness_compare.py

echo "=== 12/13 multi-source Jain on the RTL (default bank) ==="
iverilog -g2012 -s tb_jain_top -o sim/jain.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_jain.sv
vvp sim/jain.vvp

echo "=== 13/13 shared-queue drain model (window sweep) ==="
python scripts/queue_drain.py

echo "ALL CHECKS PASSED"
