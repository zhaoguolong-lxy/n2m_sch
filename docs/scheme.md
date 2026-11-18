# Fair Arbiter (iSLIP Crossbar Scheduler) - Design & Scheme

> **Note:** the default RTL is the Wavefront (WFA/WWFA) implementation plus a
> parallel single-source/single-destination RR override in `rtl/fair_arbiter.v`;
> its circuit-level scheme is in
> [`diagram/circuit/README.md`](../diagram/circuit/README.md).  This document
> explains the earlier iSLIP + residual-fill reference architecture
> (`rtl/reference/fair_arbiter_islip.v`) and remains as the detailed comparison.

## 1. Problem

An N-to-M crossbar scheduler: N sources request M destinations every cycle.
The arbiter must, in a single cycle, produce an orthogonal (one-to-one)
matching, fairly, with round-robin fairness on both the source side and the
destination side.

## 2. Algorithm: iSLIP with ITER iterations

The design is the classic iSLIP matching algorithm (N. McKeown), parameterized
by the number of matching iterations ITER. One pass is:

```
request --> grant --> accept
```

- **grant**: each destination picks ONE requesting source, using a per-
  destination round-robin pointer (g_ptr). This gives destination-side
  fairness.
- **accept**: each source that received one or more grants picks ONE, using a
  per-source round-robin pointer (a_ptr). This gives source-side fairness and
  enforces orthogonality (a source takes at most one destination).

Orthogonality holds because:
- the grant stage produces at most one grant per destination (one-hot), and
- the accept stage produces at most one accept per source (one-hot).

A pointer advances only when its side actually matched (in the FIRST pass),
and to "one past" the matched partner. A partner that was granted but not
accepted stays at the head of the line for the next cycle (this is what makes
iSLIP fair and minimizes reordering).

**Iterations (ITER)**: a single pass can leave a source/destination idle even
when a match was possible (e.g. all destinations grant the same "hot" source,
which accepts only one). Each additional pass re-runs request->grant->accept
over the still-unmatched sources/destinations, producing a larger (closer to
maximal) matching. ITER = 1 is the area/delay-optimal variant; ITER = 2 is the
measured PPA sweet spot (same 97-98% random-traffic throughput as ITER = 4 at
8x8/10x10 for 30-36% fewer cells). Later-pass matches do not advance pointers
(standard iSLIP), preserving fairness.

## 2b. Guaranteed maximal matching (AUGMENT + residual fill)

The hard requirement is stronger than "high throughput": a cycle must never
leave a requested pair unserved when BOTH its endpoints are idle. In graph
terms the output matching must be **maximal**:

```
error  <=>  exists (i,j): req[i][j]=1
                        and source i has no grant
                        and dest   j has no grant
```

Finite iSLIP is not guaranteed to be maximal for every request pattern (and
the optional swap can occasionally remove a match without completing its
replacement). The design therefore has two post-processing stages, both purely
combinational and inside the same cycle:

1. **AUGMENT (swap, AUGMENT=1)** - improves the matching SIZE. An unmatched
   source `i` borrows a matched destination `j` whose source `k` is
   rematchable; `k` moves to an alternative free destination `l`. This is a
   length-3 augmenting path implemented as two lowest-index matchings. It is a
   pure bonus: it never decreases the size, but it is NOT what guarantees
   maximality (a simultaneous swap can leave a moved source without its
   alternative).

2. **Residual fill (always on)** - guarantees maximality for every N and M.
   It only ADDS matches, never moves or drops one. Adding a match cannot create
   a new wasted pair (a wasted pair needs both endpoints idle, and adding an
   edge only removes endpoints from the idle sets). The fill resolves the
   residual graph (still-unmatched sources x still-free destinations):

```
free = destinations not matched by iSLIP + swap
for i = 0 .. N-1:                       // fixed source order
    if source i is unmatched:
        pick = a requested destination in `free` (a_ptr preference)
        match(i, pick)
        free = free \ {pick}
```

**Maximality proof.** Suppose a requested pair `(i,j)` remains with source `i`
unmatched and destination `j` free after the fill. The free set only shrinks,
so `j` was still free when source `i` was processed. Source `i` would then have
taken some destination and could not remain unmatched - contradiction.
Therefore no such pair exists, for ANY request pattern and ANY N/M.

Because the fill only adds edges, orthogonality is preserved and the match
size never decreases. It also repairs the rare incomplete swap. The fill uses
the source's `a_ptr` for destination preference, so a source served only by the
fill still rotates over its destinations.

**Tradeoff.** `AUGMENT=1` uses fixed lowest-index priority inside the swap to
maximize size. That relaxes round-robin fairness: under a fixed request matrix
one pair can be repeatedly displaced, which is why the starvation test (S16)
runs only for `AUGMENT=0`. Set `AUGMENT=0` for strict iSLIP fairness (the fill
still guarantees maximality, at ~88-94% of min(N,M) average size instead of
~96-99.5%). See `docs/perf.md` for measurements.

## 3. Block diagram

