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

Simulator: Icarus Verilog 14.0 (`iverilog -g2012`). All 13 configurations
passed; total 141,213 checks, 0 errors.

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
| cfg_16x16_i1 | PASS | 26892 |
| **Total** | **ALL PASS** | **141213** |

### Matching quality (S17) - effect of ITER

| Config | First-cycle match | Converge to full (cycles) |
|--------|-------------------|---------------------------|
| 8x8 ITER=1 | 1 of 8 | 6 |
| 8x8 ITER=2 | 2 of 8 | 5 |
| 8x8 ITER=3 | 3 of 8 | 4 |

Each extra iteration buys ~1 more first-cycle match and ~1 faster convergence;
all variants converge to a full matching in steady state (pointers
desynchronize over cycles).

Command:
```
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

## 3. Notes

- The two round-robin directions are both exercised with *all* destinations /
  sources and with a *subset*, verifying skip + wrap behaviour.
- Non-power-of-two sizes (6, 5, 3) specifically exercise the `$clog2` width
  and pointer wrap logic.
- The no-reset configuration is verified by `$deposit`-ing the pointers to a
  known state after reset (simulating power-on), then running the same
  invariants; Icarus `$deposit` cannot target unpacked-array words, which is
  why the pointers are stored as flat vectors in the RTL.
