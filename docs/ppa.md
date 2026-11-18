# Fair Arbiter - Synthesis & PPA

> **Default RTL is now the Wavefront (WFA/WWFA) implementation** in
> `rtl/fair_arbiter.v` (section 8).  Sections 1-7 describe the earlier
> iSLIP + residual-fill reference (`rtl/reference/fair_arbiter_islip.v`) and are
> kept for comparison.

Synthesizer: Yosys 0.66 (`synth -top fair_arbiter`), generic gate library
(no standard-cell liberty file, so "area" = count of gate-level cells after
ABC mapping).  "Depth" = longest topological path from `ltp -noff`, in mapped
gate levels.  Every number includes the residual fill (the maximality
guarantee); the `AUGMENT` column adds the optional swap.

## 1. Round-robin arbiter core

The grant/accept round-robin uses the arithmetic find-first-one
`lowest_set(x) = x & ~(x - 1)` (one subtractor + NOT + AND), which is smaller
than a thermometer priority encoder at the target sizes (N,M <= 16):

| Arbiter core | W=8 | W=16 | W=32 |
|--------------|-----|------|------|
| thermometer priority encoder | 67 | 157 | 356 |
| arithmetic find-first-one | 59 | 154 | 358 |

Arithmetic is ~12% smaller at W=8, equal at W=16, slightly larger at W=32
(the thermometer encoder's O(W^2) OR tree gets heavily shared by ABC). For
this design's sizes, arithmetic is the better choice.

## 2. ITER sweep (8x8, AUGMENT=0, fill always on)

| ITER | Cells | Depth (gate levels) |
|------|-------|---------------------|
| 1 | 2291 | 129 |
| 2 | 3442 | 152 |
| 3 | 4705 | 174 |
| 4 | 6670 | 196 |

Each extra greedy pass adds ~1.2-2.0k cells and ~22 gate levels.  The residual
fill is the dominant fixed cost at low ITER (see section 4), while extra iSLIP
passes dominate at high ITER.

## 3. AUGMENT (swap) cost, 8x8 ITER=4

| AUGMENT | Cells | Depth | Purpose |
|---------|-------|-------|---------|
| 0 | 6670 | 196 | strict iSLIP fairness, still maximal |
| 1 | 7763 | 234 | +6-9% matching size on random traffic, relaxed fairness |

The swap costs ~16% cells and ~19% depth.  It is a size optimization only:
maximality is guaranteed by the fill in both cases.

## 4. Other configurations

| Config | Flops | Cells | Depth |
|--------|-------|-------|-------|
| 8x8, ITER=1, AUGMENT=0 | 48 | 2291 | 129 |
| 8x8, ITER=1, AUGMENT=1 | 48 | 3634 | 170 |
| 8x8, ITER=4, AUGMENT=0 | 48 | 6670 | 196 |
| 8x8, ITER=2, AUGMENT=1 | 48 | 4952 | 190 |
| 8x8, ITER=4, AUGMENT=1 (default) | 48 | 7763 | 234 |
| 8x4, ITER=4, AUGMENT=1 | 28 | 3110 | 112 |
| 10x10, ITER=1, AUGMENT=0 | 80 | 3983 | 175 |
| 10x10, ITER=1, AUGMENT=1 | 80 | 6212 | 221 |
| 10x10, ITER=2, AUGMENT=1 | 80 | 8257 | 252 |
| 10x10, ITER=4, AUGMENT=0 | 80 | 9722 | 258 |
| 10x10, ITER=4, AUGMENT=1 (default) | 80 | 11821 | 300 |
| 16x16, ITER=1, AUGMENT=0 | 128 | 10115 | 372 |
| 16x16, ITER=4, AUGMENT=1 (default) | 128 | 31205 | 530 |

- Flop count = (M + N) * pointer width (independent of ITER/AUGMENT/fill).
- The residual fill is a serial chain over N sources: it adds ~0.8-1.0k cells
  at 8x8 and is the main reason the 16x16 depth is large.  At 16x16 the default
  ITER=4/AUGMENT=1 design maps to 31,205 cells and 530 gate levels, versus
  10,115 cells and 372 levels for ITER=1/AUGMENT=0.  This is the price of a
  one-cycle, provably maximal matching.  For a timing-critical design the fill
  chain can be pipelined (at the cost of latency) or the arbiter can run at a
  lower clock; `ITER=1, AUGMENT=0` is the smallest/fastest variant and is
  still maximal.

## 4b. Throughput / area sweet spot (long-run benchmark)

1500-cycle Bernoulli(0.5) benchmark (`tb/tb_perf.sv`), matching size as a
fraction of min(N,M):

| Config | Cells | Depth | Bern size |
|--------|-------|-------|-----------|
| 8x8, ITER=1, AUGMENT=0 | 2291 | 129 | 89% |
| 8x8, ITER=1, AUGMENT=1 | 3634 | 170 | 91% |
| 8x8, ITER=2, AUGMENT=1 | 4952 | 190 | 97% |
| 8x8, ITER=4, AUGMENT=1 | 7763 | 234 | 97% |
| 10x10, ITER=1, AUGMENT=0 | 3983 | 175 | 91% |
| 10x10, ITER=1, AUGMENT=1 | 6212 | 221 | 94% |
| 10x10, ITER=2, AUGMENT=1 | 8257 | 252 | 98% |
| 10x10, ITER=4, AUGMENT=1 | 11821 | 300 | 98% |

`ITER=2, AUGMENT=1` is the PPA sweet spot: it matches the ITER=4 throughput
(97% at 8x8, 98% at 10x10) while using 36% fewer cells and 44 fewer gate levels
at 8x8, and 30% fewer cells and 48 fewer gate levels at 10x10.  `ITER=1,
AUGMENT=1` is the cheapest configuration that still beats strict iSLIP
(91%/94% vs 89%/91%), and `ITER=1, AUGMENT=0` is the minimum-area option.
The RTL default stays `ITER=4, AUGMENT=1` for maximum throughput / largest
matching; select ITER=2 when area or delay matters more.

## 5. Cost of the hard maximality guarantee

Compared with the earlier non-maximal design (same RTL before the fill):

| Config | Before (no fill) | After (fill) | Cost |
|--------|------------------|--------------|------|
| 8x8, ITER=1, AUGMENT=0 | 1461 cells | 2291 cells | +57% |
| 8x8, ITER=4, AUGMENT=0 | 5663 cells | 6670 cells | +18% |
| 16x16, ITER=1, AUGMENT=0 | 6364 cells | 10115 cells | +59% |

The fill costs proportionally more when ITER is small (the iSLIP logic is
smaller) and when N is large (more serial stages).  In exchange, the output is
guaranteed maximal for every request matrix and every N/M - the property the
design is required to have - instead of being maximal only heuristically.

## 6. Applied optimizations

- Arithmetic find-first-one grant/accept core (smaller than thermometer PPE).
- Staggered pointer reset (`g_ptr[j]=j mod N`, `a_ptr[i]=i mod M`) so the first
  full-crossbar cycle is already a full matching.
- Pointers default to async reset (`PTR_RESET=1`); `PTR_RESET=0` drops the
  reset for a leaner design.
- Pointer update reuses the first-pass match index via two small one-hot-to-
  binary functions.
- Flat internal vectors inside the generate loops (synthesis-friendly).
- The fill only touches still-unmatched sources / still-free destinations and
  reuses the existing round-robin mask logic; it never duplicates the full
  iSLIP grant network.
- The swap is optional (`AUGMENT`): drop it for strict fairness and ~16% less
  area, keep it for maximum matching size.

## 7. Literature reference

Web research confirms: iSLIP achieves 100% throughput for uniform traffic and
is the standard crossbar scheduler; its arbiter core is a programmable
priority encoder.  Multi-iteration iSLIP improves matching quality, but a
fixed number of iterations is not guaranteed to produce a maximal matching for
every request pattern.  Maximal matching can be computed in NC (e.g. Luby's
randomized algorithm), but those constructions need multiple rounds and are
impractical for a single-cycle hardware arbiter; the serial residual fill is
the smallest known way to make the result provably maximal at these sizes.
Binary-tree round-robin arbiters (PRRA/IPRRA) are only preferable for very
large N (>=64).

## 8. Logic-depth metric (target <= 40 levels)

The user-visible metric is the longest combinational path in Yosys generic gate
levels (`ltp -noff`), including the request rotation, the matching array and the
output encoders.  Designs above 40 levels are flagged for optimization.

| Design | 8x8 | 10x10 | 9x11 | 11x9 | 16x16 |
|--------|-----|-------|------|------|-------|
| iSLIP + serial fill (old) | 129 (ITER=1) | 300 (ITER=4/AUG=1) | - | - | 372 (ITER=1) |
| Wavefront WFA (default) | **28** | **35** | **35** | **35** | 48 |
| Target | <=40 | <=40 | <=40 | <=40 | <=40 |

WFA synthesis detail (generic cells, async-reset DFF, `synth/synth.ys`):

| Config | cells | flops | levels |
|--------|-------|-------|--------|
| 8x8 | 1181 | 3 | 28 |
| 10x10 | 2062 | 4 | 35 |
| 9x11 | 2029 | 4 | 35 |
| 11x9 | 2029 | 4 | 35 |
| 16x16 | 5261 | 4 | 48 |

The WFA numbers are for the wrapper `rtl/fair_arbiter.v` + core `rtl/wfa_core.v`
(P = max(N,M) torus
diagonals, P stages, rotating start).  The current RTL also uses a log-depth
cyclic rotator for delta (instead of a runtime modulo + per-bit P-way mux) and
an N>M transpose wrapper, so 11x9 reuses the 9x11 core; the N>M transpose is pure
wiring and saves both rotation rows and output-encoder logic.  `8x8`, `10x10`, `9x11` and `11x9` meet the target; `16x16` is 8 levels over and is the
candidate for a 2-cycle pipelined wavefront (P/2 = 8 stages per cycle, about 24
levels) or a 4x4 hierarchical split.  The cell itself is 2 gate levels
(`G = R & N & W`, token update = AND + NAND), so the depth is dominated by P.

WFA also removes the serial N-stage fill: the 10x10 area drops from 11,821 to
2,062 cells and the flop count from 80 to 4 (only the rotating start register).
The price is that WFA is maximal but not maximum-cardinality, and the exact
per-port RR order is relaxed (see `diagram/circuit/README.md`).
