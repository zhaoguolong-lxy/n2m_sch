# Fair Arbiter - Scheduling Performance

Benchmark: `tb/tb_perf.sv` (Icarus Verilog). Per config: 100-cycle warmup plus
1500 cycles of full-crossbar and 1500 cycles of Bernoulli(0.5), PTR_RESET=1,
with STAGGERED pointer reset (g_ptr[j]=j mod N, a_ptr[i]=i mod M).  1500 samples
per traffic type give a standard error far below one percentage point of
min(N,M).

Metrics:
- **first** = matches in the first cycle of full-crossbar traffic.
- **converge** = cycles until the matching reaches min(N,M).
- **full** = average matches/cycle under full-crossbar (100% load).
- **bern** = average matches/cycle under Bernoulli(0.5) random traffic.

## Results

Long run: 1500 cycles per traffic type (after 100-cycle warmup).

| NxM | ITER | AUGMENT | first | converge | full (of min) | bern (of min) |
|-----|------|---------|-------|----------|---------------|---------------|
| 4x4 | 1 | 0 | 4 | 0 | 4.00/4 (100%) | 2.63/4 (66%) |
| 4x4 | 2 | 0 | 4 | 0 | 4.00/4 (100%) | 2.63/4 (66%) |
| 4x4 | 4 | 1 | 4 | 0 | 4.00/4 (100%) | 3.38/4 (84%) |
| 8x8 | 1 | 0 | 8 | 0 | 8.00/8 (100%) | 7.12/8 (89%) |
| 8x8 | 2 | 0 | 8 | 0 | 8.00/8 (100%) | 7.15/8 (89%) |
| 8x8 | 4 | 0 | 8 | 0 | 8.00/8 (100%) | 7.15/8 (89%) |
| 8x8 | 1 | 1 | 8 | 0 | 8.00/8 (100%) | 7.29/8 (91%) |
| 8x8 | 2 | 1 | 8 | 0 | 8.00/8 (100%) | 7.75/8 (97%) |
| 8x8 | 4 | 1 | 8 | 0 | 8.00/8 (100%) | 7.75/8 (97%) |
| 10x10 | 1 | 0 | 10 | 0 | 10.00/10 (100%) | 9.09/10 (91%) |
| 10x10 | 4 | 0 | 10 | 0 | 10.00/10 (100%) | 9.06/10 (91%) |
| 10x10 | 1 | 1 | 10 | 0 | 10.00/10 (100%) | 9.42/10 (94%) |
| 10x10 | 2 | 1 | 10 | 0 | 10.00/10 (100%) | 9.78/10 (98%) |
| 10x10 | 4 | 1 | 10 | 0 | 10.00/10 (100%) | 9.83/10 (98%) |
| 16x16 | 1 | 0 | 16 | 0 | 16.00/16 (100%) | 15.01/16 (94%) |
| 16x16 | 1 | 1 | 16 | 0 | 16.00/16 (100%) | 15.15/16 (95%) |
| 8x4 | 4 | 1 | 4 | 0 | 4.00/4 (100%) | 4.00/4 (100%) |
| 4x8 | 4 | 1 | 4 | 0 | 4.00/4 (100%) | 3.98/4 (100%) |
| 9x11 | 4 | 1 | 9 | 0 | 9.00/9 (100%) | 8.99/9 (100%) |
| 11x9 | 4 | 1 | 9 | 0 | 9.00/9 (100%) | 8.99/9 (100%) |

## Guaranteed maximal matching (AUGMENT + residual fill)

**Hard criterion (checked by `tb/tb_maximal.sv` and
`scripts/verify_maximal.py`)**: a cycle is an error if some `req[i][j]` has
BOTH source `i` and destination `j` idle.  The output matching must be
**maximal** every cycle, for every N/M, including 10x10.

A finite number of iSLIP iterations is not guaranteed to be maximal for every
request pattern, and the parallel swap can occasionally move a match without
completing the replacement.  The RTL therefore ends with a **residual fill**:
it only ADDS matches, taking still-unmatched sources in a fixed order and
giving each one a requested destination that is still free.  Adding an edge
cannot create a wasted pair, and no wasted pair can survive the fill (if
`(i,j)` survived, `j` was free when `i` was processed because the free set only
shrinks, so `i` would have taken something).  Hence the result is maximal for
every request matrix and every N/M.

Measured on random (Bernoulli 0.5) traffic with the RTL benchmark, 1500 cycles:

| Config | non-maximal cycles | ortho violations | size (of min) |
|--------|--------------------|------------------|---------------|
| 8x8 ITER=4 AUG=0 (greedy) | 0 | 0 | 89% |
| 8x8 ITER=2 AUG=1 (swap)   | 0 | 0 | 97% |
| 8x8 ITER=4 AUG=1 (swap)   | 0 | 0 | 97% |
| 10x10 ITER=4 AUG=1         | 0 | 0 | 98% |
| 16x16 ITER=1 AUG=1         | 0 | 0 | 95% |
| 9x11 ITER=4 AUG=1          | 0 | 0 | 100% |

