# Fair Arbiter - Synthesis & PPA

> **Default RTL is now the replicate/bank Wavefront implementation** in
> `rtl/fair_arbiter.v` (section 8).  It runs P fixed-delta WFA cores in
> parallel and selects one with a registered one-hot bank select; there is no
> runtime input/output barrel rotator.  Sections 1-7 describe the earlier
> iSLIP + residual-fill reference (`rtl/reference/fair_arbiter_islip.v`) and are
> kept for comparison.  The old rotating WFA top is kept as
> `rtl/reference/fair_arbiter_rot.v`.

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

## One-layer DPA reference (not a full DPA)

A complete DPA scans the P diagonals in priority order, just like the
wavefront, and is maximal; in fact the wavefront arbiter *is* the temporal
realisation of the full DPA.  `rtl/reference/fair_arbiter_dpa.v` deliberately
implements only the **first** diagonal layer: a cell is granted when it is
both the row's first request from `a_ptr[i]` and the column's first request
from `g_ptr[j]`.  That layer is shallow (10x10: 2726 cells / 21 levels) and
gives strict single-source / single-destination RR for free (42/42), but it
is not maximal: 630/773 non-maximal cycles at 10x10, only 2.20/10 grants per
cycle (22%), 31k wasted pairs.  Continuing the scan on the residual
diagonals is exactly the wavefront, which costs the usual P stages; a
spatially unrolled "loop-free" version was measured earlier at 77 levels.

The classic global-delta DPA (priority `(j-i-delta) mod P`) is the same
diagonal-priority family as the wavefront: full scan gives the same maximal
matching family, and the global delta still does not provide strict per-port
RR (see the WFA discussion).

One-layer reference PPA: 1553/20 (8x8), 2726/21 (10x10), 2688/22 (9x11),
2707/22 (11x9) cells/levels.

The strict 42/42 RR result of this one-layer module comes from its per-port
`a_ptr`/`g_ptr`, **not** from the diagonal priority.  The classic DPA of
Hurt et al. rotates a global diagonal priority and exhibits the same
staircase sequence as the WFA for a single source
(`0,2,2,5,5,5,0,...`), so it is not strict per-port RR.  See
`docs/literature.md` section 2.3 for the derivation and citations.

## 8. Logic-depth metric (target <= 40 levels)

The user-visible metric is the longest combinational path in Yosys generic gate
levels (`ltp -noff`), including the request rotation, the matching array and the
output encoders.  Designs above 35 levels are flagged for optimization.

| Design | 8x8 | 10x10 | 9x11 | 11x9 | 16x16 |
|--------|-----|-------|------|------|-------|
| iSLIP + serial fill (old) | 129 (ITER=1) | 300 (ITER=4/AUG=1) | - | - | 372 (ITER=1) |
| **Bank WFA + override + wavefront+, generic (default)** | **26** | **30** | - | - | out of scope |
| Single-core rotating WFA + override (legacy default) | 29 | 35 | 35 | 35 | out of target |
| 4-schedule rotating WFA + override (legacy option) | 31 | 36 | 36 | 38 | out of target |
| Fair variant: iSLIP first + WFA fill | 60 | 74 | 74 | 76 | out of target |
| Pure WFA (low-depth reference) | **28** | **35** | **35** | **35** | 48 |
| Target | <=35 | <=35 | <=35 | <=35 | out of scope |

WFA synthesis detail (generic cells, async-reset DFF, `synth/run_synth.sh`;
each shape runs in a fresh Yosys process):

Default bank + single-side RR override + wavefront+ + AOI21 form:

| Config | cells | levels | SKY130HD cells / area / ABC delay |
|--------|-------|--------|-----------------------------------|
| 8x8 | 6386 | 26 | 3424 / 20453.37 um^2 / 3634.04 ps |
| 10x10 | 12661 | 30 | 7108 / 39794.41 um^2 / 3876.72 ps |

These are generic Yosys levels; generic Yosys has no AOI21 cell, so the
AOI21 form still maps to gates.  With the real AOI21 library the wavefront
is one level per stage, so the core depth estimate is lower; the local
SKY130HD ABC delay above is the library-level validation.  For reference,
the legacy single-core rotating default was 8x8 3286/29 (SKY130 2341 cells /
15149.53 um^2 / 4420.88 ps) and 10x10 5366/35 (4586 cells / 31237.46 um^2 /
5192.11 ps).  The old four-schedule baseline (`NSCHED=4,
WAVEFRONT_PLUS=0, AOI_STYLE=0`) was 8x8 6655/31, 10x10 10711/35,
9x11 10426/36, 11x9 10692/38; it remains available in
`rtl/reference/fair_arbiter_rot.v` as the fairness-first option.

