#!/usr/bin/env python3
"""Verify the fair_arbiter matching algorithm's maximality guarantee.

The RTL performs, in one combinational pass:
  1. ISLIP greedy passes (ITER iterations, round-robin pointers);
  2. an optional length-3 augmenting (swap) pass (AUGMENT=1);
  3. a residual fill (serial dictatorship over still-unmatched sources).

This script mirrors that algorithm and checks the user's criterion:

    a cycle is an ERROR iff there is a requested pair (i,j) whose source i
    and destination j both received no grant.

The residual fill has a short proof of correctness: it adds matches only, and
it matches the residual graph maximally (if a requested pair (i,j) survived
with i unmatched and j free, then j was free on i's turn and i would have
taken it).  This script tests that proof exhaustively on small shapes, checks
all shapes 2..16 on random traffic, and - as a stress test - starts from
ARBITRARY matchings (including deliberately broken ones) and confirms that the
fill alone still produces a maximal matching.

ASCII only; no dependencies beyond the Python standard library.
"""
import itertools
import random
import sys


# ---------------------------------------------------------------------------
# Algorithm mirror of rtl/fair_arbiter.v
# ---------------------------------------------------------------------------
def islip(N, M, req, iters):
    g = [j % N for j in range(M)]
    a = [i % M for i in range(N)]
    sm = [False] * N
    dm = [False] * M
    acc = [[False] * M for _ in range(N)]
    for _ in range(iters):
        grant = [[False] * N for _ in range(M)]
        for j in range(M):
            if dm[j]:
                continue
            cand = [i for i in range(N) if req[i][j] and not sm[i]]
            if not cand:
                continue
            hi = [i for i in cand if i >= g[j]]
            grant[j][min(hi) if hi else min(cand)] = True
        for i in range(N):
            if sm[i]:
                continue
            cand = [j for j in range(M) if grant[j][i]]
            if not cand:
                continue
            hi = [j for j in cand if j >= a[i]]
            j = min(hi) if hi else min(cand)
            acc[i][j] = True
            sm[i] = True
            dm[j] = True
    return acc, sm, dm


def swap(N, M, req, acc, sm, dm):
    rematch = [sm[k] and any(req[k][l] and not dm[l] for l in range(M))
               for k in range(N)]
    releasable = [any(acc[k][j] and rematch[k] for k in range(N))
                  for j in range(M)]
    grant_s = [[False] * N for _ in range(M)]
    for j in range(M):
        if releasable[j]:
            cand = [i for i in range(N) if not sm[i] and req[i][j]]
            if cand:
                grant_s[j][min(cand)] = True
    swap_acc = [[False] * M for _ in range(N)]
    for i in range(N):
        if sm[i]:
            continue
        cand = [j for j in range(M) if grant_s[j][i]]
        if cand:
            swap_acc[i][min(cand)] = True
    j_taken = [any(swap_acc[i][j] for i in range(N)) for j in range(M)]
    displaced = [sm[k] and any(acc[k][j] and j_taken[j] for j in range(M))
                 for k in range(N)]
    grant_m = [[False] * N for _ in range(M)]
    for l in range(M):
        if dm[l]:
            continue
        cand = [k for k in range(N) if displaced[k] and req[k][l]]
        if cand:
            grant_m[l][min(cand)] = True
    move = [[False] * M for _ in range(N)]
    for k in range(N):
        if not displaced[k]:
            continue
        cand = [l for l in range(M) if grant_m[l][k]]
        if cand:
            move[k][min(cand)] = True
    out = [[False] * M for _ in range(N)]
    for i in range(N):
        src = move[i] if (sm[i] and displaced[i]) else (
              acc[i] if sm[i] else swap_acc[i])
        out[i] = src[:]
    return out


def fill(N, M, req, base):
    free = [not any(base[i][j] for i in range(N)) for j in range(M)]
    out = [row[:] for row in base]
    for i in range(N):
        if any(out[i]):
            continue
        cand = [j for j in range(M) if req[i][j] and free[j]]
        if cand:
            j = min(cand)
            out[i][j] = True
            free[j] = False
    return out


def schedule(N, M, req, iters=4, augment=True):
    acc, sm, dm = islip(N, M, req, iters)
    base = swap(N, M, req, acc, sm, dm) if augment else acc
    return fill(N, M, req, base)


def check(N, M, req, match):
    sm = [any(match[i]) for i in range(N)]
    dm = [any(match[i][j] for i in range(N)) for j in range(M)]
    orth = (all(sum(match[i]) <= 1 for i in range(N)) and
            all(sum(match[i][j] for i in range(N)) <= 1 for j in range(M)))
    wasted = [(i, j) for i in range(N) for j in range(M)
              if req[i][j] and not sm[i] and not dm[j]]
    return orth, wasted, sum(sum(row) for row in match)


