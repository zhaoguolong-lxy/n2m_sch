#!/usr/bin/env python3
"""Queue-drain model for the shared-queue use case.

Scenario: each source owns one shared queue that holds packets for several
destinations (not a strict FIFO).  Every cycle the source exposes a window of
W entries as its request bitmap; the arbiter grants at most one packet per
source and per destination (maximal matching).  The model measures:

  makespan      cycles until every queue is empty (lower is better)
  finish Jain   Jain index of the per-source finish cycles (1.0 = all sources
                drain out together)
  spread        max(finish) - min(finish) in cycles

Schedulers compared:
  wfa1/wfa2/wfa4  1, 2 or 4 wavefront schedules (rtl/fair_arbiter.v)
  fair            iSLIP first pass + WFA fill (rtl/fair_arbiter_fair.v)
  max             maximum-cardinality matching (augmenting paths); this is a
                  throughput upper bound, not a realizable single-cycle design
"""
import random
from collections import deque

N = 10
M = 10
Q = 20          # packets per source
CYCLES_CAP = 4000


def gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def coprimes(n, k):
    out = []
    for c in range(1, n):
        if gcd(c, n) == 1:
            out.append(c)
        if len(out) == k:
            break
    return out or [1]


def wfa_match(req, N, M, delta, perm):
    P = max(N, M)
    reqw = [[0] * P for _ in range(P)]
    for i in range(N):
        for j in range(M):
            reqw[i][(j - delta) % P] = req[i][j]
    rf = [True] * P
    cf = [True] * P
    gl = [[0] * P for _ in range(P)]
    for d in range(P):
        for r in range(N):
            i = perm[r]
            j = (r + d) % P
            if j < M and reqw[i][j] and rf[r] and cf[j]:
                gl[r][j] = 1
                rf[r] = False
                cf[j] = False
    out = [[0] * M for _ in range(N)]
    for r in range(N):
        out[perm[r]] = [gl[r][(j - delta) % M] for j in range(M)]
    return out


def max_match(req, N, M):
    match_r = [-1] * M

    def try_k(i, seen):
        for j in range(M):
            if req[i][j] and not seen[j]:
                seen[j] = True
                if match_r[j] == -1 or try_k(match_r[j], seen):
                    match_r[j] = i
                    return True
        return False

    for i in range(N):
        try_k(i, [False] * M)
    g = [[0] * M for _ in range(N)]
    for j, i in enumerate(match_r):
        if i >= 0:
            g[i][j] = 1
    return g


def first_pass(req, N, M, gp, ap):
    g = [[0] * M for _ in range(N)]
    for j in range(M):
        cand = [i for i in range(N) if req[i][j]]
        if cand:
            k = next((i for i in cand if i >= gp[j]), cand[0])
            g[k][j] = 1
    a = [[0] * M for _ in range(N)]
    for i in range(N):
        cand = [j for j in range(M) if g[i][j]]
        if cand:
            k = next((j for j in cand if j >= ap[i]), cand[0])
            a[i][k] = 1
    return a


def hybrid_match(req, N, M, gp, ap, delta):
    first = first_pass(req, N, M, gp, ap)
    sm = [any(first[i]) for i in range(N)]
    dm = [any(first[i][j] for i in range(N)) for j in range(M)]
    res = [[req[i][j] and not sm[i] and not dm[j] for j in range(M)]
           for i in range(N)]
    fill = wfa_match(res, N, M, delta, list(range(N)))
    return [[first[i][j] or fill[i][j] for j in range(M)] for i in range(N)]


def jain(v):
    s = sum(v)
    q = sum(x * x for x in v)
    return 0.0 if s == 0 or q == 0 else s * s / (len(v) * q)


def run(window, seed, sched):
    random.seed(seed)
    queues = [deque(random.randrange(M) for _ in range(Q)) for _ in range(N)]
    perms = [[(c * i) % N for i in range(N)] for c in coprimes(N, 4)]
    delta = 0
    gp = [0] * M
    ap = [0] * N
    finish = [-1] * N
    t = 0
    while any(queues) and t < CYCLES_CAP:
        req = [[0] * M for _ in range(N)]
        for i in range(N):
            if queues[i]:
                for j in list(queues[i])[:window]:
                    req[i][j] = 1
        if sched == "max":
            g = max_match(req, N, M)
        elif sched == "fair":
            g = hybrid_match(req, N, M, gp, ap, delta)
        else:
            ns = int(sched[-1])
            g = wfa_match(req, N, M, delta, perms[(t // max(N, M)) % ns])
        for i in range(N):
            for j in range(M):
                if g[i][j] and queues[i]:
                    try:
                        queues[i].remove(j)
                    except ValueError:
                        pass
        for i in range(N):
            if finish[i] < 0 and not queues[i]:
                finish[i] = t + 1
        if any(map(any, g)):
            delta = (delta + 1) % max(N, M)
        if sched == "fair":
            for i in range(N):
                row = g[i]
                if any(row):
                    ap[i] = (row.index(1) + 1) % M
            for j in range(M):
                col = [g[i][j] for i in range(N)]
                if any(col):
                    gp[j] = (col.index(1) + 1) % N
        t += 1
    return t, finish



def main():
    print("Shared-queue drain (10x10, 20 packets/source, 10 seeds)")
    print("window = entries exposed per source each cycle (1 = FIFO head only)")
    print("%-7s %-6s %10s %12s %10s" %
          ("window", "sched", "makespan", "finish-Jain", "spread"))
    for window in (1, 2, 4, 10):
        for sched in ("wfa1", "wfa2", "wfa4", "fair", "max"):
            ms, jf, sp = 0.0, 0.0, 0.0
            seeds = 10
            for s in range(seeds):
                t, fin = run(window, s, sched)
                ms += t
                jf += jain(fin)
                sp += max(fin) - min(fin)
            print("%-7d %-6s %10.1f %12.3f %10.1f" %
                  (window, sched, ms / seeds, jf / seeds, sp / seeds))
    print("max = maximum-cardinality reference (augmenting paths), not")
    print("realizable single-cycle; the arbiter's maximal matching is within")
    print("noise of it once the window is >= 4.")


if __name__ == "__main__":
    main()