Multi-schedule WFA (legacy rotating reference): `rtl/reference/fair_arbiter_rot.v`
runs NSCHED wavefronts in parallel, each with a fixed coprime row permutation
`r -> (c*r) mod N` (pure wiring), and rotates the selected schedule every P
grants.  The default bank top is single-schedule and ignores `NSCHED`.
Fairness model with wavefront+ (10x10, 3000-cycle persistent patterns):

| Scheme | src Jain | dst Jain | 10x10 cells / levels |
|--------|----------|----------|----------------------|
| **Bank default** | **0.821-0.887** | **0.805-0.871** | **12661 / 30** |
| rotating NSCHED=2 (legacy) | 0.867-0.901 | 0.873-0.905 | 7395 / 35 |
| rotating NSCHED=4 (legacy) | 0.914-0.933 | 0.895-0.934 | 11255 / 36 |
| iSLIP first + fill (fair) | 0.866-0.895 | 0.912-0.934 | 5119 / 74 |

Saturated uniform traffic (K-regular graphs), `WAVEFRONT_PLUS=0` baseline:
every source asks K destinations and every destination is asked by K
sources, i.e. full load with perfectly balanced degrees.  `circ` is the
diagonal-aligned pattern (source i asks i..i+K-1), `rnd` is the same graph
with random row/column permutations.  src Jain (dst is identical for the
circulant):

| K | shape | WFAx1 | WFAx2 | WFAx4 | iSLIP first + fill |
|---|-------|-------|-------|-------|--------------------|
| 10 | circ / rnd | 1.000 | 1.000 | 1.000 | 1.000 |
| 8 | circ | 0.781 | 0.926 | 0.935 | 0.922 |
| 8 | rnd | 0.907 | 0.956 | 0.965 | 0.987 |
| 5 | circ | 0.500 | 0.635 | 0.812 | 0.960 |
| 5 | rnd | 0.833 | 0.897 | 0.928 | 0.980 |
| 3 | circ | 0.505 | 0.593 | 0.771 | 1.000 |
| 3 | rnd | 0.812 | 0.860 | 0.922 | 0.983 |

The full crossbar is trivial.  The weak spot is a narrow diagonal-aligned
pattern: with K=5 the rotating diagonal repeats the same destination for 6 of
the 10 phases, so the single-schedule baseline gives Jain 0.5 even though
every cycle is fully matched.  **Wavefront+ lifts the single schedule to
1.000**, so the default bank handles this pattern; the legacy 4-schedule
baseline lifts it to 0.81 (0.930 with wavefront+).  Per-port iSLIP reaches
0.96-1.00 but costs 74 levels.

`tb/tb_jain.sv` measures the same effect on the RTL: the default bank gives
random 0.821-0.887 src / 0.805-0.871 dst.  The earlier rotating model gave
NSCHED=4 0.914-0.933 / 0.895-0.934.  The K-regular mode gives the bank
1.000/1.000/1.000 and the legacy NS4 0.943/0.930/0.899 for K=8/5/3.
The legacy four-schedule option costs about 2x the cell area, 4x the matcher
switching activity, and the 4:1 output mux (about one level at 10x10).

### Legacy rotating single core (reference)

The table below is the pre-bank rotating top, kept in
`rtl/reference/fair_arbiter_rot.v` for the multi-schedule comparison.  The
default bank top is **12661 / 30** at 10x10 and ignores `NSCHED`.
With wavefront+ + AOI21:

| NSCHED | 10x10 generic cells/levels | SKY130HD cells / area / ABC delay | random src Jain | K=5 Jain |
|--------|----------------------------|-----------------------------------|-----------------|----------|
| **1** | **5366 / 35** | **4586 / 31237.46 um^2 / 5192.11 ps** | 0.821-0.887 | **1.000** |
| 2 | 7395 / 35 | - | 0.867-0.901 | 0.930 |
| 4 | 11255 / 36 | 10718 / 81874.77 um^2 / 5567.39 ps | 0.914-0.933 | 0.930 |

