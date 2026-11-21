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
| Multi-schedule WFA + override (fast default) | **31** | **35** | **36** | **38** | out of target |
| Fair variant: iSLIP first + WFA fill | 60 | 74 | 74 | 76 | out of target |
| Pure WFA (low-depth reference) | **28** | **35** | **35** | **35** | 48 |
| Target | <=40 | <=40 | <=40 | <=40 | <=40 |

WFA synthesis detail (generic cells, async-reset DFF, `synth/run_synth.sh`;
each shape runs in a fresh yosys process):

Default WFA + single-side RR override:

| Config | cells | levels |
|--------|-------|--------|
| 8x8 | 6655 | 31 |
| 10x10 | 10711 | 35 |
| 9x11 | 10426 | 36 |
| 11x9 | 10692 | 38 |

Multi-schedule WFA (default): `rtl/fair_arbiter.v` runs NSCHED wavefronts in
parallel, each with a fixed coprime row permutation `r -> (c*r) mod N`
(pure wiring), and rotates the selected schedule every P grants.  `NSCHED` is
a parameter (default 4).  Fairness model (10x10, 3000-cycle persistent
patterns):

| Scheme | src Jain | dst Jain | 10x10 cells / levels |
|--------|----------|----------|----------------------|
| NSCHED=1 | 0.819-0.834 | 0.804-0.891 | 5274 / 35 |
| NSCHED=2 | 0.851-0.876 | 0.873-0.905 | 7155 / 36 |
| **NSCHED=4** | **0.890-0.929** | **0.918-0.952** | 10711 / 35 |
| iSLIP first + fill (fair) | 0.866-0.895 | 0.912-0.934 | 5119 / 74 |

`tb/tb_jain.sv` measures the same effect on the RTL (0.914-0.933 src /
0.895-0.934 dst for NSCHED=4).  The four wavefronts are independent and
combinational, so the matcher depth is unchanged at 10x10; the cost is about
2x the cell area and 4x the matcher switching activity.

Pure WFA reference (no override): 8x8 1181/28, 10x10 2062/35,
9x11 2029/35, 11x9 2029/35, 16x16 5261/48.  The override runs in parallel
with the WFA, so the critical path is still the WFA path; the area increases
because the RR selectors and a_ptr/g_ptr are duplicated.

Fair variant (`rtl/fair_arbiter_fair.v`, iSLIP first pass + WFA fill):
8x8 3069/60, 10x10 5119/74, 9x11 4963/74, 11x9 5606/76.  It adds the
per-port iSLIP grant/accept layer before the WFA residual fill; multi-source
Jain averages improve at the cost of roughly 2x the fast variant's depth.

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

Net: with a single schedule the 10x10 fast wrapper drops from 5488 to 5149
cells (-6%) at the same 35 levels, and the fair variant from 5474 to 5119
(-6.5%).  The multi-schedule default adds the extra wavefronts on top (10711
cells / 35 levels).  The request-mask network is still built once in the
wrapper (`eff_req`) and once in the core: sharing it was measured, but it
raises the `eff_req` fanout and cost two levels at 8x8, so each side keeps its
own local mask.

Generic-gate mapping is sensitive to statement order and ABC heuristics: the
same logic can move by +-1 level between builds, so treat single-level
differences as noise.

The WFA numbers are for the wrapper `rtl/fair_arbiter.v` + core `rtl/wfa_core.v`
(P = max(N,M) torus diagonals, P stages, rotating start).  The current RTL uses
a log-depth cyclic rotator for delta and an N>M transpose wrapper (pure wiring),
so 11x9 reuses the 9x11 core.  Cell/depth numbers come from
`bash synth/run_synth.sh [fast|fair]`, which runs each shape in a fresh yosys
process: repeating `design -reset` inside one process perturbs ABC's mapping
and moves the reported depth by +-1 level.  A parallel single-source/single-destination RR
override (a_ptr/g_ptr + one RR selector per source and per destination) gives
strict fairness for the single-side cases; its area is included in the default
table above.  The override is combinational and parallel to the WFA, so it
does not add to the matcher depth.

`8x8`, `10x10`, `9x11` and `11x9` meet the <=40 target; 16x16 is outside this
variant's target.  The cell itself is 2 gate levels (`G = R & N & W`, token
update = AND + NAND), so depth is dominated by P.  General mixed traffic is
maximal but not maximum-cardinality; the exact mixed-traffic per-port RR order
is relaxed.  Single-source and single-destination sequences are strict RR
(42/42 tests).

The pure WFA (without the override) at 10x10 is 2,062 cells / 35 levels; the
default fast variant is 5,149 / 35, and the old iSLIP+fill is 11,821 / 300.
