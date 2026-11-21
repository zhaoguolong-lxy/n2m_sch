#!/usr/bin/env python3
"""Fairness model: WFA schedules vs the iSLIP-first fair variant.

Algorithm-level comparison of multi-source/multi-destination fairness.
Not an RTL simulation; the strict single-source/single-destination RTL
tests are in tb/tb_fairness.sv (fast) and tb/tb_fairness_fair.sv (fair).

The multi-schedule WFA runs several wavefronts in parallel, each with a
fixed row permutation (r -> (c*r) mod N, c coprime to N); the schedule
rotates every P grants.  This matches rtl/fair_arbiter.v.

Metrics:
  src Jain = Jain index of the destination counts for each source, averaged
             over sources with >1 requested destination (1.0 = uniform)
  dst Jain = Jain index of the source counts for each destination, averaged
             over destinations with >1 requesting source.
"""
import random

NSCHED = 4


def gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def coprime_list(n, k):
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


def wfa_match_wp(req, N, M, delta, perm):
    """Wavefront+ matching (Becker / Rasheed): same scan as wfa_match, but
    the caller advances delta to the diagonal after the first diagonal that
    actually has a request, instead of always delta+1.

    Returns (grant matrix, delta step).  The grant matrix is identical to
    wfa_match for the same delta; only the next delta differs.
    """
    P = max(N, M)
    reqw = [[0] * P for _ in range(P)]
    for i in range(N):
        for j in range(M):
            reqw[i][(j - delta) % P] = req[i][j]
    rf = [True] * P
    cf = [True] * P
    gl = [[0] * P for _ in range(P)]
    first_req = -1
    for d in range(P):
        for r in range(N):
            i = perm[r]
            j = (r + d) % P
            if j < M and reqw[i][j] and first_req < 0:
                first_req = d
            if j < M and reqw[i][j] and rf[r] and cf[j]:
                gl[r][j] = 1
                rf[r] = False
                cf[j] = False
    out = [[0] * M for _ in range(N)]
    for r in range(N):
        out[perm[r]] = [gl[r][(j - delta) % M] for j in range(M)]
    return out, (1 if first_req < 0 else first_req + 1)


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