In the legacy top, NSCHED=1 was the depth/area choice and 4 was the
fairness-first option.  The bank default has the same single-schedule
fairness (src Jain ~0.82-0.89); narrow K-regular patterns are 1.000 because
wavefront+ handles them.  The bank was verified with the current 24/24
strict-RR and 11-configuration maximality tests; the historical rotating runs
used the older 42/42 and 18-configuration suites.

Pure WFA reference (no override): 8x8 1181/28, 10x10 2062/35,
9x11 2029/35, 11x9 2029/35, 16x16 5261/48.  The override runs in parallel
with the WFA, so the critical path is still the WFA path; the area increases
because the RR selectors and a_ptr/g_ptr are duplicated.

Fair variant (`rtl/fair_arbiter_fair.v`, iSLIP first pass + WFA fill):
8x8 3069/60, 10x10 5119/74, 9x11 4963/74, 11x9 5606/76.  It adds the
per-port iSLIP grant/accept layer before the WFA residual fill; multi-source
Jain averages improve at the cost of roughly 2x the fast variant's depth.

WTF-style prototype (`rtl/fair_arbiter_wtf.v`, comparison only): iSLIP
first pass + row-serial waterfall fill.  The default `SIMPLE_FILL=1`
makes the fill a fixed-order lowest-index greedy (the first pass already
owns the per-port RR, so the fill only has to guarantee maximality):
8x8 2007/58, 10x10 3387/70.  It passed the historical 42 strict RR checks and 18
maximality configurations (0 non-max cycles), K-regular Jain 1.000, random 10x10
0.876-0.920 src / 0.870-0.950 dst.  The original per-row `a_ptr` fill
(`SIMPLE_FILL=0`) is 8x8 3094/122, 10x10 6802/186; removing the per-row
pointer and rotating start halves both depth and area.

With `FILL=0` (first pass only) it is 1467/27 (8x8) and 2564/32 (10x10),
but 394/476 non-maximal cycles, so the fill is mandatory.  With
`FIRST_PASS=0, SIMPLE_FILL=1` (greedy base only) it is 552/31 and 880/38.
Adding the parallel per-port override to that greedy base gives
`rtl/fair_arbiter_greedy.v`: 8x8 1976/34, 10x10 3630/39, strict RR
(historical 42/42) and maximal, but multi-source Jain collapses to 0.125-0.333 (the fixed-order
greedy keeps serving the same low-index pairs).  This shows the iSLIP
first pass is what makes the WTF-style fair; the optimized 70-level
version is the smallest fair+maximal variant found.  It is still 2x the
30-level bank (or 35-level rotating WFA), so the bank remains the default.
This prototype does not reproduce the paper's cell-level waterfall; see
`docs/literature.md` section 4.2.

Reproduce the WTF prototype checks:

```sh
iverilog -g2012 -DWTF_DUT -s tb_fairness_top -o /tmp/wtf_fair.vvp \
    rtl/fair_arbiter_wtf.v tb/tb_fairness.sv && vvp /tmp/wtf_fair.vvp
iverilog -g2012 -DWTF_DUT -s tb_maximal_top -o /tmp/wtf_max.vvp \
    rtl/fair_arbiter_wtf.v tb/tb_maximal.sv && vvp /tmp/wtf_max.vvp
iverilog -g2012 -DWTF_DUT -s tb_jain_top -o /tmp/wtf_jain.vvp \
    rtl/fair_arbiter_wtf.v tb/tb_jain.sv && vvp /tmp/wtf_jain.vvp
```

Set `SIMPLE_FILL=0` (via `chparam` or the module parameter) to reproduce the
original per-row `a_ptr` fill (122/186 levels).  The greedy-base comparison
uses `FIRST_PASS=0, SIMPLE_FILL=1`; `rtl/fair_arbiter_greedy.v` is the
greedy base plus the parallel per-port override.

Wavefront+ (default `WAVEFRONT_PLUS=1`): the δ register advances to the
diagonal after the first scan stage that has any request, instead of always
δ+1.  The default implementation registers the **delta-independent**
diagonal-presence vector `diag_pres` and rotates the previous cycle's copy
by δ (`stage_present = rot_plus(diag_pres_r, delta)`).  Persistent patterns
see the same vector every cycle, so fairness is identical to the
combinational version; the current request only drives the short
OR-tree -> presence-register path, never the δ next-state path.
`WAVEFRONT_PLUS=2` uses the current `diag_pres` combinationally;
`WAVEFRONT_PLUS=0` restores δ+1.