def random_req(N, M, p, rng):
    return [[rng.random() < p for _ in range(M)] for _ in range(N)]


def random_matching(N, M, rng):
    """An arbitrary (not necessarily maximal) orthogonally valid matching."""
    out = [[False] * M for _ in range(N)]
    srcs = list(range(N))
    dsts = list(range(M))
    rng.shuffle(srcs)
    rng.shuffle(dsts)
    for i, j in zip(srcs, dsts):
        if rng.random() < 0.5:
            out[i][j] = True
    return out


def main():
    failures = 0
    cases = 0

    # ---- 1. exhaustive over every request matrix for small shapes ----
    for N, M in [(2, 2), (2, 3), (3, 2), (2, 4), (4, 2), (3, 3),
                 (2, 5), (3, 4), (4, 3)]:
        for bits in itertools.product([0, 1], repeat=N * M):
            req = [list(bits[i * M:(i + 1) * M]) for i in range(N)]
            for aug in (False, True):
                cases += 1
                m = schedule(N, M, req, 4, aug)
                orth, wasted, _ = check(N, M, req, m)
                if not orth or wasted:
                    failures += 1
                    print("FAIL exhaustive %dx%d aug=%d req=%r wasted=%r"
                          % (N, M, aug, req, wasted))
                    if failures > 5:
                        sys.exit(1)

    # ---- 2. every shape 2..16, random densities ----
    rng = random.Random(12345)
    for N in range(2, 17):
        for M in range(2, 17):
            for p in (0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99):
                for _ in range(20):
                    req = random_req(N, M, p, rng)
                    cases += 1
                    m = schedule(N, M, req, 4, True)
                    orth, wasted, _ = check(N, M, req, m)
                    if not orth or wasted:
                        failures += 1
                        print("FAIL random %dx%d p=%.2f wasted=%r"
                              % (N, M, p, wasted))
                        if failures > 5:
                            sys.exit(1)

    # ---- 3. the fill alone repairs an ARBITRARY base matching ----
    # This isolates the guarantee used by the RTL: adding matches can never
    # create a wasted pair, and a maximal matching on the residual graph makes
    # the union maximal.
    for N in range(2, 17):
        for M in range(2, 17):
            for p in (0.1, 0.5, 0.9):
                for _ in range(20):
                    req = random_req(N, M, p, rng)
                    base = random_matching(N, M, rng)
                    cases += 1
                    m = fill(N, M, req, base)
                    orth, wasted, _ = check(N, M, req, m)
                    if not orth or wasted:
                        failures += 1
                        print("FAIL fill-only %dx%d p=%.2f wasted=%r"
                              % (N, M, p, wasted))
                        if failures > 5:
                            sys.exit(1)

    # ---- 4. adversarial deterministic patterns on all shapes 2..16 ----
    for N in range(2, 17):
        for M in range(2, 17):
            pats = []
            pats.append([[True] * M for _ in range(N)])
            pats.append([[j >= (i * M) // N for j in range(M)]
                         for i in range(N)])
            pats.append([[j <= (i * M) // N for j in range(M)]
                         for i in range(N)])
            pats.append([[j == (i * M) // N for j in range(M)]
                         for i in range(N)])
            pats.append([[(i % 2) == (j % 2) for j in range(M)]
                         for i in range(N)])
            pats.append([[((i * 7 + 3) % M) == j for j in range(M)]
                         for i in range(N)])
            for req in pats:
                cases += 1
                m = schedule(N, M, req, 4, True)
                orth, wasted, _ = check(N, M, req, m)
                if not orth or wasted:
                    failures += 1
                    print("FAIL adversarial %dx%d wasted=%r" % (N, M, wasted))
                    if failures > 5:
                        sys.exit(1)

    # ---- 5. size comparison: greedy-only vs swap, both with the fill ----
    print("\nsize (fraction of min(N,M)) on random p=0.5, 200 graphs:")
    for N, M in [(8, 8), (10, 10), (16, 16), (9, 11), (11, 9)]:
        tot0 = tot1 = 0
        for _ in range(200):
            req = random_req(N, M, 0.5, rng)
            _, _, s0 = check(N, M, req, schedule(N, M, req, 4, False))
            _, _, s1 = check(N, M, req, schedule(N, M, req, 4, True))
            tot0 += s0
            tot1 += s1
        mn = min(N, M)
        print("  %2dx%2d  greedy+fill %.1f%%   swap+fill %.1f%%"
              % (N, M, 100.0 * tot0 / (200 * mn), 100.0 * tot1 / (200 * mn)))

    print("\n%d cases checked, %d failures" % (cases, failures))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
