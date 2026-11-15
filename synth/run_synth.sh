#!/usr/bin/env bash
# Synthesize the fair_arbiter and print PPA statistics.
# Requires oss-cad-suite bin/lib on PATH (DLLs).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

yosys -s synth/synth.ys
