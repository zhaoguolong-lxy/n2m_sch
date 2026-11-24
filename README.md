# Fair Arbiter (Wavefront crossbar scheduler)

[中文文档](README.zh-CN.md) · [WFA circuit diagrams](diagram/circuit/README.md) · [Old iSLIP scheme](diagram/fair_arbiter_scheme.svg)

A parameterizable N-to-M fair arbiter: every cycle it produces an orthogonal
(one-to-one) matching between N sources and M destinations, with rotating
priority fairness, zero-latency (same-cycle) grant, and source/destination
backpressure.  The default implementation is a **replicate/bank Wavefront
Arbiter**: P fixed-delta WFA cores run in parallel, their diagonal rotations
are compile-time wiring, and a registered one-hot bank select picks one core.
It combines that with a parallel **single-source / single-destination RR
override**:
- general traffic -> bank WFA (maximal / no wasted scheduling, low depth);
- exactly one active source -> a per-source `a_ptr` RR selector chooses the
  next requested destination, so the source's destination sequence is strict RR;
- exactly one active destination -> a per-destination `g_ptr` RR selector
  chooses the next requested source, so the destination's source sequence is
  strict RR.

**Hard guarantee:** the matching is *maximal* every cycle, for every N and M.
A requested pair is never left unserved when both its source and its
destination are idle (the exact "no wasted scheduling opportunity" criterion).
This holds for 10x10, non-power-of-two sizes, N<M and N>M alike.

**Verification summary:** 17 configurations / 192,860 checks pass; 11 N/M
configurations (2x2 ... 10x10, including three 10x10 variants) report 0
non-maximal cycles, 0 wasted pairs and 0 orthogonality violations over 773
cycles each; long randomized soak (3 configurations, max 10x10, x 1500 cycles
with random backpressure, plus 10x10 x 20,000 cycles / 720,096 request
instants) reports 0 non-maximal cycles and 0 invariant violations; the WFA
algorithm-level script checks 94,475 cases (exhaustive for small shapes, every
shape 2..16) with 0 failures; the strict single-source / single-destination
fairness test passes 24/24; reset and X-state checks pass.

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
- [Single-source / single-destination fairness override](diagram/circuit/wfa_06_fairness.png)
- [Fair variant: iSLIP first pass + WFA fill](diagram/circuit/wfa_07_fair_hybrid.png)

Index and algorithm comparison: [diagram/circuit/README.md](diagram/circuit/README.md).
The default RTL (`rtl/fair_arbiter.v`) is the **replicate/bank WFA** plus the
single-side fairness override and wavefront+: P fixed-delta cores, no runtime
barrel rotator, registered one-hot bank select.  10x10 maps to **12661 cells /
30 generic Yosys levels** (8x8: 6386 / 26).  Generic Yosys has no AOI21 cell,
so it maps the wavefront cell to two levels; with the real AOI21 library the
wavefront is one level per stage.  The old rotating NSCHED=1 top was 5366 / 35;
the iSLIP+fill version is 11821 / 300.  General traffic is maximal but not
maximum-cardinality.  Single-source and single-destination sequences are strict
RR (24/24 tests for the default bank).

The bank select uses a registered one-hot `delta_oh` that lags `delta` by one
cycle; this keeps the wavefront+ next-state priority logic off the output path.
`NSCHED` is accepted but ignored in the default top (single schedule); the old
rotating `NSCHED=1..4` implementation is kept in
`rtl/reference/fair_arbiter_rot.v` for the multi-schedule fairness comparison.
Random multi-source Jain of the default is 0.821-0.887 src / 0.805-0.871 dst;
K-regular remains 1.000.  SKY130HD: 7108 cells / 39794 um^2 / 3877 ps at
10x10 (8x8: 3424 / 20453 / 3634 ps).

An optional **4-schedule fairness top** (`rtl/fair_arbiter_sched4.v`, module
`fair_arbiter_sched4`) keeps the same interface and time-multiplexes four
fixed schedule permutations on one bank.  A registered uniform-degree
detector keeps the single wavefront+ schedule for K-regular traffic.  It
gives random 10x10 Jain **0.914-0.933 src / 0.895-0.934 dst** and K-regular
**1.000**, at **12129 cells / 28 levels with the AOI-capable cmos mapping**
(15199 / 40 under the old NAND/NOR-only mapping) and SKY130HD **9040 cells /
53953 um^2 / 4522 ps**.
It is a fairness mode, not the depth-first default.  Full comparison:
`docs/optimization.md`.

## Fast vs fair variants

Both variants have the same required top-level interface; they differ only in
internal scheduling.

