# Fair Arbiter - Test Points

## 1. Test point decomposition

The arbiter is tested along six orthogonal dimensions; every scenario also
re-checks two global invariants (orthogonality and grant-implies-request).

### Dimension A: configuration (N x M x ITER)
| ID | Config | Purpose |
|----|--------|---------|
| A1 | 8x8, ITER=2   | square, power-of-two baseline |
| A2 | 6x6, ITER=2   | square, non-power-of-two ($clog2 wrap) |
| A3 | 8x4, ITER=2   | N > M (more sources than destinations) |
| A4 | 4x8, ITER=2   | N < M (more destinations than sources) |
| A5 | 6x4, ITER=2   | N > M, both non-power-of-two |
| A6 | 4x6, ITER=2   | N < M, both non-power-of-two |
| A7 | 5x3, ITER=2   | N > M, odd small |
| A8 | 3x5, ITER=2   | N < M, odd small |
| A9 | 2x2, ITER=2   | minimal |
| A10 | 16x16, ITER=1 | large (scalability) |
| A11 | 8x8, ITER=2, PTR_RESET=0 | no-reset pointers |
| A12 | 8x8, ITER=1 | single-iteration variant (area-optimal) |
| A13 | 8x8, ITER=3 | three iterations (higher matching quality) |

### Dimension B: request pattern
| ID | Scenario | Checks |
|----|----------|--------|
| B1 | idle (no requests) | zero grants |
| B2 | single request (5 corner/edge/middle cells) | exact grant, ptr/vld |
| B3 | source RR, all destinations | order 0..M-1 + wrap (2M cycles) |
| B4 | source RR, subset (even dests) | skip + wrap over subset |
| B5 | dest RR, all sources | order 0..N-1 + wrap (2N cycles) |
| B6 | dest RR, subset (even srcs) | skip + wrap over subset |
| B7 | conflict-free permutation (src i -> dest i) | all min(N,M) granted |
| B8 | full crossbar | perfect matching of size min(N,M) |

### Dimension C: backpressure
| ID | Scenario | Checks |
|----|----------|--------|
| C1 | single source backpressured | that source never granted |
| C2 | all sources backpressured | zero grants |
| C3 | single destination backpressured | that dest never granted |
| C4 | all destinations backpressured | zero grants |
| C5 | source + destination backpressure together | both suppressed |
| C6 | dynamic backpressure toggle | suppressed only while asserted |

### Dimension D: timing / reset
| ID | Scenario | Checks |
|----|----------|--------|
| D1 | same-cycle result | grant appears in cycle T, not T+1 |
| D2 | async reset | outputs 0 during reset |
| D3 | no-reset pointers (PTR_RESET=0) | functional, orthogonal, fair |

### Dimension E: fairness / starvation / efficiency (temporal)
| ID | Scenario | Checks |
|----|----------|--------|
| E1 | long-run fairness (full crossbar, 500 cyc) | per-source / per-dest counts balanced |
| E2 | starvation freedom (persistent matrix, 4NM cyc) | every requested pair granted >= 1 |
| E3 | matching quality (S17) | first-cycle matching size + convergence |

### Dimension F: random stress
| ID | Scenario | Checks |
|----|----------|--------|
| F1 | random traffic + random backpressure (200 cyc) | invariants hold every cycle |

### Global invariants (checked in every applicable scenario)
| ID | Invariant |
|----|-----------|
| G1 | orthogonality: each source matched to <=1 dest, each dest to <=1 source |
| G2 | grant implies request and not backpressured |

## 2. Results

Simulator: Icarus Verilog 14.0 (`iverilog -g2012`). All 19 configurations
passed; total 247,485 checks, 0 errors.

| Config | Result | Checks |
|--------|--------|--------|
| cfg_2x2 | PASS | 3366 |
| cfg_5x3 | PASS | 6456 |
| cfg_3x5 | PASS | 6620 |
| cfg_6x4 | PASS | 7952 |
| cfg_4x6 | PASS | 7956 |
| cfg_8x4 | PASS | 9029 |
| cfg_4x8 | PASS | 9045 |
| cfg_6x6 | PASS | 10085 |
| cfg_8x8 (ITER=2) | PASS | 13462 |
| cfg_8x8_nrst (no-reset) | PASS | 13462 |
| cfg_8x8_i1 (ITER=1) | PASS | 13426 |
| cfg_8x8_i3 (ITER=3) | PASS | 13462 |
| cfg_8x9 | PASS | 14863 |
| cfg_7x11 | PASS | 14964 |
| cfg_9x9 | PASS | 15860 |
| cfg_9x11 | PASS | 17270 |
| cfg_11x9 | PASS | 17097 |
| cfg_15x15_i1 | PASS | 26218 |
| cfg_16x16_i1 | PASS | 26892 |
| **Total** | **ALL PASS** | **247485** |

The added 8x9 / 9x9 / 9x11 / 11x9 / 7x11 / 15x15 configs exercise the
`$clog2` width transitions just above/below power-of-two (8->9, 15->16) and
the pointer wrap at odd boundaries, which is where sizing bugs hide.

### Matching quality (S17) - staggered reset

| Config | First-cycle match | Converge to full (cycles) |
|--------|-------------------|---------------------------|
| 8x8 ITER=1 | 8 of 8 | 0 |
| 8x8 ITER=2 | 8 of 8 | 0 |
| 8x8 ITER=3 | 8 of 8 | 0 |

The staggered pointer reset (g_ptr[j]=j, a_ptr[i]=i) makes the first cycle of
full-crossbar traffic a maximal matching (no iSLIP desynchronization ramp-up).
ITER then only matters for random/bursty traffic throughput, not full-crossbar.

Command:
```
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

## 3. Notes

- The two round-robin directions are both exercised with *all* destinations /
  sources and with a *subset*, verifying skip + wrap behaviour.
- Non-power-of-two sizes (6, 5, 3, 7, 9, 11, 15) exercise the `$clog2` width
  and pointer wrap logic, including just above/below power-of-two boundaries.
- The no-reset configuration is verified by `$deposit`-ing the pointers to a
  known state after reset (simulating power-on), then running the same
  invariants; Icarus `$deposit` cannot target unpacked-array words, which is
  why the pointers are stored as flat vectors in the RTL.
- **AUGMENT tradeoff**: `AUGMENT=1` (swap) uses a fixed lowest-index priority
  to maximize matching size, which relaxes round-robin fairness.  The S16
  starvation test is therefore skipped for `AUGMENT=1` (it would starve a
  fixed-matrix pair).  Maximality is instead checked by `tb_maximal.sv`
  (req[i][j] && src and dst both idle -> error).

## 4. X-state (unknown) check

`tb/tb_x_check.sv` uses `$isunknown()` to verify reset/X behaviour:

| Case | Result |
|------|--------|
| During async reset (pointers X) | outputs clean 0, no X |
| After reset, PTR_RESET=1 | X-free |
| After reset, PTR_RESET=0 | X (expected: no-reset flop sim artifact) |
| After $deposit init, PTR_RESET=0 | X-free, then random traffic X-free |

The `& rst_n` gating in `eff_req` guarantees clean 0 outputs during reset even
when the no-reset pointers hold X.  The X seen after reset for `PTR_RESET=0`
is a simulation artifact of no-reset flops (real silicon has a deterministic
unknown value, not X, and round-robin fairness is invariant to it).  Use
`PTR_RESET=1` for a cleanly-reset (X-free) simulation, or `$deposit` the
pointers to model power-on in a no-reset flow.
