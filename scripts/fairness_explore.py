#!/usr/bin/env python3
"""Explore fairness policies for the replicate/bank WFA (model only).

The bank instantiates all P fixed-delta WFA cores; the only freedom is which
candidate the registered select picks each cycle.  This script compares
selection policies on the same persistent request patterns and K-regular
graphs used by scripts/fairness_compare.py.

Policies:
  seq          delta + 1 every granted cycle
  wp           wavefront+ (baseline): after the first present diagonal
  strideS      delta + S mod P, S in {2,3,7}
  alt          delta + 1 / -1 alternating
  lfsr         pseudo-random present diagonal
  age          pick the candidate whose granted ports are oldest
  deficit      pick the candidate whose granted ports have the lowest counts
  perm4_shared one bank; 4 row permutations rotate every P grants; shared delta
  perm4_indep  4 independent deltas (legacy NS4-like); schedule rotates
"""
import random
from fairness_compare import wfa_match, regular_req, jain, coprime_list

N = M = 10
P = max(N, M)
PERMS4 = [[(c * i) % N for i in range(N)] for c in coprime_list(N, 4)]
PERMS2 = PERMS4[:2]


def present(req, perm=None):
    if perm is None:
        return [any(req[i][(i + k) % N] for i in range(N)) for k in range(P)]
    return [any(req[perm[i]][(i + k) % N] for i in range(N)) for k in range(P)]


def wp_step(req, d, perm=None):
    pres = present(req, perm)
    for off in range(P):
        k = (d + off) % P
        if pres[k]:
            return (k + 1) % P
    return d


def lfsr_next(state):
    return ((state * 1103515245 + 12345) >> 8) & 0xffffffff


