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
| [wfa_05_depth.png](wfa_05_depth.png) | 分图：逻辑级数 / 面积指标 |
| [wfa_06_fairness.png](wfa_06_fairness.png) | 分图：单源 / 单目的严格 RR 覆盖（与 WFA 并行） |
| [wfa_07_fair_hybrid.png](wfa_07_fair_hybrid.png) | 分图：fair 变体（iSLIP 首轮 + WFA fill） |

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

默认 WFA + 单源/单目的 RR 覆盖：

| 配置 | cells | 级数 | 状态 |
|------|-------|------|------|
| 8x8 | 3038 | **27** | 达标 |
| 10x10 | 5925 | **34** | 达标 |
| 9x11 | 5847 | **36** | 达标 |
| 11x9 | 5808 | **36** | 达标 |
| 16x16 | - | - | 不在本变体目标内 |

纯 WFA（无覆盖）参考：8x8 1181/28，10x10 2062/35，9x11 2029/35，
11x9 2029/35，16x16 5261/48。单侧 RR 覆盖与 WFA 并行，面积增加但关键路径
仍是 WFA。

- 当前实现加入**对数循环旋转器**、**N>M 转置 wrapper**，以及并行的
  **单源/单目的严格 RR 覆盖**（a_ptr/g_ptr + 每端口 RR 选择器）。
- 旧 iSLIP + 串行 fill：10x10 11821 cells、300 级、80 flops。
- 默认（WFA + 覆盖）：10x10 5925 cells、34 级；纯 WFA：2062 cells、35 级；
  fair 变体：5474 cells、73 级；iSLIP+fill：11821 cells、300 级。
- 8x8 / 10x10 / 9x11 / 11x9 均已 ≤40；11x9 通过 N>M 转置复用 9x11 核心；16x16 不在本变体目标内。

> 说明：这里统计的是 Yosys generic gate 映射。真实标准单元库若有 AOI21/OAI21
> 复合门，cell 的“token 更新”可压到 1 级，实际级数会更低。

## 5. 公平性（对应图 03 / 06）

默认 RTL 在 WFA 之外并联了一个**单源 / 单目的严格 RR 覆盖**：

- **只有一个源有请求**：每源 `a_ptr[i]` 选择“从指针开始第一个被请求的目的”，
  覆盖 WFA 的选择；源的获授目的序列严格轮询（all/even/odd 子集都正确）。
- **只有一个目的有请求**：每目的 `g_ptr[j]` 选择“从指针开始第一个被请求的源”，
  覆盖 WFA 的选择；目的的获授源序列严格轮询。
- **一般混合流量**：仍走 WFA；保证极大/不浪费，公平性为 WFA 的计数/覆盖公平，
  不是严格的每端口 RR。
- 覆盖逻辑与 WFA **并行**，`a_ptr/g_ptr` 只在覆盖生效时推进；因此关键路径仍是
  WFA；输出侧 vld/ptr 融合把 src_vld 从 35 级降到 26 级，dest_ptr 降到 34 级。

严格测试 `tb/tb_fairness.sv`：7 种形状 × 6 个场景（单源 all/even/odd，
单目的 all/even/odd）= **42/42 PASS，0 errors**。

## 6. Fair 变体（对应图 07）

`rtl/fair_arbiter_fair.v` 是独立的可选 fair 版：

1. iSLIP 首轮 grant/accept：每目的 `g_ptr`、每源 `a_ptr` 做 per-port RR；
2. 对未匹配残差跑 WFA fill：保证极大/不浪费；
3. `a_ptr/g_ptr` 在最终匹配上推进。

严格单源/单目的 42/42；fair 主回归 295,848，极大性 18/18，4 形状 soak PASS，
10x10 × 20,000 soak PASS（146,021 grants）。
多源公平的 Jain 平均值比纯 WFA 更高（10x10 持续矩阵：
src 0.819-0.834 → 0.866-0.895，dst 0.804-0.891 → 0.912-0.934）。代价是
10x10 73 级 / 5474 cells；fast 默认是 34 级 / 5925 cells。fair 版不是全流量
严格 RR 的数学保证，fill-only 端口仍是近似。

## 7. WFA 全局旋转（对应图 03）

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

# 严格单源/单目的公平（42 项）
iverilog -g2012 -s tb_fairness_top -o sim/fairness.vvp     rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp

# 极大性检查（18 种 N/M 形状）
iverilog -g2012 -s tb_maximal_top -o sim/torus_max.vvp \
    rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/torus_max.vvp

# 综合 / 深度
yosys -p "read_verilog -sv rtl/wfa_core.v rtl/fair_arbiter.v; \
          chparam -set N 10 -set M 10 fair_arbiter; \
          synth -top fair_arbiter; flatten; stat; ltp -noff"
```

RTL：`rtl/fair_arbiter.v`（默认 WFA 实现；`ITER`/`AUGMENT` 保留但被忽略）。
严格 RR 的旧 iSLIP+fill 参考实现移至 `rtl/reference/fair_arbiter_islip.v`。
