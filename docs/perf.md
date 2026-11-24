# Fair Arbiter - Scheduling Performance

Benchmark: `tb/tb_perf.sv` (Icarus Verilog). Per config: 100-cycle warmup plus
1500 cycles of full-crossbar and 1500 cycles of Bernoulli(0.5), PTR_RESET=1.
The default bank WFA rotates a start offset δ; the iSLIP reference uses
staggered pointer reset (g_ptr[j]=j mod N, a_ptr[i]=i mod M).  1500 samples per
traffic type give a standard error far below one percentage point of min(N,M).

Metrics:
- **first** = matches in the first cycle of full-crossbar traffic.
- **converge** = cycles until the matching reaches min(N,M).
- **full** = average matches/cycle under full-crossbar (100% load).
- **bern** = average matches/cycle under Bernoulli(0.5) random traffic.

## Bank WFA (default) results

1500 cycles per traffic type, PTR_RESET=1.  The bank select delta rotates on
each grant; full crossbar is 100% from the first cycle for every shape.
The regression scope is max 10x10.

| NxM | first | converge | full (of min) | bern (of min) |
|-----|-------|----------|---------------|---------------|
| 4x4 | 4 | 0 | 4.00/4 (100%) | 3.00/4 (75%) |
| 8x8 | 8 | 0 | 8.00/8 (100%) | 6.81/8 (85%) |
| 10x10 | 10 | 0 | 10.00/10 (100%) | 8.91/10 (89%) |
| 8x4 | 4 | 0 | 4.00/4 (100%) | 4.00/4 (100%) |
| 4x8 | 4 | 0 | 4.00/4 (100%) | 3.92/4 (98%) |
| 8x9 | 8 | 0 | 8.00/8 (100%) | 7.42/8 (93%) |

Fair variant (`rtl/fair_arbiter_fair.v`, iSLIP first + WFA fill): 10x10
first=10, full=100%, Bernoulli ~9.0/10 (90%); depth 74.  The default bank is
8.91/10 (89%) at depth 30; the legacy rotating 4-schedule option is 8.87/10
at depth 36 (within run-to-run noise).

The WFA is maximal, not maximum-cardinality: random square traffic is 85-89%
versus 97-98% for the old iSLIP+augment.  In exchange the 10x10 depth drops from
300 to 30 gate levels and the cell count is 12,661 for the default bank +
override (2,062 pure WFA; the legacy rotating single core is 5,366/35, its
four-schedule option 11,255/36).  The bank costs more area than the rotating
core but removes the runtime barrel rotator; depth-first, that is the chosen
trade.  The override is only selected in single-source/single-destination
traffic; the random/full crossbar numbers above are the WFA path and are
unchanged.

## Shared-queue drain (one multi-destination queue per source)

Application model: each source owns one shared queue holding packets for
several destinations.  Every cycle the source exposes a window of W entries
as `i_src_dest_req`; the arbiter grants at most one packet per source and per
destination.  `scripts/queue_drain.py` measures the drain time and source
fairness (10x10, 200 packets/source, 10 seeds):

| window W | scheme | makespan | pkt/cycle | finish Jain | finish spread |
|----------|--------|----------|-----------|-------------|---------------|
| 1 (FIFO head) | bank | 337 | 5.93 | 0.999 | 39 |
| 1 | legacy WFAx4 | 342 | 5.85 | 0.998 | 41 |
| 1 | fair | 339 | 5.91 | 0.999 | 40 |
| 1 | max-cardinality ref | 410 | 4.89 | 0.952 | 210 |
| 4 | bank | 258 | 7.74 | 0.999 | 26 |
| 4 | legacy WFAx4 | 260 | 7.68 | 0.999 | 29 |
| 4 | fair | 258 | 7.75 | 0.999 | 30 |
| 4 | max-cardinality ref | 323 | 6.21 | 0.972 | 123 |
| 10 (full buffer) | bank | 236 | 8.49 | 0.999 | 20 |
| 10 | legacy WFAx4 | 235 | 8.52 | 0.999 | 20 |
| 10 | fair | 232 | 8.62 | 0.999 | 19 |
| 10 | max-cardinality ref | 246 | 8.16 | 0.996 | 46 |

Takeaways:

- the request window dominates: exposing 4 entries instead of only the head
  cuts the drain time by 23% (337 -> 258 cycles), and a full buffer by 30%
  (235).  The arbiter cannot recover head-of-line blocking caused by a strict
  FIFO in the front end;
- with a maximal matcher every source that has a free requested destination is
  served every cycle, so the arbiter itself adds no wasted cycles;
- fairness also buys throughput: the cardinality-only reference is much worse
  at small windows (410 vs 337 cycles, finish spread 210 vs 39) because it
  starves some sources; the rotating bank WFA finishes all sources together;
- bank / legacy WFAx4 are within ~1% on makespan; the multi-schedule's gain is the
  persistent-traffic Jain index (0.914-0.933 vs 0.821-0.887), not the drain time;