RTL results (registered presence):

| K-regular, 10x10 | WFAx1 | WFAx1+ | WFAx4 | WFAx4+ |
|------------------|-------|--------|-------|--------|
| K=8 | 0.781 | **1.000** | 0.935 | 0.943 |
| K=5 | 0.500 | **1.000** | 0.812 | **0.930** |
| K=3 | 0.505 | **1.000** | 0.771 | **0.899** |

Random 10x10 also improves slightly at NSCHED=4 in the legacy rotating top
(0.890-0.929 -> 0.914-0.933 src).  The default bank and fair-variant
regressions pass; the bank itself is verified with 24/24 strict RR and 11
maximality configurations (0 non-max cycles).

**AOI21 form (default `AOI_STYLE=1`)**: the free-token update is written as

```
rf_next = ~((req & cf) | ~rf)     // AOI21: 2-AND + 1-OR + invert
cf_next = ~((req & rf) | ~cf)
```

which maps to a single AOI21 cell in the real library, i.e. **one level per
wavefront stage instead of two**.  The generic Yosys flow has no AOI21 cell;
the legacy rotating single core was 29/35 generic levels (8x8/10x10), and the
default bank is 26/30.  With the real AOI21 library each wavefront stage is
one level, so the core depth estimate is lower; the local SKY130HD ABC delay
is the library-level validation.  This meets the <=35 closure target with
margin.  Legacy rotating generic area/depth with the AOI form: 8x8 3286/29,
10x10 5366/35; the default bank is 6386/26 and 12661/30.  The optional
four-schedule legacy mode is 8x8 7064/31, 10x10 11255/36; `AOI_STYLE=0` keeps
the old AND/NAND form (four-schedule comparison: 8x8 6916/30, 10x10
11072/36).  The AOI form is logically identical; strict-RR and maximality
checks pass in the current bank and fair-variant regressions.

Delta-register path optimization: `wfa_core` enables the δ register with
`any_req = |req_pad` (an OR reduction of the effective request matrix) instead
of `any_grant = |match_accept`.  For a maximal WFA these are functionally
equivalent (any effective request produces at least one grant), but the old
enable path went input -> full P-stage wavefront -> OR -> δ, while the new path
is input -> AND -> OR reduction -> δ.  For 10x10 the δ D path drops from the
wavefront depth (~35 levels) to roughly 10 logic levels; the overall output
path is unchanged.

Output-side vld fusion (P >= 10): `o_grant_src_vld` / `o_grant_dest_vld` are
selected per path (single-source override / single-destination override / WFA)
after the path's own OR, so the `N*M`-bit `match_final` mux is no longer on the
valid path.  Three further tricks remove the remaining OR trees:

1. `src_ov` row i is `src_any[i] & s_pick_i`, and `s_pick_i` is one-hot
   (non-zero whenever the row has a request), so the row OR is just `src_any`.
   The same holds for `dst_ov` / `dst_any`; only the two cross-direction ORs
   need reduction trees.
2. `wfa_core` derives `o_src_vld` / `o_dest_vld` from the final free tokens
   (`~row_free_final`, `~rot_minus(col_free_final, delta)`), which are one gate
   after the last wavefront stage instead of a full OR tree.  The column token
   lives in the rotated space, so it reuses the same `rot_minus` structure.
3. Under `use_src` the WFA necessarily grants the only requesting source, and
   under `use_dst` it grants the only active destination, so `wfa_src_vld` /
   `wfa_dest_vld` already equal the override answer on those branches.  That
   turns the 3:1 output mux into a 2:1 mux.

At 10x10 this takes the source-valid path from 35 to 26 levels and the
destination-valid path from 34 to 30.  Fusion is gated off for N < 10 and
M < 10, so 8x8 keeps its plain path.  The pointer encoders are now the
critical path (35 levels: matcher + index OR), which is inherent to the
single-cycle design, so further reduction needs compound standard cells or a
2-cycle pipeline.

Redundancy removal (same behaviour, fast and fair):

