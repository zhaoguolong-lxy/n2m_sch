# Fair Arbiter (Wavefront crossbar scheduler)

[中文文档](README.zh-CN.md) · [WFA circuit diagrams](diagram/circuit/README.md) · [Old iSLIP scheme](diagram/fair_arbiter_scheme.svg)

A parameterizable N-to-M fair arbiter: every cycle it produces an orthogonal
(one-to-one) matching between N sources and M destinations, with rotating
priority fairness, zero-latency (same-cycle) grant, and source/destination
backpressure.  The default implementation is the **Wavefront Arbiter
(WFA/WWFA)**: P=max(N,M) torus diagonals, P combinational stages, and only one
small rotating-start register.

**Hard guarantee:** the matching is *maximal* every cycle, for every N and M.
A requested pair is never left unserved when both its source and its
destination are idle (the exact "no wasted scheduling opportunity" criterion).
This holds for 10x10, non-power-of-two sizes, N<M and N>M alike.

**Verification summary:** 22 configurations / 295,797 checks pass; 18 N/M
shapes (2x2 ... 16x16, including 10x10) report 0 non-maximal cycles, 0 wasted
pairs and 0 orthogonality violations over 773 cycles each; long randomized soak
(4 shapes x 1500 cycles with random backpressure, plus 10x10 x 20,000 cycles /
720,096 request instants) reports 0 non-maximal cycles and 0 invariant
violations; the WFA algorithm-level script checks 94,475 cases (exhaustive for
small shapes, every shape 2..16) with 0 failures; reset and X-state checks pass.

## Detailed circuit-level diagrams (PNG)

The low-depth **Wavefront Arbiter (WFA/WWFA)** variant is documented as
circuit-level PNG diagrams ("总 / 分" set): cell gates, diagonal stages,
rotating priority, the no-waste proof, and the depth/area metric.

- [Overview](diagram/circuit/wfa_00_overview.png)
- [Crosspoint cell](diagram/circuit/wfa_01_cell.png)
- [Diagonal stages](diagram/circuit/wfa_02_diagonal.png)
- [Priority rotation / fairness](diagram/circuit/wfa_03_rotation.png)
- [No-waste example](diagram/circuit/wfa_04_nowaste.png)
- [Depth / area metric](diagram/circuit/wfa_05_depth.png)

Index and algorithm comparison: [diagram/circuit/README.md](diagram/circuit/README.md).
The default RTL (`rtl/fair_arbiter.v`) is now the WFA implementation; 10x10 maps to 2062 cells / 35 gate levels, vs 11821 cells /
300 levels for the iSLIP+fill version.  It is maximal (no wasted pair) but not
maximum-cardinality, and its per-port RR order is relaxed (the two sides rotate
in opposite directions); see the index for the exact tradeoff.  The <=40-level
target is met at 8x8/10x10/9x11/11x9; 16x16 is 8 levels over and has a
documented 2-cycle / hierarchical optimization path.  The RTL uses a
log-depth cyclic rotator for the delta priority and an N>M transpose wrapper
(pure wiring), so 11x9 reuses the 9x11 core.

## Files

```
rtl/fair_arbiter.v      default WFA RTL (N, M, PTR_RESET; ITER/AUGMENT legacy/ignored)
rtl/reference/fair_arbiter_islip.v  strict-RR iSLIP+fill reference
tb/tb_fair_arbiter.sv   main self-checking regression (17 scenarios x 22 configs)
tb/tb_maximal.sv        maximality + orthogonality + output-consistency checker
tb/tb_soak.sv           long randomized soak (thousands of cycles, backpressure)
tb/tb_perf.sv           throughput benchmark
tb/tb_x_check.sv        reset / X-state checks
scripts/verify_wfa.py     exhaustive WFA maximality / orthogonality check
scripts/verify_maximal.py  same check for the old iSLIP+fill reference
sim/run_sim.sh          compile + run wrapper (optional)
sim/run_all.sh          full verification suite (all of the above)
synth/synth.ys          Yosys synthesis + depth/area sweep (WFA)
synth/synth_islip.ys    synthesis sweep for the iSLIP reference
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

Expected: `RESULT: ALL CONFIGURATIONS PASSED`.

Maximality checker (18 N/M shapes, long random run, adversarial patterns,
includes 10x10):

```
iverilog -g2012 -s tb_maximal_top -o sim/maximal.vvp rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp
```

Long randomized soak (4 shapes x 1500 cycles with random backpressure, plus
10x10 x 20000 cycles):

```
iverilog -g2012 -s tb_soak_top   -o sim/soak.vvp   rtl/fair_arbiter.v tb/tb_soak.sv
iverilog -g2012 -s tb_soak10_top -o sim/soak10.vvp rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp
vvp sim/soak10.vvp
```

Everything (main + maximality + soak + X + throughput + exhaustive check):

```
bash sim/run_all.sh
```

Exhaustive algorithm check (all request matrices for small shapes, every shape
2..16, every WFA start offset):

```
python scripts/verify_wfa.py
```

## Synthesize (PPA)

```
yosys -s synth/synth.ys        # prints area stats for the sweep
```

## Parameters

| Param | Meaning | Default |
|-------|---------|---------|
| N | number of sources (>= 2) | 8 |
| M | number of destinations (>= 2) | 8 |
| PTR_RESET | 0 = no-reset delta (area), 1 = async reset | 1 |
| ITER | legacy, ignored by the WFA (kept for reference TB compatibility) | 4 |
| AUGMENT | legacy, ignored by the WFA | 1 |

Random-traffic matching size of the WFA is 86% (8x8), 89% (10x10), 92% (16x16)
and 96-100% when N!=M.  This is lower than the old iSLIP+augment 97-98% because
the WFA is maximal but not maximum-cardinality, which is the accepted tradeoff
for depth.  The old iSLIP+fill reference (`ITER`/`AUGMENT`) reaches 97-98% but
costs 300 levels at 10x10; see `docs/ppa.md`.

## Maximality guarantee

The default WFA is **maximal by construction**.  The P torus diagonals visit
every crosspoint exactly once.  Suppose a requested pair `(i,j)` still has both
its source and destination idle at the end.  The free row/column sets only
shrink during the wave, so both were still free when `(i,j)`'s diagonal was
evaluated; the cell would therefore have granted.  Contradiction.  Hence no
requested pair is left unserved when both ends are idle, for every N/M.

This is *maximal*, not *maximum*: a source can lose when its only requested
destination was taken by an earlier diagonal.  `scripts/verify_wfa.py` checks
this exhaustively for all request matrices of small shapes and on 94,475 cases
across every shape 2..16 / every start offset; `tb/tb_maximal.sv` reports zero
violations on 18 RTL shapes, including 10x10.

The earlier iSLIP + **residual fill** reference achieves maximality the same
way with a serial dictatorship over sources (see
`rtl/reference/fair_arbiter_islip.v` and `docs/scheme.md`); it is kept for
comparison and for strict per-port RR order.

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