- one grant per source per cycle is an interface property (`o_grant_src_vld`
  is one bit per source), so the per-source drain rate is capped at one
  packet/cycle by construction.

## iSLIP reference results (old default)

The table below is the earlier `ITER`/`AUGMENT` iSLIP + residual-fill design,
kept for comparison.  Its pointers reset to a staggered diagonal
(`g_ptr[j]=j mod N`, `a_ptr[i]=i mod M`).

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

## Maximal matching proof (WFA default; iSLIP fill reference)

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

Broad RTL run (`tb_maximal.sv`): 11 N/M configurations - 2x2, 4x4, 8x8,
8x8 ITER=1, 3x5, 5x7, 8x9, **10x10 (ITER=4 AUG=1, ITER=1 AUG=0, ITER=1
AUG=1)**, 5x3 - each driven for 773 cycles with full crossbar, staircases,
diagonals, hot source/dest, checkerboard, mod-3 blocks, sparse, corners,
two-row/two-col and random 5/10/25/50/75/90/99% traffic.  Result: **0
non-maximal cycles, 0 wasted pairs, 0 orthogonality violations, 0
output-consistency violations** (11 configurations x 773 cycles, max 10x10).

Long randomized soak (`tb/tb_soak.sv`), with 10% random source and destination
backpressure re-drawn every cycle and six rotating traffic modes:

| Test | Cycles | Shapes | non-max | orth/cons/impl/bp |
|------|--------|--------|---------|-------------------|
| 3-shape soak | 1500 each | 8x8, 9x9, 10x10 A0 | 0 | 0 / 0 / 0 / 0 |
| 10x10 soak | 20000 | 10x10 | 0 | 0 / 0 / 0 / 0 |

The 20,000-cycle 10x10 run alone covers 720,096 effective request instants and
144,396 grants, with maximality checked on the effective (post-backpressure)
request matrix every cycle.  All runs PASS.

Algorithm-level verification (`scripts/verify_maximal.py`):

- exhaustive over ALL request matrices for 2x2, 2x3, 3x2, 2x4, 4x2, 3x3,
  2x5, 3x4, 4x3, with and without the swap;
- all shapes 2..16 on 7 random densities;
- arbitrary (deliberately broken) base matchings repaired by the fill alone;
- deterministic adversarial patterns on all shapes.

Total: **94,475 WFA cases, 0 failures** (`scripts/verify_wfa.py`); the old
iSLIP model `scripts/verify_maximal.py` reports 67,118 cases, 0 failures.

Matching size (model, random p=0.5, 200 graphs, fraction of min(N,M)):

| Config | greedy + fill | swap + fill |
|--------|---------------|-------------|
| 8x8    | 87.1% | 95.9% |
| 10x10  | 90.0% | 97.8% |

The swap therefore buys ~6-9 percentage points of size at 8x8/10x10.  Its
fixed lowest-index priority relaxes round-robin fairness (a fixed matrix can
starve one pair), which is the accepted performance tradeoff; `AUGMENT=0`
keeps strict iSLIP fairness and is still maximal thanks to the fill.

## Key takeaways

1. **Full-crossbar is immediately maximal**: the WFA grants a full permutation
   in the first cycle for every shape (8x8 -> 8, 10x10 -> 10).

2. **WFA trades matching size for depth**: random square traffic is 81% (4x4),
   86% (8x8), 89% (10x10), and 96-100% for N!=M.  The old iSLIP+augment
   reference reaches 97-98% at 8x8/10x10, but costs 300 levels at 10x10 versus
   30 for the default bank WFA + override.

3. **Depth/area (10x10)**: 12661 cells / 30 levels for the default bank;
   the legacy rotating NSCHED=1 is 5366 / 35; NSCHED=4 is 11255 / 36; pure WFA
   is 2062/35, versus 11821 cells / 300 levels / 80 flops for iSLIP+fill.  The
   bank pays ~1.3x area to remove the runtime barrel rotator and cut depth by
   5 levels.  The override adds the per-source/per-destination RR selectors but
   runs in parallel; the WFA path stays critical.

4. **Fairness is count-fair, not strict-order**: δ rotates every diagonal, so
   every source/destination gets priority in turn; long-run counts are balanced
   and starvation does not occur.  The two port sides rotate in opposite
   directions, so a strict 0,1,2,... order on both sides is not preserved.
   This is the documented tradeoff for the depth reduction.

5. **All tested shapes are within the 35-level target**: the default bank maps
   to 8x8 = 26 and 10x10 = 30 generic levels.  The legacy rotating WFA was
   8x8 = 28, 10x10 = 35, 9x11 = 36, 11x9 = 35.  The 16x16 configuration is out
   of scope for this variant; if needed, a 2-cycle pipelined wavefront
   (P/2 = 8 stages per cycle) or a 4x4 hierarchical split is the documented
   direction.  See `docs/ppa.md` and `diagram/circuit/wfa_05_depth.png`.

The iSLIP reference table above is kept to show the 97-98% matching-size
reference point; it is no longer the default RTL.
