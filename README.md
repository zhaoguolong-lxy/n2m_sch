# Fair Arbiter (iSLIP crossbar scheduler)

[中文文档](README.zh-CN.md) · [Scheme diagram](diagram/fair_arbiter_scheme.svg) · [Algorithm animation](diagram/fair_arbiter_animation.svg)

A parameterizable N-to-M fair arbiter: every cycle it produces an orthogonal
(one-to-one) matching between N sources and M destinations, with round-robin
fairness on both sides, zero-latency (same-cycle) grant, and source/destination
backpressure.

## Files

```
rtl/fair_arbiter.v      synthesizable RTL (N, M, PTR_RESET parameters)
tb/tb_fair_arbiter.sv   self-checking testbench (16 scenarios x 11 configs)
sim/run_sim.sh          compile + run wrapper (optional)
synth/synth.ys          Yosys synthesis + PPA script
synth/rr_compare.v      arbiter-core A/B comparison (PPA iteration)
docs/scheme.md          design + scheme diagram
docs/testpoints.md      test point matrix + results
docs/ppa.md             synthesis / PPA results
```

## Build & run simulation

Requires Icarus Verilog (iverilog). On Windows with oss-cad-suite, put `bin`
and `lib` on PATH first (DLLs / lib-ivl).

```
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

Expected: `RESULT: ALL CONFIGURATIONS PASSED` (125,702 checks).

## Synthesize (PPA)

```
yosys -s synth/synth.ys        # prints area stats for 4 configs
```

## Parameters

| Param | Meaning | Default |
|-------|---------|---------|
| N | number of sources (>= 2) | 8 |
| M | number of destinations (>= 2) | 8 |
| PTR_RESET | 0 = no-reset pointers (area), 1 = async reset | 1 |
| ITER | matching iterations (1 = area-optimal, 2..3 = higher throughput) | 2 |

## Interface

```
clk, rst_n                        clock, active-low async reset
i_src_dest_req[N-1:0][M-1:0]      source n requests dest m
i_src_bp[N-1:0]                   backpressure on source n
i_dest_bp[M-1:0]                  backpressure on dest m
o_grant_rand_vld[N-1:0][M-1:0]    granted match (orthogonal)
o_grant_src_vld[N-1:0]            source n got a grant
o_grant_src_ptr[N-1:0][$clog2(M)-1:0]   dest index for source n
o_grant_dest_vld[M-1:0]           dest m got a grant
o_grant_dest_ptr[M-1:0][$clog2(N)-1:0]  source index for dest m
```
