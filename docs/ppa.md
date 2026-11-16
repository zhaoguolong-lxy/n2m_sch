# Fair Arbiter - Synthesis & PPA

Synthesizer: Yosys 0.66 (`synth -top fair_arbiter`), generic gate library
(no standard-cell liberty file, so "area" = count of gate-level cells after
ABC mapping).

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

## 2. ITER sweep (8x8, no-reset): throughput vs area

| ITER | Cells | First-cycle match (of 8) | Converge (cycles) |
|------|-------|--------------------------|-------------------|
| 1 | 1461 | 1 | 6 |
| 2 | 2668 | 2 | 5 |
| 3 | 4037 | 3 | 4 |
| 4 | 5663 | 4 | 3 |

Each extra iteration adds ~1.2k cells (8x8) and buys ~1 more first-cycle match
and ~1 faster convergence.  The matching-size improvement is linear in ITER:
reaching a perfect matching in a single cycle would need ITER = min(N,M), so
ITER = 2..3 is the usual sweet spot; the round-robin pointers desynchronize
over a few cycles anyway and then every ITER reaches a full matching.

## 3. Other configurations

| Config | Flops | Cells |
|--------|-------|-------|
| 8x8, ITER=1, no-reset | 48 | 1461 |
| 8x8, ITER=2, no-reset | 48 | 2668 |
| 8x8, ITER=2, async reset | 48 | 2671 |
| 8x4, ITER=2, no-reset | 28 | 1152 |
| 16x16, ITER=1, no-reset | 128 | 6364 |

- Flop count = (M + N) * pointer width (independent of ITER).
- No-reset pointers save a little area vs async reset (~3 cells here).
- Combinational area grows ~quadratically with N (16x16 ITER=1 = 6364 vs
  8x8 ITER=1 = 1461).

## 4. Applied optimizations

- Arithmetic find-first-one grant/accept core (smaller than thermometer PPE).
- Pointers default to async reset (`PTR_RESET=1`); `PTR_RESET=0` drops the
  reset for a leaner no-reset design (~3 cells saved).
- Pointer update reuses the first-pass match index via two small one-hot-to-
  binary functions (no duplicate encoders on the critical path).
- Flat internal vectors inside the generate loop (synthesis-friendly).

## 5. Literature reference

Web research confirms: iSLIP achieves 100% throughput for uniform traffic and
is the standard crossbar scheduler; its arbiter core is a programmable
priority encoder. Multi-iteration iSLIP improves matching quality; binary-tree
round-robin arbiters (PRRA/IPRRA) are only preferable for very large N (>=64).