def run(N, M, cycles, pattern, seed, nsched, hybrid=False):
    random.seed(seed)
    if pattern == "full":
        req = [[1] * M for _ in range(N)]
    else:
        req = [[1 if random.random() < 0.5 else 0 for _ in range(M)]
               for _ in range(N)]
        for i in range(N):
            if not any(req[i]):
                req[i][random.randrange(M)] = 1
    perms = [[(c * i) % N for i in range(N)]
             for c in coprime_list(N, nsched)]
    sw = [[0] * M for _ in range(N)]
    dw = 0
    t = 0
    gp = [0] * M
    ap = [0] * N
    dh = 0
    for _ in range(cycles):
        if hybrid:
            gh = hybrid_match(req, N, M, gp, ap, dh)
        else:
            gh = wfa_match(req, N, M, dw, perms[(t // max(N, M)) % len(perms)])
        for i in range(N):
            for j in range(M):
                if gh[i][j]:
                    sw[i][j] += 1
        if any(map(any, gh)):
            dw = (dw + 1) % max(N, M)
            dh = (dh + 1) % max(N, M)
            t += 1
        if hybrid:
            for i in range(N):
                row = gh[i]
                if any(row):
                    ap[i] = (row.index(1) + 1) % M
            for j in range(M):
                col = [gh[i][j] for i in range(N)]
                if any(col):
                    gp[j] = (col.index(1) + 1) % N

    js = []
    jd = []
    for i in range(N):
        vals = [sw[i][j] for j in range(M) if req[i][j]]
        if len(vals) > 1:
            js.append(jain(vals))
    for j in range(M):
        vals = [sw[i][j] for i in range(N) if req[i][j]]
        if len(vals) > 1:
            jd.append(jain(vals))
    return (sum(js) / len(js), sum(jd) / len(jd))


def regular_req(N, M, K, seed=None):
    """K-regular request matrix: source i asks (i..i+K-1) mod M.  With a
    random row/column permutation this is a random K-regular bipartite graph
    (every source and every destination has degree K)."""
    req = [[1 if (j - i) % M < K else 0 for j in range(M)] for i in range(N)]
    if seed is not None:
        rng = random.Random(seed)
        rows = list(range(N))
        cols = list(range(M))
        rng.shuffle(rows)
        rng.shuffle(cols)
        req = [[req[rows[i]][cols[j]] for j in range(M)] for i in range(N)]
    return req


def run_req(req, N, M, cycles, nsched):
    perms = [[(c * i) % N for i in range(N)]
             for c in coprime_list(N, nsched)]
    sw = [[0] * M for _ in range(N)]
    d = 0
    t = 0
    for _ in range(cycles):
        g = wfa_match(req, N, M, d, perms[(t // max(N, M)) % len(perms)])
        for i in range(N):
            for j in range(M):
                if g[i][j]:
                    sw[i][j] += 1
        if any(map(any, g)):
            d = (d + 1) % max(N, M)
            t += 1
    js = []
    jd = []
    for i in range(N):
        v = [sw[i][j] for j in range(M) if req[i][j]]
        if len(v) > 1:
            js.append(jain(v))
    for j in range(M):
        v = [sw[i][j] for i in range(N) if req[i][j]]
        if len(v) > 1:
            jd.append(jain(v))
    return sum(js) / len(js), sum(jd) / len(jd)


def run_req_wp(req, N, M, cycles, nsched):
    """Same as run_req, with the wavefront+ delta update."""
    perms = [[(c * i) % N for i in range(N)]
             for c in coprime_list(N, nsched)]
    sw = [[0] * M for _ in range(N)]
    d = 0
    t = 0
    for _ in range(cycles):
        g, step = wfa_match_wp(req, N, M, d,
                               perms[(t // max(N, M)) % len(perms)])
        for i in range(N):
            for j in range(M):
                if g[i][j]:
                    sw[i][j] += 1
        if any(map(any, g)):
            d = (d + step) % max(N, M)
            t += 1
    js = []
    jd = []
    for i in range(N):
        v = [sw[i][j] for j in range(M) if req[i][j]]
        if len(v) > 1:
            js.append(jain(v))
    for j in range(M):
        v = [sw[i][j] for i in range(N) if req[i][j]]
        if len(v) > 1:
            jd.append(jain(v))
    return sum(js) / len(js), sum(jd) / len(jd)


def main():
    N = M = 10
    print("10x10 multi-source fairness model (Jain index, 1.0 = uniform)")
    print("%-18s %10s %10s %10s %10s %10s" %
          ("scenario", "WFAx1 src", "WFAx2 src", "WFAx4 src",
           "WFAx1 dst", "WFAx4 dst"))
    cases = [("full crossbar", 1000, "full", 0)]
    cases += [("persistent #%d" % k, 3000, "persistent", s)
              for k, s in enumerate((3, 5, 7), 1)]
    for name, cyc, pat, seed in cases:
        r1 = run(N, M, cyc, pat, seed, 1)
        r2 = run(N, M, cyc, pat, seed, 2)
        r4 = run(N, M, cyc, pat, seed, 4)
        print("%-18s %10.3f %10.3f %10.3f %10.3f %10.3f" %
              (name, r1[0], r2[0], r4[0], r1[1], r4[1]))
    for name, cyc, pat, seed in cases[1:]:
        rf = run(N, M, cyc, pat, seed, 1, hybrid=True)
        print("  fair variant %-12s src %.3f  dst %.3f" %
              (name, rf[0], rf[1]))
    print("full crossbar is 1.000 for every scheme; the fair variant is not")
    print("a strict all-traffic RR guarantee (fill-only ports are approximate).")

    print()
    print("Saturated uniform traffic: K-regular request graph")
    print("(every source asks K destinations, every destination is asked by K")
    print("sources).  'circ' is the diagonal-aligned pattern, 'rnd' is the same")
    print("graph with random row/column permutations.")
    print("%-6s %-5s %10s %10s %10s" % ("K", "shape", "WFAx1 src", "WFAx2 src", "WFAx4 src"))
    for K in (10, 8, 5, 3):
        for tag, seed in (("circ", None), ("rnd", 7)):
            req = regular_req(N, M, K, seed)
            r1 = run_req(req, N, M, 2000, 1)
            r2 = run_req(req, N, M, 2000, 2)
            r4 = run_req(req, N, M, 2000, 4)
            print("%-6d %-5s %10.3f %10.3f %10.3f" %
                  (K, tag, r1[0], r2[0], r4[0]))

    print()
    print("wavefront+ (delta advances to the diagonal after the first")
    print("diagonal that has any request; no effect on random traffic):")
    print("%-6s %-5s %10s %10s %10s %10s" %
          ("K", "shape", "WFAx1", "WFAx1+", "WFAx4", "WFAx4+"))
    for K in (10, 8, 5, 3):
        req = regular_req(N, M, K)
        r1 = run_req(req, N, M, 2000, 1)
        r1p = run_req_wp(req, N, M, 2000, 1)
        r4 = run_req(req, N, M, 2000, 4)
        r4p = run_req_wp(req, N, M, 2000, 4)
        print("%-6d %-5s %10.3f %10.3f %10.3f %10.3f" %
              (K, "circ", r1[0], r1p[0], r4[0], r4p[0]))


if __name__ == "__main__":
    main()
