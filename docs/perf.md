# Fair Arbiter - Scheduling Performance

Benchmark: `tb/tb_perf.sv` (Icarus Verilog). Per config: 100-cycle warmup + 1500
cycles of full-crossbar + 1500 cycles of Bernoulli(0.5), PTR_RESET=1, with
STAGGERED pointer reset (g_ptr[j]=j mod N, a_ptr[i]=i mod M).

Metrics:
- **first** = matches in the first cycle of full-crossbar traffic.
- **converge** = cycles until the matching reaches min(N,M).
- **full** = average matches/cycle under full-crossbar (100% load).
- **bern** = average matches/cycle under Bernoulli(0.5) random traffic.

## Results

| NxM | ITER | first | converge | full (of min) | bern (of min) |
|-----|------|-------|----------|---------------|---------------|
| 4x4 | 1 | 4 | 0 | 4.00/4 (100%) | 2.38/4 (59%) |
| 4x4 | 2 | 4 | 0 | 4.00/4 (100%) | 2.63/4 (66%) |
| 4x4 | 3 | 4 | 0 | 4.00/4 (100%) | 2.63/4 (66%) |
| 8x8 | 1 | 8 | 0 | 8.00/8 (100%) | 5.16/8 (64%) |
| 8x8 | 2 | 8 | 0 | 8.00/8 (100%) | 7.11/8 (89%) |
| 8x8 | 3 | 8 | 0 | 8.00/8 (100%) | 7.15/8 (89%) |
| 16x16 | 1 | 16 | 0 | 16.00/16 (100%) | 10.66/16 (67%) |
| 8x4 | 1 | 4 | 0 | 4.00/4 (100%) | 3.74/4 (94%) |
| 8x4 | 2 | 4 | 0 | 4.00/4 (100%) | 4.00/4 (100%) |
| 4x8 | 1 | 4 | 0 | 4.00/4 (100%) | 3.34/4 (84%) |
| 4x8 | 2 | 4 | 0 | 4.00/4 (100%) | 3.83/4 (96%) |
| 9x11 | 1 | 9 | 0 | 9.00/9 (100%) | 6.81/9 (76%) |
| 9x11 | 2 | 9 | 0 | 9.00/9 (100%) | 8.48/9 (94%) |

## Key takeaways

1. **Full-crossbar is immediately maximal**: with the staggered pointer reset,
   the very first cycle dispatches min(N,M) matches (8 for 8x8, 16 for 16x16).
   No desynchronization ramp-up.  This is what "输出被占满" requires.

2. **ITER only matters for random (non-uniform) traffic**:
   - `first`/`converge`/`full` are already optimal for every ITER.
   - Under Bernoulli(0.5), extra iterations raise throughput a lot:
     8x8 64% -> 89%, 4x8 84% -> 96%, 9x11 76% -> 94%.

3. **Aspect ratio**:
   - N > M (8x4, dest-limited): near-full even at ITER=1.
   - N < M (4x8, source-limited): ITER=2 recovers most of the "hot source"
     loss (84% -> 96%).

4. **Recommendation**: ITER=1 is enough for uniform/high-load traffic (and now
   already maximal in one cycle); ITER=2 is worth ~2x area for bursty/random
   traffic (recovers ~90%+ throughput).
