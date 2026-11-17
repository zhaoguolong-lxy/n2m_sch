# wavefront 仲裁器（WFA / WWFA）— 电路级方案图

本目录给出 **Wavefront Arbiter（波前仲裁器，WFA）** 的电路级方案图，全部为 PNG
位图（不是 SVG 流程图）。图的组织是“总—分”：

| 图 | 内容 |
|----|------|
| [wfa_00_overview.png](wfa_00_overview.png) | 总图：填充、列旋转、P 级波前、逆旋转、输出编码、δ 寄存器 |
| [wfa_01_cell.png](wfa_01_cell.png) | 分图：单个 crosspoint cell 的门级电路与真值表 |
| [wfa_02_diagonal.png](wfa_02_diagonal.png) | 分图：P 条对角线如何组成 P 级阵列，级内并行、级间传 token |
| [wfa_03_rotation.png](wfa_03_rotation.png) | 分图：δ 旋转、P 路 MUX、源/目的公平性时序 |
| [wfa_04_nowaste.png](wfa_04_nowaste.png) | 分图：“不浪费调度”的判定公式与 S1/S2/S3 例子 |
| [wfa_05_depth.png](wfa_05_depth.png) | 分图：逻辑级数 / 面积指标，>40 级的优化方案 |

## 1. 为什么选 wavefront

| 算法 | 单拍极大匹配？ | 逻辑级数 | 说明 |
|------|----------------|----------|------|
| PIM / iSLIP | 有限轮不保证 | O(ITER·仲裁) + fill | 经典交叉开关调度；需要多轮收敛 |
| iSLIP + 串行 fill（旧方案） | 是（fill 保证） | O(N·优先级选择)，10x10 实测 300 | 极大性靠 N 级串行独裁，深 |
| Wavefront WFA（本方案） | **是** | **O(P)**，10x10 实测 39 | 对角线波前，cell 只看 N/W token |
| Wrapped WFA（WWFA） | 是 | O(P) | 对角线环绕 + 起点旋转，公平性更好 |
| 最大匹配 / 增广路 | 最大 | 更深 | 本需求不要求最大，只要求不浪费 |

WFA 由 Tamir 与 Chi（UCLA）提出，用于 SGI Spider 等交叉开关；经典结论：
n×n 阵列完成一次仲裁需要 (2n-1) 个 cell 延时，整个阵列组合完成、单拍出结果。
本实现用 P=max(N,M) 的 **torus 对角线**，把级数进一步压到 P 级。

## 2. Cell 电路（对应图 01）

每个 crosspoint cell 有：

- `R`：请求；
- `N`：同列上方还没有 grant（north token）；
- `W`：同行左侧还没有 grant（west token）；
- `G`：grant；
- `S`、`E`：把“仍空闲”传给下方 / 右侧。

```text
G = R & N & W
S = N & ~(R & W) = N & ~G
E = W & ~(R & N) = W & ~G
```

只有 `R=N=W=1` 才 grant；grant 同时消耗行 token 和列 token，未 grant 时
token 原样下传。cell 是纯组合逻辑，没有寄存器。

## 3. 为什么它保证“不浪费调度”（对应图 04）

波前按对角线顺序访问每个 crosspoint，每个 cell 恰好访问一次。反证：

> 若请求 `(i,j)` 在结束时源 i 和目的 j 都空闲，则轮到它所在对角线时，i、j
> 也一定空闲（free 集合只会缩小，不会变大），于是 cell 必然 grant，矛盾。

所以不存在“出口空闲、入口却不调度”的请求对，即输出是 **极大匹配（maximal）**。
注意极大不等于最大：某个源可能因为唯一请求的目的已被更早的对角线占用而落选，
这是允许的（图 04 的 S2 例子）。

判定公式：

```text
error <=> exists (i,j):
    i_src_dest_req[i][j] == 1
    and o_grant_src_vld[i] == 0
    and o_grant_dest_vld[j] == 0
```

`tb/tb_maximal.sv` 对 18 种 N/M 形状、每种 773 拍做了这个检查，结果全部为
0 non-maximal、0 wasted pair、0 正交/一致性错误（包括 10x10）。

## 4. 深度 / 面积（对应图 05）

Yosys 0.66 generic gate levels（`ltp -noff`），含旋转 MUX 与输出编码：

| 配置 | P | cells | flops | 级数 | 状态 |
|------|---|-------|-------|------|------|
| 8x8 | 8 | 1189 | 3 | **28** | 达标 |
| 10x10 | 10 | 3699 | 4 | **39** | 达标 |
| 9x11 | 11 | 6072 | 4 | 41 | 超标 1 级 |
| 11x9 | 11 | 6630 | 4 | 43 | 超标 3 级 |
| 16x16 | 16 | 5396 | 4 | 48 | 超标 8 级 |

- 旧 iSLIP + 串行 fill：10x10 11821 cells、300 级、80 flops。
- WFA：10x10 3699 cells、39 级、4 flops；**面积约 1/3，级数约 1/8**。
- P≤10 已满足 ≤40；P=11 只超 1-3 级，可去掉输出编码关键路径或重定时。
- P=16 超 8 级，建议 2 拍流水（每拍 P/2 级，约 24 级）或 4x4 分层
  （局部 WFA + 二级仲裁），代价是 latency 或连线/面积。

> 说明：这里统计的是 Yosys generic gate 映射。真实标准单元库若有 AOI21/OAI21
> 复合门，cell 的“token 更新”可压到 1 级，实际级数会更低。

## 5. 公平性取舍（对应图 03）

δ 是唯一状态，每个 grant 后 `δ ← δ+1 mod P`。P 个周期覆盖所有对角线，
每个源、每个目的都轮获得最高优先级。

- 无竞争时：源 0 请求全部目的 → `0,1,2,...,P-1`（上升循环）。
- 目的 0 被全部源请求 → `0,P-1,P-2,...,1`（下降循环）。

一个对角线旋转同时决定源侧和目的侧优先级，因此两边必然是“一升一降”；
WFA 能保证**计数公平**（每 P 拍每端口各 1 次）和**无饥饿**，但不保证两边都按
0,1,2... 的严格顺序。这是“牺牲一点 RR 公平性换深度”的明确取舍。若必须严格
双向 RR，需要 per-port 指针或 iSLIP 变体，逻辑级数会回升。

## 6. 复现

```bash
# 只生成 PNG（内部用 SVG 模型渲染，不落地 SVG 文件）
python scripts/gen_wfa_diagrams.py

# 极大性检查（18 种 N/M 形状）
iverilog -g2012 -s tb_maximal_top -o sim/torus_max.vvp \
    rtl/fair_arbiter_torus.v tb/tb_maximal.sv
vvp sim/torus_max.vvp

# 综合 / 深度
yosys -p "read_verilog -sv rtl/fair_arbiter_torus.v; \
          chparam -set N 10 -set M 10 fair_arbiter; \
          synth -top fair_arbiter; stat; ltp -noff"
```

RTL：`rtl/fair_arbiter_torus.v`（与旧 `rtl/fair_arbiter.v` 端口、参数兼容，
`ITER`/`AUGMENT` 保留但被忽略）。