- `src_ov` was `src_any[i] & s_pick_i[j]`; the row-any factor is redundant
  because the RR pick is zero whenever the row has no request (the same holds
  for `dst_ov`).  This drops 2 x N*M AND gates and one level from the
  override paths.
- `wfa_core` no longer exports `o_src_ptr` / `o_dest_ptr`: both wrappers
  encode the pointers from the final match, so the core encoders were dead
  logic that still loaded `match_accept` before ABC mapping.

### Output one-hot -> binary pointer audit

The 10x10 generic critical path ends at `o_grant_dest_ptr`, so the output
encoder is the last stage on the path.  Current implementation:

```
terms[j] = match_final[i*M+j] & bit_b(j)
ptr[b]   = |terms[j]
```

This is an independent OR tree per binary bit.  Depth is
`ceil(log2 N/M) + 1` (about 4 levels at 10x10), which is the asymptotic
minimum for producing a binary index from a one-hot vector.

Alternatives checked:

- **Pre-mux encoders + final pointer mux** (`PTR_FAST` experiment):
  WFA/override pointers are encoded before `match_final`, then selected.
  Measured 10x10 **5754 cells / 36 levels** vs the current **5383 / 35** in
  the same legacy run (the pre-bank table was 5366 / 35; the difference is ABC
  mapping noise).  The extra pointer mux and duplicated WFA encoders
  outweigh the removed match-mux level.  Rejected.
- **Priority encoder**: same `log` depth, more area than the independent
  OR trees (the one-hot input already selects one term per bit).  No win.
- **Thermometer/prefix encoder**: about `2*log` depth (prefix OR + XOR),
  worse.  No win.
- **One-hot pointer output**: would remove the encoder and about 4 levels,
  but changes the required binary interface.  Not applicable.

Stage audit at 10x10 (default single core, generic levels):

| Stage | Current | Depth | Alternative | Verdict |
|-------|---------|-------|-------------|---------|
| request mask | AND with backpressure | 2 | 3-input AND / merge into rotator | library-dependent; sharing the mask was slower |
| input rotation | log-stage 2:1 barrel | 4 | radix-4 barrel | library-dependent (4:1 cell); generic same |
| wavefront | P stages, AOI21 form | 20 generic / 10 AOI | replicate / MARX | library-dependent; Becker's replicate is fastest in ASIC |
| inverse rotation | log-stage 2:1 barrel | 4 | radix-4 barrel | library-dependent |
| match mux | 2:1 WFA/override | 1 | fused AOI mux | same |
| one-hot -> bin | OR tree | 4 | pre-mux / priority / thermometer | current best measured |
| vld | fused per path | ~1 | plain post-mux OR | current best |

The pointer encoder is therefore near-optimal for the required binary
interface; the remaining 4 levels are inherent.  The only real ways to
remove them are a wider-OR/priority-encoder cell in the target library or a
one-hot output contract.

### Token-ring WFA experiment (negative result)

`rtl/reference/wfa_core_tr.v` is a classic token-ring WFA core: the request
matrix is fixed, a one-hot row/column token selects the top-priority cell, and
north/west tokens propagate south/east.  It removes the data rotators, but the
naive top/left boundary injection is **not maximal** for an arbitrary priority
cell: the tokens can be consumed by cells above/left before reaching the
intended top-priority cell.  Measured on the maximality bench at 10x10:
**0.51/10 average grants (5.1%), 763/773 non-maximal cycles, 32k wasted
pairs**.  Fairness fails as well.

The correct classic WFA needs **wrap-around edges** (bottom/right back to
top/left) so the cells above/left are after the priority cell in the
wavefront.  Those wrap edges introduce combinational cycles; the current
design avoids them with the data rotation.  Alternatively, the start cell can
be moved by a full row/column data permutation, which is the same rotator
cost, or by replication/unrolling (area).  The classic single-cell WFA is
also `(2P-1)` stages, i.e. deeper than the `P`-stage torus even before the
rotator.

Conclusion: the rotator is **not algorithmically necessary**, but it is the
price of an **acyclic, arbitrary-start, P-stage** implementation.  Removing
it requires wrap-around (STA loop risk), replication/unrolling (area), or
accepting the deeper `2P-1` classic WFA.  The prototype is kept as a
negative-result reference; it is not integrated into `fair_arbiter`.

