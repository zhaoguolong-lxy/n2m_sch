#!/usr/bin/env bash
# Compile and run the fair_arbiter testbench with Icarus Verilog.
# Requires oss-cad-suite bin/lib on PATH (DLLs and lib/ivl sub-tools).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p sim
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
