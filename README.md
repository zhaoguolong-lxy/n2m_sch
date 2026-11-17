# Fair Arbiter (iSLIP crossbar scheduler)

[中文文档](README.zh-CN.md) · [Scheme diagram](diagram/fair_arbiter_scheme.svg) · [Algorithm animation](diagram/fair_arbiter_animation.svg)

A parameterizable N-to-M fair arbiter: every cycle it produces an orthogonal
(one-to-one) matching between N sources and M destinations, with round-robin
fairness on both sides, zero-latency (same-cycle) grant, and source/destination
backpressure.

**Hard guarantee:** the matching is *maximal* every cycle, for every N and M.
A requested pair is never left unserved when both its source and its
destination are idle (the exact "no wasted scheduling opportunity" criterion).
This holds for 10x10, non-power-of-two sizes, N<M and N>M alike.

**Verification summary:** 22 configurations / 294,356 checks pass; 18 N/M
shapes (2x2 ... 16x16, including 10x10) report 0 non-maximal cycles, 0 wasted
pairs and 0 orthogonality violations over 773 cycles each; long randomized soak
(4 shapes x 1500 cycles with random backpressure, plus 10x10 x 20,000 cycles /
720,096 request instants) reports 0 non-maximal cycles and 0 invariant
violations; the algorithm-level script checks 67,118 cases (exhaustive for small
shapes, every shape 2..16) with 0 failures; reset and X-state checks pass.

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
The WFA RTL (`rtl/fair_arbiter_torus.v`) has the same ports/parameters as the
main design; 10x10 maps to 3699 cells / 39 gate levels, vs 11821 cells /
300 levels for the iSLIP+fill version.  It is maximal (no wasted pair) but not
maximum-cardinality, and its per-port RR order is relaxed (the two sides rotate
in opposite directions); see the index for the exact tradeoff.  The <=40-level
target is met at 8x8/10x10; 9x11, 11x9 and 16x16 are 1-8 levels over and have a
documented 2-cycle / hierarchical optimization path.

## Files

```
rtl/fair_arbiter.v      synthesizable RTL (N, M, PTR_RESET, ITER, AUGMENT)
tb/tb_fair_arbiter.sv   main self-checking regression (17 scenarios x 22 configs)
tb/tb_maximal.sv        maximality + orthogonality + output-consistency checker
tb/tb_soak.sv           long randomized soak (thousands of cycles, backpressure)
tb/tb_perf.sv           throughput benchmark
tb/tb_x_check.sv        reset / X-state checks
scripts/verify_maximal.py  exhaustive algorithm-level maximality proof check
sim/run_sim.sh          compile + run wrapper (optional)
sim/run_all.sh          full verification suite (all of the above)
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
2..16, arbitrary base matchings):

```
python scripts/verify_maximal.py
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
| PTR_RESET | 0 = no-reset pointers (area), 1 = async reset | 1 |
| ITER | greedy matching iterations | 4 |
| AUGMENT | 1 = swap/augmenting pass (larger matching, relaxed fairness) | 1 |

The residual-fill stage is always present and is what guarantees maximality.
`AUGMENT` only affects the matching SIZE: `1` gives 97-98% of min(N,M) at
8x8/10x10 (95% at 16x16, ~100% when N!=M) on random traffic, at the cost of
relaxed round-robin fairness; `0` gives 89-91% at 8x8/10x10 with strict iSLIP
fairness.  `ITER=2, AUGMENT=1` reaches the same 97-98% as ITER=4 with ~30-36%
fewer cells (see `docs/ppa.md`).

## Maximality guarantee

A finite number of iSLIP passes is not guaranteed to be maximal for every
request pattern, and a parallel swap can move a match without completing its
replacement. The design therefore ends with a **residual fill** that only ADDS
matches to still-unmatched sources / still-free destinations:

```
for i = 0 .. N-1:
    if source i unmatched: take a requested destination that is still free
```

Adding an edge can never create a new wasted pair (both endpoints would have
to be idle), and the fill leaves no requested pair with both ends idle: if
`(i,j)` survived, `j` was free on `i`'s turn (the free set only shrinks), so
`i` would have taken some destination. Hence the final matching is maximal for
every N/M. `scripts/verify_maximal.py` checks this exhaustively for all request
matrices of small shapes and on 67k+ cases across every shape 2..16; the RTL
checker `tb/tb_maximal.sv` reports zero violations for all 18 tested shapes.

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
