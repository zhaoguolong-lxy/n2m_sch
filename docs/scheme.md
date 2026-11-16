# Fair Arbiter (iSLIP Crossbar Scheduler) - Design & Scheme

This document explains the architecture and hardware of `rtl/fair_arbiter.v`.

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
maximal) matching. ITER = 1 is the area/delay-optimal variant; ITER = 2..3 is
the usual sweet spot. Later-pass matches do not advance pointers (standard
iSLIP), preserving fairness.

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

- `o_grant_rand_vld` is the accept one-hot matrix directly.
- `o_grant_src_vld[i]` = OR of accept row i.
- `o_grant_src_ptr[i]` = binary index of the accepted destination, computed as
  `ptr[i][b] = OR_j (accept[i][j] & bit_b(j))` -- a one-hot-to-binary
  thermometer encoder.
- `o_grant_dest_vld[j]` / `o_grant_dest_ptr[j]` are the same, over sources.

## 6. Timing (zero latency)

All grant/accept logic is combinational; only the two pointer arrays are
registered. Therefore a request presented in cycle T produces its grant in
cycle T (the outputs are combinational from `req`, backpressure and the
registered pointers). The pointers update at `posedge clk`.

## 7. Backpressure and reset

- `i_src_bp[n]` gates out all requests from source n (combinational).
- `i_dest_bp[m]` gates out all requests toward destination m.
- `rst_n` (active-low, async) gates the effective requests to zero while
  asserted, so all outputs are 0 during reset with no X propagation even when
  pointers are uninitialized.
- The round-robin pointers default to async reset (`PTR_RESET = 1`) for an
  X-free simulation. Fairness is invariant to their initial value, so setting
  `PTR_RESET = 0` drops the reset for a leaner, no-reset design.

## 8. Coding style compliance

- One `always` block assigns exactly one pointer slice (generate per element).
- No-reset registers preferred (pointers default no-reset).
- ASCII only.
- Synthesizable RTL; only two small one-hot-to-binary functions, kept on the
  pointer-update path. Internal request/grant/accept matrices use flat 1-D
  vectors (synthesis-friendly inside the generate loop).
- Orthogonality is verified in the testbench rather than with in-RTL
  assertions (which are non-synthesizable).