| Variant | RTL | Strict single-source / single-destination | Multi-source fairness | 10x10 PPA |
|---------|-----|-------------------------------------------|-----------------------|-----------|
| **fast (default, bank)** | `rtl/fair_arbiter.v` | **24/24** | bank WFA + wavefront+ (Jain 0.821-0.887 src / 0.805-0.871 dst) | **12661 cells / 30 generic; 7108 / 39794um2 / 3877ps SKY130** |
| legacy rotating, 4-schedule | `rtl/reference/fair_arbiter_rot.v` `NSCHED=4` | **42/42 (historical)** | 4-schedule WFA + wavefront+ (Jain 0.914-0.933 src / 0.895-0.934 dst) | 11255 cells / 36 generic |
| **fair** | `rtl/fair_arbiter_fair.v` | **24/24** | iSLIP first pass + WFA fill (Jain 0.87-0.90 src / 0.91-0.93 dst) | 5119 cells / 74 levels |
| **fairness top (optional)** | `rtl/fair_arbiter_sched4.v` | **24/24** | 4 schedules + adaptive gate (Jain 0.914-0.933 src / 0.895-0.934 dst, K-reg 1.000) | 12129 / 28 cmos (15199 / 40 old map); SKY 9040 / 53953 / 4522 ps |
| strict reference | `rtl/reference/fair_arbiter_islip.v` | strict all traffic | strict iSLIP+serial fill | 11821 / 300 |

### Multi-schedule fairness (legacy rotating reference)

The default bank top is single-schedule.  The legacy rotating reference
(`rtl/reference/fair_arbiter_rot.v`) still supports `NSCHED` wavefronts in
parallel.  Schedule s permutes the core rows by `r -> (c_s*r) mod N` with a
different coprime `c_s` (pure wiring, no mux), and the selected schedule
rotates every P grants.  This flattens the long-run grant distribution:

| Scheme | src Jain (10x10) | dst Jain (10x10) | 10x10 cells / levels |
|--------|------------------|------------------|----------------------|
| **bank default** | **0.821-0.887** | **0.805-0.871** | **12661 / 30** |
| legacy rotating NSCHED=2 | 0.867-0.901 | 0.873-0.905 | 7395 / 35 |
| legacy rotating NSCHED=4 | 0.914-0.933 | 0.895-0.934 | 11255 / 36 generic |
| fair variant | 0.866-0.895 | 0.912-0.934 | 5119 / 74 |

The default-bank RTL checker `tb/tb_jain.sv` measures 0.821-0.887 src /
0.805-0.871 dst on three persistent patterns, with K-regular Jain 1.000.
The legacy rotating reference reproduces the NSCHED=2/4 numbers above; its
`NSCHED` parameter is not used by the default bank top.

### Shared-queue drain

When each source owns one multi-destination queue, the drain rate is set by
how much of the queue the front end exposes.  For 10x10 and 200 packets per
source: head-only FIFO 337 cycles, window 4 258 cycles, full buffer 235
cycles.  The arbiter's maximal matching adds no wasted cycles, and the
cardinality-only reference is *worse* (410 cycles) because it starves
sources.  Details and the full table: `docs/perf.md`.

Fair variant verification: main regression 192,884 checks PASS; maximality
11/11 (0 non-max / 0 wasted); 3-shape soak x 1500 PASS; 10x10 x 20,000 soak
PASS (146,049 grants, 0 violations); strict fairness 24/24 (4 shapes).
Its multi-source Jain averages (10x10 model, 3000-cycle
persistent patterns): pure WFA src 0.819-0.834 / dst 0.804-0.891; fair src
0.866-0.895 / dst 0.912-0.934.  Full crossbar is 1.000 for both.  The fair
variant is not a mathematical all-traffic RR guarantee (fill-only ports are
approximate).  The legacy 4-schedule option is fairer on average at 36
levels; the bank default is the depth/area choice, and the fair variant is
kept as an independent alternative.

Run the fair variant:

```
iverilog -g2012 -DFAIR_DUT -s tb_top -o sim/sim_fair.vvp     rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fair_arbiter.sv
vvp sim/sim_fair.vvp

iverilog -g2012 -s tb_fairness_fair_top -o sim/fairness_fair.vvp     rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fairness_fair.sv
vvp sim/fairness_fair.vvp
```

## Files

