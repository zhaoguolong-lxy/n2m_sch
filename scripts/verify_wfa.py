#!/usr/bin/env python3
"""Exhaustive algorithm-level check of the Wavefront (WFA/WWFA) arbiter.

Mirrors rtl/fair_arbiter.v:
  - P = max(N,M), pad the request matrix to P x P;
  - rotate columns by delta;
  - process torus diagonals d = 0..P-1, cells (i, (i+d)%P);
  - G = R & row_free & col_free, then clear row/col.

Checks, for every case:
  1. orthogonality (one grant per row and per column);
  2. maximality: no requested pair with both row and column idle
     (the user's "no wasted scheduling" criterion);
  3. grants are a subset of requests.
"""
import itertools
import random


def wfa(req, N, M, delta):
    P = max(N, M)
    # column rotation: logical column j reads physical (j+delta)%P
    reqw = [[0] * P for _ in range(P)]
    for i in range(N):
        for j in range(M):
            reqw[i][(j - delta) % P] = req[i][j]
    rf = [True] * P
    cf = [True] * P
    gl = [[0] * P for _ in range(P)]
    for d in range(P):
        for i in range(P):
            j = (i + d) % P
            if reqw[i][j] and rf[i] and cf[j]:
                gl[i][j] = 1
                rf[i] = False
                cf[j] = False
    g = [[0] * M for _ in range(N)]
    for i in range(N):
        for j in range(M):
            g[i][j] = gl[i][(j - delta) % P]
    return g


def check(req, N, M, g):
    # orthogonal rows/columns
    for i in range(N):
        if sum(g[i]) > 1:
            return "row %d has multiple grants" % i
    for j in range(M):
        if sum(g[i][j] for i in range(N)) > 1:
            return "column %d has multiple grants" % j
    # grants subset of requests
    for i in range(N):
        for j in range(M):
            if g[i][j] and not req[i][j]:
                return "grant (%d,%d) not requested" % (i, j)
    # maximality
    for i in range(N):
        for j in range(M):
            if req[i][j] and not any(g[i]) and \
               not any(g[i2][j] for i2 in range(N)):
                return "wasted pair (%d,%d)" % (i, j)
    return None


def main():
    random.seed(20261118)
    cases = 0
    fails = 0

    # 1) exhaustive over all request matrices for small shapes
    small = [(2, 2), (2, 3), (3, 2), (2, 4), (4, 2), (3, 3)]
    for (N, M) in small:
        P = max(N, M)
        for bits in itertools.product([0, 1], repeat=N * M):
            req = [list(bits[i * M:(i + 1) * M]) for i in range(N)]
            for delta in range(P):
                g = wfa(req, N, M, delta)
                cases += 1
                err = check(req, N, M, g)
                if err:
                    fails += 1
                    if fails <= 10:
                        print("FAIL %dx%d delta=%d: %s" % (N, M, delta, err))

    # 2) all shapes 2..16, several densities / graphs / deltas
    for N in range(2, 17):
        for M in range(2, 17):
            P = max(N, M)
            for dens in (5, 10, 25, 50, 75, 90, 99):
                for _ in range(5):
                    req = [[1 if random.randrange(100) < dens else 0
                            for _ in range(M)] for _ in range(N)]
                    for delta in range(P):
                        g = wfa(req, N, M, delta)
                        cases += 1
                        err = check(req, N, M, g)
                        if err:
                            fails += 1
                            if fails <= 10:
                                print("FAIL %dx%d delta=%d: %s"
                                      % (N, M, delta, err))

    print("WFA algorithm check: %d cases, %d failures" % (cases, fails))
    if fails:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
