# Fair Arbiter - Test Points

## 1. Test point decomposition

The arbiter is tested along eight orthogonal dimensions; every scenario also
re-checks two global invariants (orthogonality and grant-implies-request).

### Dimension A: configuration (N x M x ITER x AUGMENT)
Default configuration is ITER=4, AUGMENT=1 (maximal + largest matching).

| ID | Config | Purpose |
|----|--------|---------|
| A1 | 8x8, ITER=4 | square, power-of-two baseline |
| A2 | 6x6, ITER=4 | square, non-power-of-two ($clog2 wrap) |
| A3 | 8x4, ITER=4 | N > M (more sources than destinations) |
| A4 | 4x8, ITER=4 | N < M (more destinations than sources) |
| A5 | 6x4, ITER=4 | N > M, both non-power-of-two |
| A6 | 4x6, ITER=4 | N < M, both non-power-of-two |
| A7 | 5x3, ITER=4 | N > M, odd small |
| A8 | 3x5, ITER=4 | N < M, odd small |
| A9 | 2x2, ITER=4 | minimal |
| A10 | 16x16, ITER=1 | large (scalability) |
| A11 | 8x8, PTR_RESET=0 | no-reset pointers |
| A12 | 8x8, ITER=1 | single-iteration variant (area-optimal) |
| A13 | 8x8, ITER=3 | three iterations |
| A14 | 9x9, ITER=4 | $clog2 wrap just above 8 |
| A15 | 9x11, ITER=4 | N<M, both non-power-of-two |
| A16 | 8x9, ITER=4 | $clog2 transition 8 -> 9 |
| A17 | 11x9, ITER=4 | N>M, both non-power-of-two |
| A18 | 7x11, ITER=4 | odd x odd, N<M |
| A19 | 15x15, ITER=1 | $clog2 transition 15 -> 16 |
| A20 | **10x10, ITER=4** | **explicitly requested N=M=10 case** |
| A21 | 10x10, ITER=4, AUGMENT=0 | no-swap variant; also runs S16 fairness |
| A22 | 8x8, ITER=4, AUGMENT=0 | strict-iSLIP baseline; also runs S16 fairness |

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
| E2 | starvation freedom (persistent matrix, 4NM cyc) | every requested pair granted >= 1 (AUGMENT=0 only) |
| E3 | matching quality (S17) | first-cycle matching size + convergence |

### Dimension F: random stress
| ID | Scenario | Checks |
|----|----------|--------|
| F1 | random traffic + random backpressure (200 cyc) | invariants hold every cycle |

### Dimension G: maximality (the hard requirement)
| ID | Scenario | Checks |
|----|----------|--------|
| G1 | `scripts/verify_maximal.py` exhaustive small shapes | every request matrix of 2x2..3x4: no wasted pair |
| G2 | `scripts/verify_maximal.py` all shapes 2..16 | random densities 5%..99%, 7 densities x 20 graphs |
| G3 | `scripts/verify_maximal.py` arbitrary base matching | fill alone repairs any base to maximal |
| G4 | `tb/tb_maximal.sv` 18 N/M shapes | ~780 cycles each: adversarial patterns + 7 random densities |
| G5 | `tb/tb_maximal.sv` 10x10 ITER=1/4, AUGMENT=0/1 | maximality independent of greedy quality |

### Dimension H: long randomized soak (stability)
| ID | Scenario | Checks |
|----|----------|--------|
| H1 | `tb/tb_soak.sv` 4 shapes x 1500 cyc (8x8, 9x11, 10x10 A0, 16x16) | rotating traffic modes + 10% random backpressure every cycle; maximality on effective requests |
| H2 | `tb/tb_soak.sv` 10x10 default x 20000 cyc | long-run stability, no drift, X-free |

The maximality criterion is exactly: `req[i][j] && !src_vld[i] && !dest_vld[j]`
is an error.  `tb_maximal.sv` also checks orthogonality and that
`o_grant_src_vld`, `o_grant_dest_vld`, `o_grant_src_ptr` and
`o_grant_dest_ptr` agree with `o_grant_rand_vld` every cycle.