def run_policy(policy, cycles, seed):
    random.seed(seed)
    req = [[1 if random.random() < 0.5 else 0 for _ in range(M)]
           for _ in range(N)]
    for i in range(N):
        if not any(req[i]):
            req[i][random.randrange(M)] = 1

    sw = [[0] * M for _ in range(N)]
    last_s = [0] * N
    last_d = [0] * M
    cnt_s = [0] * N
    cnt_d = [0] * M
    d = 0
    alt_step = 1
    lfsr = 1
    grants_total = 0
    sched = 0
    d4 = [0, 0, 0, 0]

    for t in range(cycles):
        perm = list(range(N))
        if policy in ("perm4_shared", "perm4_fast", "perm4_half", "perm2_shared"):
            nsch = 2 if policy == "perm2_shared" else 4
            perms = PERMS2 if nsch == 2 else PERMS4
            if policy == "perm4_fast":
                sched = grants_total % nsch
            elif policy == "perm4_half":
                sched = (grants_total // max(1, P // 2)) % nsch
            else:
                sched = (grants_total // P) % nsch
            perm = perms[sched]
            cand = wfa_match(req, N, M, d, perm)
            d = wp_step(req, d, perm)
        elif policy == "perm4_indep":
            sched = (grants_total // P) % 4
            perm = PERMS4[sched]
            cand = wfa_match(req, N, M, d4[sched], perm)
            for s in range(4):
                d4[s] = wp_step(req, d4[s], PERMS4[s])
        elif policy in ("age", "age_min", "deficit", "deficit_minmax"):
            best = None
            best_score = None
            for k in range(P):
                g = wfa_match(req, N, M, k, perm)
                ages = []
                cnts = []
                for i in range(N):
                    for j in range(M):
                        if g[i][j]:
                            ages.append((t - last_s[i]) + (t - last_d[j]))
                            cnts.append(cnt_s[i] + cnt_d[j])
                if policy == "age":
                    score = (sum(ages), min(ages), (t + k) % P)
                elif policy == "age_min":
                    score = (min(ages), sum(ages), (t + k) % P)
                elif policy == "deficit":
                    score = (-sum(cnts), -max(cnts), (t + k) % P)
                else:
                    score = (-max(cnts), -sum(cnts), (t + k) % P)
                if best_score is None or score > best_score:
                    best_score = score
                    best = g
                    best_k = k
            cand = best
            d = (best_k + 1) % P
        else:
            if policy == "lfsr":
                pres = present(req)
                choices = [k for k in range(P) if pres[k]]
                lfsr = lfsr_next(lfsr)
                d = choices[lfsr % len(choices)] if choices else d
                cand = wfa_match(req, N, M, d, perm)
                d = (d + 1) % P
            else:
                cand = wfa_match(req, N, M, d, perm)
                if policy == "seq":
                    d = (d + 1) % P
                elif policy == "wp":
                    d = wp_step(req, d)
                elif policy == "alt":
                    d = (d + alt_step) % P
                    alt_step = -alt_step
                elif policy.startswith("stride"):
                    d = (d + int(policy[6:])) % P

        any_g = False
        for i in range(N):
            for j in range(M):
                if cand[i][j]:
                    any_g = True
                    sw[i][j] += 1
                    last_s[i] = t
                    last_d[j] = t
                    cnt_s[i] += 1
                    cnt_d[j] += 1
        if any_g:
            grants_total += 1

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
    return sum(js) / len(js), sum(jd) / len(jd), grants_total / cycles


def run_regular(policy, K, seed=None, cycles=2000):
    req = regular_req(N, M, K, seed)
    sw = [[0] * M for _ in range(N)]
    d = 0
    d4 = [0, 0, 0, 0]
    t = 0
    grants = 0
    for _ in range(cycles):
        if policy in ("perm4_shared", "perm4_fast", "perm4_half", "perm2_shared"):
            nsch = 2 if policy == "perm2_shared" else 4
            perms = PERMS2 if nsch == 2 else PERMS4
            if policy == "perm4_fast":
                sched = grants % nsch
            elif policy == "perm4_half":
                sched = (grants // max(1, P // 2)) % nsch
            else:
                sched = (grants // P) % nsch
            perm = perms[sched]
            g = wfa_match(req, N, M, d, perm)
            d = wp_step(req, d, perm)
        elif policy == "perm4_indep":
            sched = (grants // P) % 4
            perm = PERMS4[sched]
            g = wfa_match(req, N, M, d4[sched], perm)
            for s in range(4):
                d4[s] = wp_step(req, d4[s], PERMS4[s])
        else:
            g = wfa_match(req, N, M, d, list(range(N)))
            if policy == "seq":
                d = (d + 1) % P
            elif policy == "wp":
                d = wp_step(req, d)
            elif policy.startswith("stride"):
                d = (d + int(policy[6:])) % P
        for i in range(N):
            for j in range(M):
                if g[i][j]:
                    sw[i][j] += 1
        if any(map(any, g)):
            t += 1
            grants += 1
    js = []
    for i in range(N):
        vals = [sw[i][j] for j in range(M) if req[i][j]]
        if len(vals) > 1:
            js.append(jain(vals))
    return sum(js) / len(js)


def main():
    policies = ["seq", "wp", "stride2", "stride3", "stride7", "alt",
                "lfsr", "age", "age_min", "deficit", "deficit_minmax",
                "perm2_shared", "perm4_shared", "perm4_fast", "perm4_half"]
    print("10x10 persistent traffic, 3000 cycles x seeds 3/5/7")
    print("%-13s %7s %7s %7s %8s" %
          ("policy", "src avg", "dst avg", "src min", "grant/cyc"))
    for pol in policies:
        vals = [run_policy(pol, 3000, s) for s in (3, 5, 7)]
        ss = [v[0] for v in vals]
        ds = [v[1] for v in vals]
        gp = sum(v[2] for v in vals) / 3
        print("%-13s %7.3f %7.3f %7.3f %8.3f" %
              (pol, sum(ss) / 3, sum(ds) / 3, min(ss), gp))
    print()
    print("K-regular circulant src Jain (2000 cycles)")
    print("%-13s %7s %7s %7s" % ("policy", "K=8", "K=5", "K=3"))
    for pol in policies:
        vals = [run_regular(pol, K) for K in (8, 5, 3)]
        print("%-13s %7.3f %7.3f %7.3f" % (pol, *vals))


if __name__ == "__main__":
    main()
