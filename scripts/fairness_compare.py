#!/usr/bin/env python3
"""Fairness model: pure WFA vs iSLIP-first-pass + WFA-fill.

This is an algorithm-level comparison of multi-source/multi-destination
fairness.  It is not an RTL simulation; the strict single-source/single-
destination RTL tests are in tb/tb_fairness.sv (fast) and
tb/tb_fairness_fair.sv (fair).

Metrics:
  src Jain = Jain index of the destination counts for each source, averaged
             over sources with >1 requested destination (1.0 = uniform)
  dst Jain = Jain index of the source counts for each destination, averaged
             over destinations with >1 requesting source.
"""
import random


def wfa_match(req, N, M, delta):
    P = max(N, M)
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
    return [[gl[i][(j - delta) % P] for j in range(M)] for i in range(N)]


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
    fill = wfa_match(res, N, M, delta)
    return [[first[i][j] or fill[i][j] for j in range(M)] for i in range(N)]


def jain(v):
    s = sum(v)
    sq = sum(x * x for x in v)
    return 0.0 if s == 0 or sq == 0 else s * s / (len(v) * sq)


def run(N, M, cycles, pattern, seed):
    random.seed(seed)
    if pattern == "full":
        req = [[1] * M for _ in range(N)]
    else:
        req = [[1 if random.random() < 0.5 else 0 for _ in range(M)]
               for _ in range(N)]
        for i in range(N):
            if not any(req[i]):
                req[i][random.randrange(M)] = 1
    sw = [[0] * M for _ in range(N)]
    sh = [[0] * M for _ in range(N)]
    dw = 0
    gp = [0] * M
    ap = [0] * N
    dh = 0
    for _ in range(cycles):
        gw = wfa_match(req, N, M, dw)
        gh = hybrid_match(req, N, M, gp, ap, dh)
        for i in range(N):
            for j in range(M):
                if gw[i][j]:
                    sw[i][j] += 1
                if gh[i][j]:
                    sh[i][j] += 1
        if any(map(any, gw)):
            dw = (dw + 1) % max(N, M)
        if any(map(any, gh)):
            dh = (dh + 1) % max(N, M)
        for i in range(N):
            row = gh[i]
            if any(row):
                ap[i] = (row.index(1) + 1) % M
        for j in range(M):
            col = [gh[i][j] for i in range(N)]
            if any(col):
                gp[j] = (col.index(1) + 1) % N

    def score(cnt):
        js = []
        jd = []
        for i in range(N):
            vals = [cnt[i][j] for j in range(M) if req[i][j]]
            if len(vals) > 1:
                js.append(jain(vals))
        for j in range(M):
            vals = [cnt[i][j] for i in range(N) if req[i][j]]
            if len(vals) > 1:
                jd.append(jain(vals))
        return (min(js), sum(js) / len(js), min(jd), sum(jd) / len(jd))

    return score(sw), score(sh)


def main():
    N = M = 10
    print("10x10 multi-source fairness model (Jain index, 1.0 = uniform)")
    print("scenario              pure WFA src(avg)  fair src(avg)  "
          "pure WFA dst(avg)  fair dst(avg)")
    cases = [("full crossbar", 1000, "full", 0)]
    cases += [("persistent #%d" % k, 3000, "persistent", s)
              for k, s in enumerate((3, 5, 7), 1)]
    for name, cyc, pat, seed in cases:
        w, h = run(N, M, cyc, pat, seed)
        print("%-20s %6.3f            %6.3f          %6.3f            %6.3f"
              % (name, w[1], h[1], w[3], h[3]))
    print("min/max in the table is average over sources/destinations;")
    print("the fair variant wins on average but is not a strict all-traffic RR guarantee.")


if __name__ == "__main__":
    main()