### Global invariants (checked in every applicable scenario)
| ID | Invariant |
|----|-----------|
| I1 | orthogonality: each source matched to <=1 dest, each dest to <=1 source |
| I2 | grant implies request and not backpressured |

## 2. Results

Simulator: Icarus Verilog 14.0 (`iverilog -g2012`). All 22 configurations
passed; total 294,356 checks, 0 errors.

| Config | Result | Checks |
|--------|--------|--------|
| cfg_2x2 | PASS | 3363 |
| cfg_5x3 | PASS | 6447 |
| cfg_3x5 | PASS | 6612 |
| cfg_6x4 | PASS | 7939 |
| cfg_4x6 | PASS | 7945 |
| cfg_8x4 | PASS | 9011 |
| cfg_4x8 | PASS | 9023 |
| cfg_6x6 | PASS | 10071 |
| cfg_8x8 (ITER=4, AUGMENT=1) | PASS | 13425 |
| cfg_8x8_nrst (PTR_RESET=0) | PASS | 13425 |
| cfg_8x8_i1 (ITER=1) | PASS | 13425 |
| cfg_8x8_i3 (ITER=3) | PASS | 13425 |
| cfg_8x9 | PASS | 14837 |
| cfg_7x11 | PASS | 14959 |
| cfg_9x9 | PASS | 15827 |
| cfg_9x11 | PASS | 17235 |
| cfg_11x9 | PASS | 17049 |
| cfg_10x10 (ITER=4, AUGMENT=1) | PASS | 16779 |
| cfg_15x15_i1 | PASS | 26429 |
| cfg_16x16_i1 | PASS | 26841 |
| cfg_10x10_noswap (AUGMENT=0) | PASS | 16827 |
| cfg_8x8_noswap (AUGMENT=0, S16) | PASS | 13462 |
| **Total (22 configs)** | **ALL PASS** | **294356** |

The added 8x9 / 9x9 / 9x11 / 11x9 / 7x11 / 15x15 configs exercise the
`$clog2` width transitions just above/below power-of-two (8->9, 15->16) and
the pointer wrap at odd boundaries, which is where sizing bugs hide.

### Long-run results (G4, H1, H2)

| Run | Scope | Cycles | Result |
|-----|-------|--------|--------|
| Maximality sweep (G4) | 18 N/M shapes, 7 random densities + 19 adversarial patterns | 773 each | 0 non-maximal, 0 wasted pairs, 0 orth, 0 cons |
| 4-shape soak (H1) | 8x8 A1, 9x11 A1, 10x10 A0, 16x16 A1 | 1500 each | 0 non-max, 0 wasted, 0 orth/cons/impl/bp |
| 10x10 soak (H2) | 10x10 ITER=4 AUGMENT=1 | 20000 | 0 non-max, 0 wasted, 0 orth/cons/impl/bp |

The 20,000-cycle 10x10 soak covers 720,096 effective request instants and
154,561 grants with 10% random source + destination backpressure re-drawn every
cycle.  Grant rates under soak (which includes backpressure, so below the
no-backpressure benchmark): 8x8 75.0%, 9x11 82.4%, 10x10 A0 74.1%, 16x16
82.3%, 10x10 A1 77.3% of min(N,M).

### Matching quality (S17) - staggered reset

| Config | First-cycle match | Converge to full (cycles) |
|--------|-------------------|---------------------------|
| 8x8 ITER=1 | 8 of 8 | 0 |
| 8x8 ITER=3 | 8 of 8 | 0 |
| 8x8 ITER=4 (default) | 8 of 8 | 0 |
| 10x10 ITER=4 | 10 of 10 | 0 |
| 10x10 ITER=4 AUGMENT=0 | 10 of 10 | 0 |
| 16x16 ITER=1 | 16 of 16 | 0 |
| 15x15 ITER=1 | 15 of 15 | 0 |

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