Broad RTL run (`tb_maximal.sv`): 18 N/M shapes - 2x2, 4x4, 8x8, 8x8 ITER=1,
16x16, 3x5, 5x7, 8x9, 9x11, **10x10 (ITER=4, ITER=1 AUG=0, ITER=1 AUG=1)**,
5x3, 11x9, 12x7, 13x13, 15x15, 7x11 - each driven for 773 cycles with full
crossbar, staircases, diagonals, hot source/dest, checkerboard, mod-3 blocks,
sparse, corners, two-row/two-col and random 5/10/25/50/75/90/99% traffic.
Result: **0 non-maximal cycles, 0 wasted pairs, 0 orthogonality violations, 0
output-consistency violations** (18 shapes x 773 cycles).

Long randomized soak (`tb/tb_soak.sv`), with 10% random source and destination
backpressure re-drawn every cycle and six rotating traffic modes:

| Test | Cycles | Shapes | non-max | orth/cons/impl/bp |
|------|--------|--------|---------|-------------------|
| 4-shape soak | 1500 each | 8x8, 9x11, 10x10 A0, 16x16 | 0 | 0 / 0 / 0 / 0 |
| 10x10 soak | 20000 | 10x10 ITER=4 AUG=1 | 0 | 0 / 0 / 0 / 0 |

The 20,000-cycle 10x10 run alone covers 720,096 effective request instants and
154,561 grants, with maximality checked on the effective (post-backpressure)
request matrix every cycle.  All runs PASS.

Algorithm-level verification (`scripts/verify_maximal.py`):

- exhaustive over ALL request matrices for 2x2, 2x3, 3x2, 2x4, 4x2, 3x3,
  2x5, 3x4, 4x3, with and without the swap;
- all shapes 2..16 on 7 random densities;
- arbitrary (deliberately broken) base matchings repaired by the fill alone;
- deterministic adversarial patterns on all shapes.

Total: **67,118 cases, 0 failures**.

Matching size (model, random p=0.5, 200 graphs, fraction of min(N,M)):

| Config | greedy + fill | swap + fill |
|--------|---------------|-------------|
| 8x8    | 87.1% | 95.9% |
| 10x10  | 90.0% | 97.8% |
| 16x16  | 94.1% | 99.5% |
| 9x11   | 96.8% | 99.9% |
| 11x9   | 96.1% | 99.8% |

The swap therefore buys ~6-9 percentage points of size at 8x8/10x10.  Its
fixed lowest-index priority relaxes round-robin fairness (a fixed matrix can
starve one pair), which is the accepted performance tradeoff; `AUGMENT=0`
keeps strict iSLIP fairness and is still maximal thanks to the fill.

## Key takeaways

1. **Full-crossbar is immediately maximal**: with the staggered pointer reset,
   the very first cycle dispatches min(N,M) matches (8 for 8x8, 16 for 16x16).
   No desynchronization ramp-up.  This is what "输出被占满" requires.

2. **ITER only matters for random (non-uniform) traffic**:
   - `first`/`converge`/`full` are already optimal for every ITER.
   - With `AUGMENT=0`, two passes are enough to saturate: 8x8 stays at 89%
     for ITER=1/2/4; 10x10 stays at 91% for ITER=1/4.
   - With `AUGMENT=1`, ITER still helps: 8x8 91% (I1) -> 97% (I2/I4), 10x10
     94% (I1) -> 98% (I2/I4), 4x4 66% -> 84% (AUG only).  ITER=4 is within
     measurement noise of ITER=2 at 8x8 and 10x10.

3. **AUGMENT buys 1-18 points of random-traffic matching size**:
   4x4 66% -> 84%, 8x8 89% -> 97%, 10x10 91% -> 98%, 16x16 94% -> 95%.
   For N!=M the aspect ratio already gives ~100%, so AUGMENT changes little
   there (8x4/4x8/9x11/11x9 are all ~100%).

4. **Aspect ratio**:
   - N > M (8x4, dest-limited): 100% even without extra work.
   - N < M (4x8, source-limited): 100% with the swap.
   - Square 16x16 keeps 94-95% because a 16-way conflict is harder to resolve
     in one cycle, but the residual fill still guarantees maximality.

5. **Recommendation**:
   - **Maximum throughput (default)**: `ITER=4, AUGMENT=1` - maximal every
     cycle, 97-98% matching size at 8x8/10x10, 95% at 16x16.
   - **PPA sweet spot**: `ITER=2, AUGMENT=1` - same 97-98% at 8x8/10x10 for
     ~35% fewer cells than ITER=4 (see `docs/ppa.md`).
   - **Minimum area / strict fairness**: `ITER=1, AUGMENT=0` - still maximal
     every cycle thanks to the residual fill, 89-91% square sizes and ~100%
     for N!=M.
   - ITER=1 is enough for uniform/high-load traffic (full crossbar is 100% on
     the first cycle); extra iterations and the swap mainly help bursty /
     random traffic.
