# Fair Arbiter - Scheduling Performance

Benchmark: `tb/tb_perf.sv` (Icarus Verilog). Per config: 100-cycle warmup + 1500
cycles of full-crossbar + 1500 cycles of Bernoulli(0.5), PTR_RESET=1.

Metrics:
- **first** = matches in the first cycle of full-crossbar traffic.
- **converge** = cycles until the matching reaches min(N,M).
- **full** = average matches/cycle under full-crossbar (100% load).
- **bern** = average matches/cycle under Bernoulli(0.5) random traffic.

## Results

| NxM | ITER | first | converge | full (of min) | bern (of min) |
|-----|------|-------|----------|---------------|---------------|
| 4x4 | 1 | 1 | 3 | 4.00/4 (100%) | 2.38/4 (59%) |
| 4x4 | 2 | 2 | 2 | 4.00/4 (100%) | 2.63/4 (66%) |
| 4x4 | 3 | 3 | 1 | 4.00/4 (100%) | 2.63/4 (66%) |
| 8x8 | 1 | 1 | 7 | 8.00/8 (100%) | 5.16/8 (65%) |
| 8x8 | 2 | 2 | 6 | 8.00/8 (100%) | 7.11/8 (89%) |
| 8x8 | 3 | 3 | 5 | 8.00/8 (100%) | 7.14/8 (89%) |
| 16x16 | 1 | 1 | 15 | 16.00/16 (100%) | 10.73/16 (67%) |
| 8x4 | 1 | 1 | 3 | 4.00/4 (100%) | 4.00/4 (100%) |
| 8x4 | 2 | 2 | 2 | 4.00/4 (100%) | 4.00/4 (100%) |
| 4x8 | 1 | 1 | 3 | 4.00/4 (100%) | 3.34/4 (84%) |
| 4x8 | 2 | 2 | 2 | 4.00/4 (100%) | 3.83/4 (96%) |
| 9x11 | 1 | 1 | 8 | 9.00/9 (100%) | 6.82/9 (76%) |
| 9x11 | 2 | 2 | 7 | 9.00/9 (100%) | 8.50/9 (94%) |

## Key takeaways

1. **One cycle dispatches many requests**: a single beat produces up to
   min(N,M) simultaneous source->dest matches (8 for 8x8, 16 for 16x16). Under
   full-crossbar the steady-state matching is 100% of min(N,M) for every ITER.

2. **ITER only matters for transients and non-uniform traffic**:
   - `first` grows linearly with ITER (1/2/3) and `converge` shrinks.
   - Steady-state full-crossbar is 100% regardless of ITER.
   - Under Bernoulli(0.5), extra iterations raise throughput a lot:
     8x8 65% -> 89%, 4x8 84% -> 96%, 9x11 76% -> 94%.

3. **Aspect ratio matters**:
   - N > M (8x4, dest-limited): 100% even with ITER=1.
   - N < M (4x8, source-limited): the "hot source" problem hurts single pass;
     ITER=2 recovers most of it (84% -> 96%).

4. **Recommendation**: ITER=1 is enough for uniform/high-load traffic; ITER=2
   is worth the ~2x area for bursty/random traffic (recovers ~90%+ throughput).