### Replicate/bank arbiter (default — depth-first)

`rtl/fair_arbiter.v` is a replicate/bank design: it instantiates **P fixed-
delta cores** (`rtl/wfa_core_fixed.v`) in parallel.  Each core's input/output
diagonal rotation is compile-time wiring (0 levels), so the 8-level runtime
input+output barrel rotator disappears.  A registered one-hot bank select
(`delta_oh`) drives a flat AND-OR mux.  `delta_oh` intentionally captures the
current `delta` one cycle late, so the select output path does not include the
wavefront+ next-state priority logic.

`delta` rotates once per granted cycle; the optional wavefront+ skip is still
computed on the registered next-state path.  For the square case the presence
vector uses `eff_req`, so backpressure is included.  `NSCHED` is accepted for
source compatibility but ignored: the bank is single-schedule.  The old
rotating `NSCHED=1..4` top is kept as `rtl/reference/fair_arbiter_rot.v`.

Verified: strict RR **24/24** (default fairness TB, 4 shapes), maximality
**11 shapes (max 10x10, 0 non-max)**,
K-regular Jain **1.000**, random 10x10 src **0.823** (same as NS1 rotating).

| Shape | rotating NS1 generic | bank generic | rotating SKY130 | bank SKY130 |
|-------|----------------------|--------------|-----------------|-------------|
| 8x8   | 3286 / 29 | **6386 / 26** | 2341c / 15149um2 / 4421ps | 3424c / 20453um2 / **3634ps** |
| 10x10 | 5366 / 35 | **12661 / 30** | 4586c / 31237um2 / 5192ps | 7108c / 39794um2 / **3877ps** |

Takeaways:

- **10x10 generic depth 35 -> 30** (5 levels of margin under the 35 limit);
  SKY130 delay **5192 -> 3877 ps (-25%)**.  8x8: 29 -> 26, -18% delay.
- Cost is **~1.9-2.4x generic cells / ~1.27-1.35x SKY130 area** (ABC shares
  logic across the P cores, so it is far below the naive P-times blowup).
  Depth-first, this is a good trade.
- The earlier "bank is generic-neutral (35 vs 35)" dismissal was measured on
  the OLD 2-gate wavefront without the AOI form / output fusion; with AOI21
  and the full top the bank clearly wins.  Generic hides the AOI benefit.
- 9x11 / 11x9 are not in the default max-10x10 regression; the earlier bank
  experiment measured 9x11 = 34 and 11x9 = 36 generic levels (the 11x9 value
  is a no-AOI proxy and is expected to close with the AOI21 library).

Reproduce: `bash synth/run_synth.sh` (generic, 8x8/10x10) and
`bash synth/run_synth.sh sky130` (cell-level).

Bank stage audit at 10x10 (generic levels):

| Stage | Depth |
|-------|-------|
| request mask | 2 |
| wavefront (P fixed-delta stages, AOI21 form) | 20 generic / 10 AOI |
| bank select (registered one-hot AND-OR) | ~2 |
| match mux (WFA/override) | 1 |
| one-hot -> binary pointer | 4 |
| vld | ~1 |

The remaining depth is the P-stage wavefront itself (20 generic / 10 AOI).
Cutting that further needs a parallel-prefix / carry-lookahead reformulation
of the coupled row/col token ripple; the 2D mutual dependency has no small
associative prefix operator, so that path is high-risk and was not pursued.
The bank is the practical depth win.

Net: the default bank top is **12661 cells / 30 levels at 10x10** and
**6386 / 26 at 8x8**; SKY130 is **7108c / 39794um2 / 3877ps** and
**3424c / 20453um2 / 3634ps**.  The optional fair variant is 5119 / 74.
The request-mask network is still built once in the wrapper (`eff_req`) and
once in each core: sharing it was measured, but it raises the `eff_req`
fanout and cost two levels at 8x8, so each side keeps its own local mask.

Generic-gate mapping is sensitive to statement order and ABC heuristics: the
same logic can move by +-1 level between builds, so treat single-level
differences as noise.

