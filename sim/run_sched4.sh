#!/usr/bin/env bash
# Verification for the optional 4-schedule fairness top.
# Same testbenches as the default suite, compiled with the sched4 top wrapper
# instead of rtl/fair_arbiter.v.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p sim

SRC="rtl/wfa_core_fixed.v rtl/fair_arbiter_sched4.v tb/fair_arbiter_sched4_wrap.v"

echo "=== sched4 1/6 main regression ==="
iverilog -g2012 -Wall -DSCHED4_DUT -s tb_top -o sim/sched4_sim.vvp $SRC tb/tb_fair_arbiter.sv
vvp sim/sched4_sim.vvp

echo "=== sched4 2/6 maximality sweep ==="
iverilog -g2012 -Wall -s tb_maximal_top -o sim/sched4_maximal.vvp $SRC tb/tb_maximal.sv
vvp sim/sched4_maximal.vvp

echo "=== sched4 3/6 strict fairness ==="
iverilog -g2012 -Wall -s tb_fairness_top -o sim/sched4_fairness.vvp $SRC tb/tb_fairness.sv
vvp sim/sched4_fairness.vvp

echo "=== sched4 4/6 reset / X-state checks ==="
iverilog -g2012 -DSCHED4_DUT -s tb_x_check -o sim/sched4_x.vvp $SRC tb/tb_x_check.sv
vvp sim/sched4_x.vvp

echo "=== sched4 5/6 multi-source Jain ==="
iverilog -g2012 -s tb_jain_top -o sim/sched4_jain.vvp $SRC tb/tb_jain.sv
vvp sim/sched4_jain.vvp

echo "=== sched4 6/6 soak (3 shapes + 10x10 x 20,000) ==="
iverilog -g2012 -Wall -s tb_soak_top   -o sim/sched4_soak.vvp   $SRC tb/tb_soak.sv
iverilog -g2012 -Wall -s tb_soak10_top -o sim/sched4_soak10.vvp $SRC tb/tb_soak.sv
vvp sim/sched4_soak.vvp
vvp sim/sched4_soak10.vvp

echo "SCHED4 CHECKS PASSED"