```
rtl/fair_arbiter.v      default bank top (exact required ports; N,M,PTR_RESET)
rtl/fair_arbiter_sched4.v optional 4-schedule fairness top (same interface)
rtl/wfa_core_fixed.v    constant-delta P-stage wavefront core (bank)
rtl/wfa_core.v          rotating P-stage wavefront core (legacy reference)
rtl/fair_arbiter_fair.v optional fair variant (iSLIP first pass + WFA fill)
rtl/reference/fair_arbiter_rot.v    legacy rotating NSCHED=1..4 top
rtl/reference/fair_arbiter_islip.v  strict-RR iSLIP+fill reference
rtl/reference/fair_arbiter_dpa.v    single-pass DPA (21 levels, non-maximal)
rtl/reference/wfa_core_tr.v         token-ring WFA experiment (non-maximal)
rtl/fair_arbiter_wtf.v              WTF-style prototype (iSLIP + row fill)
rtl/fair_arbiter_greedy.v           greedy base + per-port override (comparison)
tb/tb_fair_arbiter.sv   main self-checking regression (17 scenarios x 17 configs)
tb/tb_maximal.sv        maximality + orthogonality + output-consistency checker
tb/tb_soak.sv           long randomized soak (thousands of cycles, backpressure)
tb/tb_jain.sv           multi-source Jain index on the default bank RTL
tb/tb_fairness.sv       strict fairness tests for the fast variant
tb/tb_fairness_fair.sv  strict fairness tests for the fair variant
tb/tb_perf.sv           throughput benchmark
tb/tb_x_check.sv        reset / X-state checks
scripts/verify_wfa.py     exhaustive WFA maximality / orthogonality check
scripts/fairness_compare.py  multi-source Jain model: WFAx1/x2/x4, wavefront+
scripts/fairness_explore.py  bank selection-policy / schedule fairness model
scripts/queue_drain.py      shared-queue drain model (window sweep)
scripts/verify_maximal.py  same check for the old iSLIP+fill reference
sim/run_sim.sh          compile + run wrapper (optional)
sim/run_all.sh          full verification suite (all of the above)
synth/synth.ys          Yosys synthesis + depth/area sweep (WFA)
synth/synth_islip.ys    synthesis sweep for the iSLIP reference
synth/synth_fair.ys     synthesis / depth sweep for the fair variant
synth/sky130.constr     SKY130 HD ABC constraints (inv_2, 10 fF)
docs/scheme.md          design + scheme diagram
docs/testpoints.md      test point matrix + results
docs/ppa.md             synthesis / PPA results
docs/literature.md      literature survey: DPA/WFA/RR/depth (70 refs)
```

## Build & run simulation

Requires Icarus Verilog (iverilog). On Windows with oss-cad-suite, put `bin`
and `lib` on PATH first (DLLs / lib-ivl).

```
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

Expected: `RESULT: ALL CONFIGURATIONS PASSED`.

Maximality checker (11 N/M shapes, max 10x10, long random run, adversarial
patterns):

```
iverilog -g2012 -s tb_maximal_top -o sim/maximal.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp
```

Long randomized soak (3 shapes, max 10x10, x 1500 cycles with random
backpressure, plus 10x10 x 20000 cycles):

```
iverilog -g2012 -s tb_soak_top   -o sim/soak.vvp   rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
iverilog -g2012 -s tb_soak10_top -o sim/soak10.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp
vvp sim/soak10.vvp
```

Strict fairness test (single source -> many destinations; many sources ->
one destination; all/even/odd subsets; 4 shapes, max 10x10):

```
iverilog -g2012 -s tb_fairness_top -o sim/fairness.vvp     rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp
```

Optional 4-schedule fairness top (compile the wrapper instead of the default
top):

```
iverilog -g2012 -s tb_jain_top -o sim/jain4.vvp \
    rtl/wfa_core_fixed.v rtl/fair_arbiter_sched4.v \
    tb/fair_arbiter_sched4_wrap.v tb/tb_jain.sv
vvp sim/jain4.vvp
```

Everything (main + maximality + soak + fairness + X + throughput + exhaustive check):

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
bash synth/run_synth.sh         # fast: area/depth per shape
bash synth/run_synth.sh fair    # optional fair variant
bash synth/run_synth.sh sky130  # SKY130HD: cells, AOI21 count, ABC delay

# optional 4-schedule fairness top, AOI-capable generic mapping
FAIR_SCHED=4 MAP=cmos bash synth/run_synth.sh fast
# optional 4-schedule fairness top, SKY130HD
FAIR_SCHED=4 bash synth/run_synth.sh sky130
```

## Parameters

| Param | Meaning | Default |
|-------|---------|---------|
| N | number of sources (>= 2) | 8 |
| M | number of destinations (>= 2) | 8 |
| PTR_RESET | 0 = no-reset bank delta (area), 1 = async reset | 1 |
| NSCHED | legacy compatibility; ignored by the default bank top | 1 |
| WAVEFRONT_PLUS | 1 = registered presence skip; 0 = delta+1 | 1 |
| AOI_STYLE | 1 = AOI21-form token update; 0 = AND/NAND | 1 |
| SEL_OH | 1 = registered one-hot bank select; 0 = binary select | 1 |
| ITER | legacy, ignored by the bank/WFA | 4 |
| AUGMENT | legacy, ignored by the bank/WFA | 1 |

Random-traffic matching size of the WFA is 86% (8x8) and 89% (10x10); N!=M is
96-100% in the model.  This is lower than the old iSLIP+augment 97-98% because
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
violations on 11 RTL shapes, max 10x10.

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