The bank numbers are for `rtl/fair_arbiter.v` + `rtl/wfa_core_fixed.v`
(P fixed cores; the N>M transpose and all diagonal rotations are pure wiring).
The old rotating WFA (`rtl/reference/fair_arbiter_rot.v` + `rtl/wfa_core.v`)
is kept for the NSCHED fairness comparison and for the pre-bank PPA history.
Cell/depth numbers come from `bash synth/run_synth.sh`, which runs each shape
in a fresh yosys process: repeating `design -reset` inside one process
perturbs ABC's mapping and moves the reported depth by +-1 level.  A parallel
single-source/single-destination RR override (a_ptr/g_ptr + one RR selector per
source and per destination) gives strict fairness for the single-side cases;
its area is included in the default table above.  The override is combinational
and parallel to the bank, so it does not add to the matcher depth.

The default bank meets the <=35 target: **8x8 = 26, 10x10 = 30 generic
levels**.  In the same earlier bank experiment 9x11/11x9 measured 34/36
generic levels (not part of the default max-10x10 regression; 11x9 is the
no-AOI proxy and is expected to close with the AOI21 library).  In generic
gates the wavefront cell is 2 levels (`G = R & N & W`, token update =
AND + NAND); with the real AOI21 library it is 1 level per stage.  General
mixed traffic is maximal but not maximum-cardinality; the exact mixed-traffic
per-port RR order is relaxed.  Single-source and single-destination sequences
are strict RR (24/24 default-bank and fair-variant tests).

Historical comparison at 10x10: pure WFA 2,062 / 35, rotating NSCHED=1
5,366 / 35, rotating NSCHED=4 11,255 / 36, old iSLIP+fill 11,821 / 300,
default bank 12,661 / 30.

## SKY130HD cell-level synthesis (local validation)

`bash synth/run_synth.sh sky130` (optionally
`SKY130_SHAPES=8x8 bash synth/run_synth.sh sky130`) runs
`synth -> flatten -> dfflibmap -> abc -liberty` against the SKY130HD
`tt_025C_1v80` Liberty.  The ABC constraint is `synth/sky130.constr`
(`sky130_fd_sc_hd__inv_2` driver, 10 fF load); ABC `stime` reports the
cell-level delay with wireload = none.  This is a local estimate, not
placed/routed STA; use OpenSTA/OpenROAD with the real library for signoff.

Default `NSCHED=1`:

| Shape | cells | AOI21 cells | area (um^2) | ABC delay (ps) |
|-------|-------|-------------|-------------|----------------|
| 8x8 | 2341 | 182 | 15149.53 | 4420.88 |
| 10x10 | 4586 | 328 | 31237.46 | 5192.11 |

Optional `NSCHED=4` (fairness-first):

| Shape | cells | AOI21 cells | area (um^2) | ABC delay (ps) |
|-------|-------|-------------|-------------|----------------|
| 8x8 | 5193 | 406 | 36722.72 | 4517.54 |
| 10x10 | 10718 | 778 | 81874.77 | 5567.39 |

AOI_STYLE comparison at 10x10, `NSCHED=4` (same flow):

| AOI_STYLE | cells | a21oi_1 | area (um^2) | delay (ps) |
|-----------|-------|---------|-------------|------------|
| 1 (AOI21 form) | 10718 | 778 | 81874.77 | 5567.39 |
| 0 (AND/NAND) | 10708 | 773 | 82293.93 | 5514.36 |

At the wrapper level the difference is within ABC mapping noise.  To isolate
the wavefront, synthesize the core alone at 10x10:

| Core 10x10 AOI_STYLE | cells | a21oi_1 | area (um^2) | delay (ps) |
|----------------------|-------|---------|-------------|------------|
| 1 (AOI21 form) | 2011 | 132 | 17698.22 | 4348.01 |
| 0 (AND/NAND) | 1969 | 113 | 17654.43 | 4438.99 |

The AOI21 form is **~2.1% faster at the core** (+0.25% area).  That is much
less than the ideal "20 -> 10 stage levels" arithmetic: ABC already
reassociates the old AND/NAND form into AOI21 for many stages, so both
mappings use AOI21 cells (113 vs 132).  For the full wrapper the critical
path also includes the input/output rotations, the output override/pointer
network, and (for NSCHED=4) the four parallel cores, not just a single
wavefront stage.  The
explicit AOI21 form is still worth keeping as a guarantee for a mapper that
does not reassociate the AND/NAND form, but do not expect it to single-
handedly solve the 35-level target.  For a true cell-level critical path,
run OpenSTA/OpenROAD on the mapped netlist.