```
                        i_src_dest_req[N][M]          i_src_bp[N]  i_dest_bp[M]
                                  |                        |            |
                                  v                        v            v
                          +--------------------------------------------+
                          |            effective request gate          |
                          |  eff_req[n][m] = req & ~src_bp & ~dest_bp   |
                          |                 & rst_n                     |
                          +--------------------------------------------+
                                  |
                                  v
      +-------------------------------------------------------------+
      |  GRANT stage (destination side, M arbiters)                 |
      |  for each dest j: pick one source among col_req[j]           |
      |    round-robin pointer g_ptr[j] (CLOG2N bits)                |
      |  output: grant_onehot[j][i]  (one-hot over N sources)        |
      +-------------------------------------------------------------+
                                  |
                                  v
      +-------------------------------------------------------------+
      |  ACCEPT stage (source side, N arbiters)                      |
      |  for each source i: pick one dest among row_grant[i]         |
      |    round-robin pointer a_ptr[i] (CLOG2M bits)                |
      |  output: accept_onehot[i][j]  (one-hot over M dests)         |
      +-------------------------------------------------------------+
                                  |
                                  v
      +-------------------------------------------------------------+
      |  AUGMENT (AUGMENT=1, optional): length-3 swap                |
      |  unmatched i takes j from rematchable k, k moves to free l   |
      |  improves SIZE; may leave an incomplete move                 |
      +-------------------------------------------------------------+
                                  |
                                  v
      +-------------------------------------------------------------+
      |  RESIDUAL FILL (always on): serial dictatorship              |
      |  unmatched source i takes a still-free requested dest        |
      |  only ADDS edges -> GUARANTEED maximal matching              |
      |  (no request with both source and dest idle can survive)     |
      +-------------------------------------------------------------+
                                  |
                 +----------------+----------------+
                 |                                 |
                 v                                 v
       source outputs                       destination outputs
       o_grant_rand_vld[n][m]               o_grant_dest_vld[m]
       o_grant_src_vld[n]                   o_grant_dest_ptr[m]
       o_grant_src_ptr[n]
                                  |
                                  v
      +-------------------------------------------------------------+
      |  POINTER UPDATE (registered, posedge clk)                   |
      |  g_ptr[j] <- g_ptr[j] + 1  when dest j matched (wrap at N-1) |
      |  a_ptr[i] <- a_ptr[i] + 1  when src  i matched (wrap at M-1) |
      +-------------------------------------------------------------+
```

## 4. Round-robin selection hardware (per arbiter)

The round-robin grant for a request vector `req[W-1:0]` and pointer `ptr`
(highest-priority index) is built from pure combinational hardware:

1. **Priority mask**: `mask_hi[k] = (k >= ptr)` -- bit k has priority if its
   index is at or above the pointer.
2. **Split requests**: `req_hi = req & mask_hi` (high half) and
   `req_lo = req & ~mask_hi` (low half).
3. **Find-first-one**: `grant = (|req_hi) ? (req_hi & ~(req_hi-1)) :
   (req_lo & ~(req_lo-1))` -- the arithmetic `x & ~(x-1)` isolates the lowest
   set bit, i.e. the highest-priority request in the chosen half.

This produces exactly one hot bit (or zero), which is what guarantees
orthogonality. The arithmetic find-first-one is smaller than a thermometer
priority encoder at these sizes (see docs/ppa.md).

## 5. Outputs and binary encoding

- `o_grant_rand_vld` is the FINAL matching: the union of all iSLIP passes, the
  optional swap, and the residual fill. The stages are disjoint by
  construction, so the union is exactly one grant per matched source/dest.
- `o_grant_src_vld[i]` = OR of the final match row i.
- `o_grant_src_ptr[i]` = binary index of the granted destination, computed as
  `ptr[i][b] = OR_j (match[i][j] & bit_b(j))` -- a one-hot-to-binary
  thermometer encoder.
- `o_grant_dest_vld[j]` / `o_grant_dest_ptr[j]` are the same, over sources.

## 6. Timing (zero latency)

All grant/accept/swap/fill logic is combinational; only the two pointer arrays
are registered. Therefore a request presented in cycle T produces its grant in
cycle T (the outputs are combinational from `req`, backpressure and the
registered pointers). The pointers update at `posedge clk`.

The residual fill is a serial chain over the N sources. It is the price of the
hard maximality guarantee: worst-case depth is O(N) priority selections
(the iSLIP passes themselves are O(ITER) and the swap is O(1) stages). For a
timing-critical implementation the chain can be pipelined at the cost of
latency; the interface here is deliberately zero-latency, so the entire
matching is computed in one cycle.

## 7. Backpressure and reset

- `i_src_bp[n]` gates out all requests from source n (combinational).
- `i_dest_bp[m]` gates out all requests toward destination m.
- `rst_n` (active-low, async) gates the effective requests to zero while
  asserted, so all outputs are 0 during reset with no X propagation even when
  pointers are uninitialized.
- The round-robin pointers default to async reset (`PTR_RESET = 1`) for an
  X-free simulation. They reset to a staggered diagonal (`g_ptr[j] = j mod N`,
  `a_ptr[i] = i mod M`) so the first cycle of full-crossbar traffic is already
  a maximal matching (no iSLIP desynchronization ramp-up). Fairness is
  invariant to the initial value, so setting `PTR_RESET = 0` drops the reset
  for a leaner, no-reset design.

## 8. Coding style compliance

- One `always` block assigns exactly one pointer slice (generate per element).
- Pointers default to async reset (staggered); `PTR_RESET = 0` for no-reset.
- ASCII only.
- Synthesizable RTL; only two small one-hot-to-binary functions, kept on the
  pointer-update path. Internal request/grant/accept matrices use flat 1-D
  vectors (synthesis-friendly inside the generate loop).
- Orthogonality is verified in the testbench rather than with in-RTL
  assertions (which are non-synthesizable).
