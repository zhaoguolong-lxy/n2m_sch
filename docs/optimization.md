# Fairness / area optimization results (2026-11-24)

Optimization study; the default top is unchanged.  All numbers are
10x10 unless noted; `dflt` is the original Yosys/ABC mapping (NAND/NOR-only
gate set, no AOI/OAI cells), `cmos` adds AOI/OAI/MUX gates (`abc -g cmos`),
which is a closer proxy for a real standard-cell library.  SKY130HD is the
local library cell-level mapping (cells / area / ABC delay).

## 1. Fairness model (`scripts/fairness_explore.py`)

Persistent random traffic, 3000 cycles x seeds 3/5/7:

| Policy | src Jain | dst Jain | K-regular K=8/5/3 |
|---|---|---|---|
| bank / wavefront+ (baseline) | 0.827 | 0.853 | 1.000 / 1.000 / 1.000 |
| LFSR start | 0.828 | 0.855 | 0.125 / 0.200 / 0.333 |
| age / deficit selectors | 0.29-0.42 | 0.30-0.42 | 0.125 / 0.200 / 0.333 |
| 2 schedule permutations | 0.864 | 0.887 | 0.971 / 0.930 / 0.925 |
| 4 schedule permutations | 0.904 | 0.932 | 0.937 / 0.930 / 0.898 |

Only schedule permutation helps; greedy age/deficit policies overfit and
collapse.  Four schedules recover the legacy NS4 fairness with **one bank**.

## 2. RTL variants

| Variant | dflt cells/levels | cmos cells/levels | SKY130 cells / um2 / ps | random src/dst Jain | K-reg Jain |
|---|---|---|---|---|---|
| **bank default** | **12661 / 30** | **9484 / 25** | **7108 / 39794.41 / 3876.72** | 0.821-0.887 / 0.805-0.871 | 1.000 |
| bank + 2 schedules | 12945 / **35** | 10362 / 28 | 7783 / 44870.54 / 4084.01 | 0.867-0.901 / 0.873-0.905 | 0.927-0.971 |
| bank + 4 schedules | 14150 / 40 | 11127 / 29 | 8393 / 48265.04 / 4482.99 | **0.914-0.933 / 0.895-0.934** | 0.896-0.937 |
| **`fair_arbiter_sched4`** (4 sched + adaptive) | 15199 / 40 | 12129 / **28** | 9040 / 53953.00 / 4521.74 | **0.914-0.933 / 0.895-0.934** | **1.000** |
| rotating NS1 | 5586 / 35 | 5544 / 28 | 4530 / 30912.15 / 5166.60 | 0.821-0.887 / 0.805-0.871 | 1.000 |
| rotating NS2 | 7376 / 35 | 7509 / 29 | 6746 / 48761.77 / 5221.03 | 0.867-0.901 / 0.873-0.905 | ~0.93-0.97 |
| rotating NS4 | 11255 / 36 | 11357 / 30 | 10718 / 81874.77 / 5567.39 | 0.914-0.933 / 0.895-0.934 | ~0.93-0.97 |
| fair (iSLIP first + WFA fill) | 5252 / 76 | 5774 / 55 | 4344 / 30967.20 / 8693.45 | 0.866-0.895 / 0.912-0.934 | 1.000 |

The default bank and the delivered 4-schedule adaptive top pass maximality
11/11 and strict RR 24/24 (the intermediate 2-schedule variant was screened
by Jain/maximality smoke tests, not the full suite).  The adaptive mode uses
source/destination degree uniformity to keep the single wavefront+ schedule
for K-regular traffic and rotates four schedules for mixed traffic, so it
recovers K-regular 1.000 while keeping the NS4 random fairness.

## 3. Area experiments on the bank

| Experiment | dflt cells/levels | SKY130 cells / um2 / ps | Verdict |
|---|---|---|---|
| baseline | 12661 / 30 | 7108 / 39794.41 / 3876.72 | reference |
| `SEL_OH=0` binary select | 12855 / 34 | 7479 / 41858.89 / 3953.01 | worse |
| share top-level `eff_req` mask | 12643 / **35** | 7049 / 39357.75 / 3890.70 | -0.8% cells, +5 levels; reject |
| ABC `-D 4000` | 12661 / 30 (maps same) | 7108 / 39584.21 / 3980.17 | <1% area, reject |
| ABC `-D 4500` | 12661 / 30 | 7108 / 39338.98 / 4464.03 | <1.3% area, +15% delay |
| ABC `-D 5500` | 12661 / 30 | 7108 / 39293.93 / 4900.50 | <1.3% area, +26% delay |

There is no meaningful area win inside the bank: the P-core replication is
the area.  The real area lever is the rotating single core (-42% generic
cells / -22% SKY area), at 28 cmos / 35 dflt levels and +33% delay.

## 4. Recommendation

- **Default, depth/area**: keep the bank (`rtl/fair_arbiter.v`).
  25 cmos levels, 9,484 cells, 39,794 um2, 3,877 ps.
- **Fairness mode, best result**: `rtl/fair_arbiter_sched4.v` (module
  `fair_arbiter_sched4`): 4 time-multiplexed schedules plus the adaptive
  uniform-degree gate.  28 cmos levels, 12,129 cells, 53,953 um2, 4,522 ps;
  random Jain 0.914-0.933 / 0.895-0.934, K-regular 1.000.  Verified: main
  regression 192,860 checks, maximality 11/11, strict RR 24/24, 3-shape soak
  and 10x10 x 20,000 soak (144,651 grants) pass.  Compile
  `tb/fair_arbiter_sched4_wrap.v` instead of `rtl/fair_arbiter.v` to run the
  existing testbenches against it.
  At 8x8 it is 7142 / 35 dflt, 5508 / 22 cmos, SKY130HD 4026 / 24755 / 4382 ps.
- **If the conservative NAND/NOR-only 35-level cap is absolute**: the
  4-schedule top is 40 levels in that proxy and cannot be used.  The
  2-schedule bank is exactly 35 levels (0.867-0.901), but the rotating NS2 is
  smaller (7,376 cells) for the same depth/fairness.
- **Area mode**: rotating NS1, 5,544 cmos / 5,586 dflt cells, 30,912 um2,
  5,167 ps.  It is the area winner if 35 dflt / 28 cmos levels and +33%
  delay are acceptable.

Metric note: the fair-variant row is a fresh re-measurement; earlier docs list
5119 / 74 for the same RTL (ABC mapping variance).  The original `ltp` numbers
use the Yosys default gate set, which has no AOI/OAI cells and maps each
wavefront AOI stage to two levels.
`abc -g cmos` includes AOI/OAI/MUX and gives the earlier predicted ~25-level
bank; the SKY130 library has these cells, so `cmos` is the more realistic
generic proxy.  Both metrics are reported above; the default bank passes
both, the fairness modes pass the `cmos` metric.
