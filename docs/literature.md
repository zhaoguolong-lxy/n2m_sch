# 文献调研：Crossbar 仲裁器（DPA / WFA / 严格 RR / 深度）

> 调研时间：2026-11。范围：DPA、WFA/WWFA、iSLIP/极大匹配、严格轮询、
> 饥饿防止、仲裁器逻辑深度、NoC 分配器。共检索/筛选 70 余项，其中约 25 项
> 读了正文或详细摘要；其余为摘要/综述级比对。文献编号见文末。
>
> 本文只讨论公开文献和本项目实测，不把“项目内模型”当作文献结论。

## 0. 结论摘要

1. **完整 DPA 就是对角线扫描，功能上属于 WFA/WWFA 家族**。Hurt 等人的
   DPA 从一条最高优先级对角线开始，逐条扫完所有对角线；这与 WFA 的
   “波前”是同一个匹配过程 [5][6]。所谓“DPA 比 WFA 浅”只对**只做一层**
   的残缺 DPA 成立，不是完整 DPA 的性质 [13][14]。
2. **经典 DPA 的全局优先级旋转不提供严格 per-port RR**。它旋转的是
   “哪条对角线最高”，不是“上次授出之后的下一个目的”。单源时它和 WFA
   一样会出现“阶梯函数”：授出序列可能是 `0,2,2,5,5,5,0,0,0,0`，不是
   `0,2,5,0,2,5,...`。严格 RR 必须使用 per-port 指针（iSLIP / 一层 DPA /
   WTF）[4][21][15]。
3. **深度上 DPA 不比 WWFA 更优**。文献给出的门级延迟量级：
   WFA `(2n-1)T`、WWFA `nT`、DPA `nD` [1][4][5][6]。本项目 10x10 的
   20 级波前就是 10 个 stage x 2 级门，和 WWFA 的 `nT` 同量级；换成完整
   DPA 不会变成 10 级以内。
4. **Becker & Dally 的综合对比里，DPA 和 unroll 的周期随端口数增长最快；
   replicate（复制 n 份固定优先级波前 + n:1 选择）在 n=5/8/10 都最快，
   比第二名快 30-41%** [14]。这和我们“delta 分库”在 generic Yosys 下
   没收益的实测不矛盾：那是综合库/扇出/选择器代价的问题，值得用真实库复测。
5. **WFA 的公平性在文献里被明确称为 weak fairness**：只保证“最终会被服务”，
   不保证短期均匀；输出阻塞时仍可能饥饿 [3][4][13]。要严格单源/单目的 RR，
   必须外挂 per-port 指针（我们当前的做法）或改用 WTF 这类 per-port 分配器。
6. **wavefront+（跳过空对角线）是文献里现成的、几乎零深度的公平性改进**：
   下一条最高优先级对角线取“当前最高优先级之后第一条**有请求**的对角线”，
   而不是简单的 +1 [14][58]。TAMU 的 STORM 论文明确把它称为 wavefront+，
   并给出稀疏矩阵下“某个请求 5 拍里被授 4 次”的反例 [58]。本项目模型
   实测：K=5 循环模式，NSCHED=1 的 Jain 从 0.500 升到 **1.000**；
   NSCHED=4 从 0.812 升到 **0.930**。授权路径不变（只改 delta 的
   次态逻辑）；generic Yosys 级数在 ±2 抖动内（10×10 34→36），
   关键路径仍从 `i_dest_bp` 到 `o_grant_src_ptr`。
7. **WTF（waterfall）是文献里唯一同时声称“单拍极大匹配 + 强 RR 公平 +
   无组合环”的分配器** [15][16]。它值得做可行性研究，但它的关键路径是
   `O(n)`，且面向 homogeneous resource allocation（HRA），不是任意 N×M
   请求矩阵的直接替代品。

## 1. 问题与术语

- **极大（maximal）**：不能再加入任何一条边而不替换已有边。判定式：
  存在 `req[i][j]=1` 且 source i、destination j 都空闲，就是非极大。
- **最大（maximum）**：边数最多的匹配。极大不一定是最大；我们的硬要求是
  极大，不是最大。
- **严格 per-port RR**：
  - 单源多目的：该源授出的目的序列必须是“从上次授出的下一个目的开始，
    跳过未请求的目的”的循环。
  - 单目的多源：对称。
  - 多源多目的：每个端口各自维护指针；只有该端口实际授出时才推进。
- **same-cycle**：授权组合输出，不插入流水寄存器。因此深度是组合路径
  从 `i_src_dest_req` 到 `o_grant_*` 的级数。

文献中的 WFA/DPA 大多假设 N×N；N×M 通过补 dummy 行/列变成 P×P，
`P=max(N,M)`。本项目 `wfa_core` 采用同样的 padding。

## 2. DPA（Diagonal Priority / Propagation Arbiter）

### 2.1 Hurt 等人的 DPA

Hurt、May、Zhu、Lin 在 ICC'99 提出 high-speed symmetric crossbar
scheduler，其中包括 DPA [5]。核心事实（Keyvani 的 VHDL 实现论文转述得
更清楚 [6]）：

- 从一条对角线开始，该对角线上的所有请求可以同时授权（它们不同行、
  不同列）。
- 下一条对角线只考虑“上方和左方都还没有授权”的 cell。
- 优先级用 `2n-1` 位的向量 `P` 旋转；active window 每个时隙移动一格。
- 一个 cell 每 `n^2` 个时隙获得一次最高优先级。
- **仲裁延迟为 `nD`**（D 是单个仲裁 cell 的延迟）[6]。

### 2.2 与 WFA/WWFA 的关系

Tamir & Chi 的 WFA 从**一个**最高优先级 cell 开始，波前斜向推进，
延迟 `(2n-1)T`；WWFA 从**一整条 wrapped diagonal** 开始，延迟 `nT`，
吞吐与 WFA 基本相同 [1][2][4]。DPA 从一条对角线开始、逐条扫完，本质上
就是“把 WWFA 的波前按对角线展开”；三者是同一个对角线优先级家族。

因此：

- **完整 DPA = 扫完 P 条对角线 = 极大匹配**，这一判断是正确的。
- 一层 DPA（只算 row-best 与 col-best 的交集）**不是**完整 DPA，它是
  残缺版本；本项目 `rtl/reference/fair_arbiter_dpa.v` 明确标注为 one-layer，
  它的 21 级/22% 授权率不能当作“DPA vs WFA”的结论 [13][14]。
- 完整 DPA 的深度是 `n` 个 stage，不会比 WWFA 的 `n` 个 stage 更浅。

### 2.3 经典 DPA 的 RR 性质（重要更正）

经典 DPA 的优先级是**全局的对角线顺序**，不是 per-port 指针。对单源
`S={0,2,5}`、`P=10`，按对角线顺序扫描并每拍把 `P` 移一格（本文按 DPA
的全局优先级定义推导），授出序列是：

```
delta: 0 1 2 3 4 5 6 7 8 9
grant: 0 2 2 5 5 5 0 0 0 0
```

这不是严格 RR（0 被授 5 次、2 被授 2 次、5 被授 3 次），甚至不是统计均匀。
严格 RR 要求“授出后指针跳到刚授出的目的 +1”，序列应是 `0,2,5,0,2,5,...`。
所以：

- **经典 DPA 不能天然满足严格单源/单目的 RR**；它和 WFA 一样是全局
  对角线优先级，需要 starvation prevention [3][4]。
- 能天然满足严格 RR 的是**per-port 指针**版本：每行 `a_ptr[i]`、每列
  `g_ptr[j]`，cell 同时是行最优和列最优才授权。这已经不属于经典 DPA 的
  全局旋转，而是 iSLIP/一层 DPA 类 [21][15]。
- 本项目之前的表述“DPA 可以天然做到严格 RR”需要更正为：
  **“per-port 指针的一层 DPA 可以；经典全局旋转 DPA 不行。”**

### 2.4 一层 DPA 参考实现的定位

`rtl/reference/fair_arbiter_dpa.v` 是 per-port 指针的一层 DPA：

```
row_pick[i][j] = req[i][j] & (j == 从 a_ptr[i] 起的第一个请求)
col_pick[i][j] = req[i][j] & (i == 从 g_ptr[j] 起的第一个请求)
grant = row_pick & col_pick
```

它的严格 RR 来自 per-port 指针，不是来自 DPA 的对角线旋转。它只解决
第一层冲突，所以非极大；补一遍残差波前后就是完整扫描，深度回到 WFA
家族 [13][14]。它的价值是作为一个“浅但非极大”的对照，不是替代架构。

## 3. WFA / WWFA

### 3.1 结构与延迟

Tamir & Chi 的原始 WFA：

- 每个 crosspoint 一个仲裁 cell，`G = R & N & W`，`S = N & G`，
  `E = W & G`。
- 从单个最高优先级 cell 开始，波前斜向传播；`(i,j)` 在 `(i+j-1)T`
  后稳定，整体 `(2n-1)T`。
- 公平性用两个 `n` 位循环移位寄存器（horizontal/vertical）旋转最高
  优先级 cell；每个 cell 每 `n^2` 拍获得一次最高优先级 [1][4]。

WWFA：

- 从一整条 wrapped diagonal 开始，所有 `n` 个 cell 互不同行/列，
  第一拍就能处理 `n` 个；整体 `nT`。
- 只需一个 `n` 位循环移位寄存器指示最高优先级对角线。
- 吞吐/延迟与 WFA 基本相同，但更快，因此文献推荐 WWFA [2][4]。

本项目 `wfa_core` 是 WWFA 类的 torus 实现：请求先按 `delta` 旋转，
然后 `P` 个 stage 的 wrapped diagonal 扫描，最后逆旋转。10x10 的 20 级
波前 = 10 stage x 2 级门，与 `nT` 一致。

### 3.2 公平性与饥饿

Tamir/Chi 明确说 WFA/WWFA **不保证公平** [3][4]：

- 每个 queue 每 `n^2`（WFA）或 `n`（WWFA）拍获得一次最高优先级。
- 但如果每次它获得最高优先级时，它的目标输出都被下游阻塞，它可能永远
  发不出去；低优先级 queue 反而可能先发。
- 同步网络的解决办法：**最高优先级的非空 queue 在被授出之前保持最高
  优先级**；WFA 可以通过“top priority 被拒绝时不移动 horizontal shift
  register”实现。作者把这个叫 RR arbiter [4]。
- WWFA 更复杂：最高优先级是一条对角线（n 个 queue）。作者增加一个
  **SP（starvation priority）token ring**，在最高优先级对角线内逐个
  指向 cell；WP token ring 只有在 SP 指向的 cell 被授出后才移动。
  这保证每个 queue 最终能被服务，但不是“每次授出后跳到下一个目的”的
  严格 RR [4]。

Becker & Dally 把 WFA 的公平性总结为 **weak fairness**：只保证所有请求
最终被服务，没有更强的保证 [13]。这与我们观察到的 K=5 循环模式 Jain=0.5
一致：每个请求最终都会被服务，但短期严重不均。

### 3.3 实现变体与深度（Becker 的综合研究）

Becker & Dally 在 SC'09 和 Becker 的博士论文中比较了四种无组合环的
波前实现 [13][14]：

| 变体 | 做法 | 延迟趋势 |
|------|------|----------|
| unroll | 把 P 种优先级的波前展开成无环逻辑 | 随 n 增长最快之一 |
| rotate | 固定优先级波前 + 输入/输出 barrel shifter | n=5 比 DPA/unroll 慢 11%，n>=8 反超 |
| replicate | n 份固定优先级波前并行 + n:1 选择 | **最快，比第二名快 30-41%** |
| DPA | 对角线传播 | 随 n 增长最快之一 |

原文结论（Becker 博士论文 §3.5.2）：

- "cycle time grows more quickly for the DPA and the unrolled implementation
  as the number of ports increases than for the two other implementations."
- "the replication-based implementation is the fastest across all three design
  points, outperforming the closest competitor in each case by 30-41%."
- n=5 时 rotate 比 DPA/unroll 慢 11%，但 n>=8 时 rotate 更好 [14]。

这条对我们很关键：**“DPA 更浅”在 ASIC 综合里不成立；在 8-10 端口，
replicate 才是最浅的**。我们之前的 delta 分库实验（10 份固定旋转波前 +
10:1 选择）在 generic Yosys 下是 35 级 vs 35 级，没有收益；但 Becker 的
结果是 ASIC 流程，且明确说 replicate 的面积开销换来最低周期。**需要用
用户的真实综合库/时序约束复测**，不能再用 generic 级数下结论。

### 3.4 组合环与 STA

Dimitrakopoulos 等指出：centralized wavefront allocator 的延迟随请求数
线性增长，而且其结构固有的**组合环**会禁止静态时序分析（STA）；要消除
组合环，只能把延迟再翻倍 [34]。这解释了为什么我们的 torus/rotate 实现
要付出输入/输出旋转的代价：它是无环的，可 STA，但多了旋转器。

### 3.5 PWWFA

Olesinski/Eberle/Gura 的 PWWFA 用多个 subscheduler 并行处理多个未来的
时隙，适合 large switch 的吞吐，不是“同一拍组合输出”的低延迟方案 [10]。
后续 PWWFA-FS 增加 fast secondary allocator 来修补轻载高延迟 [13]。
与我们的 same-cycle 需求不直接相关，但可以作为“多拍调度”的对照。

## 4. 严格 RR 的可行机制

### 4.1 iSLIP（per-port 指针的标准做法）

McKeown 的 iSLIP [21]：

- 每个 output 一个 grant pointer，每个 input 一个 accept pointer。
- Grant：output 从 pointer 开始选第一个请求；Accept：input 从 pointer
  开始选第一个 grant。
- Pointer 只在**第一轮迭代**更新，且只移动到“授出位置 +1”。后续迭代
  不更新，否则会出现饥饿（论文 Fig.15 的例子）[21]。
- 单轮 iSLIP 不是极大匹配；需要多轮迭代，或者像我们的 fair 变体那样
  用 WFA 补残差 [21][31]。

iSLIP 的 per-port 指针正是“严格单源/单目的 RR”的标准答案；缺点是
grant/accept 是多拍迭代（或展开后很深的组合逻辑），单拍极大需要额外的
fill。我们的 fast 变体把 per-port 指针做成与 WFA 并行的 override，就是
在“严格 RR”和“单拍极大”之间取折中。

### 4.2 WTF（waterfall）——唯一同时声称极大 + 强 RR + 无环的

Liu、Jantsch、Lu 的 WTF allocator [15][16]：

- 面向 homogeneous resource allocation（HRA）。
- **单拍极大匹配 + 基于 RR 的强公平**。
- **loop-free 结构**，90nm 下约 1GHz。
- 与 wave-front、separable-input-first、separable-output-first 相比：
  至少小 10%，高负载下延迟低 50%，功耗低 3%，公平性至少不差。
- 4x4 circuit-switched NoC 中网络性能高 20%。

但要注意：

- 论文的关键路径是 `O(n)`；作者在博士论文的 future work 里明确说
  “critical timing path scales up with O(n) ... explore techniques which can
  reduce it to O(log(n))” [16]。所以它不是“浅”，只是“无环 + 公平”。
- HRA 的请求结构是“每个 requester 请求一组同质资源”，不一定等价于
  任意 N×M 的 crossbar 请求矩阵；直接套到我们的任意矩阵需要验证。
- 没有公开 RTL。

结论：**WTF 是唯一值得做可行性研究的“另一种架构”**，但它不是现成的
drop-in；如果 wavefront+ 和 replicate/MARX 能把 35 级压到目标，优先级
应低于这两者。

**本项目 WTF-style 原型实测**（`rtl/fair_arbiter_wtf.v`，iSLIP 首轮 +
行串行 waterfall fill；不是论文的逐门复刻）：

| 变体 | 8x8 cells/levels | 10x10 cells/levels | 公平性 / 备注 |
|------|------------------|--------------------|----------------|
| iSLIP 首轮 + 逐行 a_ptr fill（`SIMPLE_FILL=0`） | 3094 / 122 | 6802 / 186 | K 1.000（NS1），随机 0.910-0.923 |
| **iSLIP 首轮 + 固定顺序简单 fill（默认）** | **2007 / 58** | **3387 / 70** | **K 1.000，随机 0.876-0.920** |
| 仅首轮（`FILL=0`） | 1467 / 27 | 2564 / 32 | 394/476 非极大 |
| 仅贪心 base（`FIRST_PASS=0`） | 552 / 31 | 880 / 38 | 多源严重不均 |
| 贪心 base + 并行 override | 1976 / 34 | 3630 / 39 | K 0.125-0.333，随机 ~0.23 |

优化方法：**把 per-port RR 完全交给 iSLIP 首轮，fill 只负责极大性**。
因此 fill 不需要 per-row `a_ptr`，也不需要旋转起始行；每行只做
“最低索引的空闲请求目的”这一个固定顺序贪心。这样每行从
“指针选择 + 比较器 + priority encoder + free 更新”降为
“AND + 最低置位 + free 更新”，深度和面积都大约减半：

- 8x8：122 -> 58 级，3094 -> 2007 cells；
- 10x10：186 -> 70 级，6802 -> 3387 cells；
- 42/42 严格 RR、18/18 极大性、K-regular Jain 1.000 全部保留。

但 70 级仍然是当前 WFA 35 级的两倍。反过来，如果去掉 iSLIP 首轮、
只做贪心 + 并行 override，深度可以到 39 级（10x10），但多源 Jain
掉到 0.125-0.333——固定顺序贪心会一直服务同一批低索引 pair。这说明
**iSLIP 首轮是 WTF-style 公平性的关键，不能省**；70 级是“公平 + 极大”
的可综合版本的下限。

论文的 90nm 1GHz 依赖其未公开的 cell 级 waterfall 结构；按“逐行
priority encoder”直接复现只能到 70 级，不能按行贪心直接做到 1GHz。
这个原型验证了 WTF 的公平性承诺，但也说明它**不是**当前架构的深度
替代品；它更适合作为“面积/公平性优先”的备选（3387 cells / 70 levels
vs WFA 10711 cells / 35 levels）。

### 4.3 饥饿防止（starvation-free）与严格 RR 的区别

Chi & Tamir 的 SP token ring [4] 保证“最终被服务”，但不保证“每次授出后
跳到下一个目的”的严格顺序。对单源，SP 机制会让被阻塞的目的保持最高
优先级直到被服务，期间源仍可能用低优先级目的发出；这不是严格 RR。
我们的 override 是在每个源/目的上独立维护“下一个起点”，因此更强，
代价是并行指针矩阵 + 输出 2:1 选择。

文献里另一类做法是 age-based / distance-based / group allocation /
weighted RR [44]-[51]，它们解决的是**全局公平**（跨 hop、跨 flow），
不是单拍 crossbar 的 per-port RR；需要 per-packet 年龄或额外状态，
不适合我们的接口。

### 4.4 wavefront+（跳过空对角线）

Becker 在博士论文 §3.3.1 提出一种修改的优先级更新；TAMU 的 Rasheed
在 STORM 论文中把它命名为 **wavefront+** [14][58]：

> "the highest priority diagonal for the next cycle is the one following the
> current top priority one which had any requests at all (and not necessarily
> the immediate successor of the current top priority diagonal)."

也就是说，`delta` 不是简单 +1，而是：

1. 从当前 `delta` 开始，找到第一条**有请求**的对角线（stage d）；
2. 下一拍的 `delta = delta + d + 1`。

Becker 还给出稀疏矩阵的反例：简单 +1 会让某个请求 5 拍里被授 4 次；
wavefront+ 可以修复 [58]。

这和 GPGPU-Sim/BookSim 的 `_skip_diags` 优化是同一类：
`_pri = first_diag + 1`，其中 `first_diag` 是本次扫描第一个产生授权的
对角线 [65]。

**本项目模型实测（不是文献数字）**：10x10，K-regular 循环模式，
persistent 请求，2000 拍：

| K | 模式 | WFAx1 | WFAx1 + wavefront+ | WFAx4 | WFAx4 + wavefront+ |
|---|------|-------|--------------------|-------|--------------------|
| 8 | circ | 0.781 | **1.000** | 0.935 | 0.937 |
| 5 | circ | 0.500 | **1.000** | 0.812 | **0.930** |
| 3 | circ | 0.505 | **1.000** | 0.771 | **0.898** |

随机 10x10、9x11 模式：没有变化（因为最高优先级对角线几乎总有请求）。
11x9：没有变化（N>M 的结构性不均衡是另一个问题）。

RTL 已实现（`WAVEFRONT_PLUS=1` 默认）：K=8/5/3 的 NS1 都是 1.000，
NS4 分别是 0.943/0.930/0.899，与模型一致；42/42 严格 RR 和 18/18 极大性
保持。详见 `docs/ppa.md`。

实现代价：

- 只为当前选中的 schedule 计算 `stage_present[d]`（d=0..P-1）：
  对每个 stage，把该 stage 上所有行的请求 OR 起来。
- 再用一个 cyclic priority encoder 找 `delta` 之后第一个 set 的 stage。
- `delta` 次态从“+1”变成“+d+1”；授权路径
  （mask -> rotation -> wavefront -> inverse rotation -> output）完全不变。
- `delta` 次态路径约 `log P + mux` 级，远低于 30+ 级的授权路径；
  不会成为关键路径（需要用综合确认）。
- 面积约 `NSCHED * P * N` 个 OR 项 + 一个 P 位优先级编码器；
  相对 10x10 的 10711 cell 很小。

这是目前**性价比最高的公平性改进**：模型上把最差的 K=5 从 0.500 拉到
1.000（NS1）/ 0.930（NS4），深度不变。

## 5. 深度/面积证据汇总

| 机制 | 文献延迟量级 | 备注 |
|------|--------------|------|
| WFA | `(2n-1)T` | 单 cell 起扫 [1][4] |
| WWFA | `nT` | 整条 wrapped diagonal 起扫 [1][4] |
| DPA | `nD` | 逐条对角线扫 [5][6] |
| WTF | `O(n)` | 无环，90nm ~1GHz [15][16] |
| iSLIP | 迭代次数 x (grant+accept) | 单轮非极大 [21] |
| PPA（1-of-N） | `log2(n)+1` 级 | 并行前缀 [32] |
| FSA（树形公平仲裁） | `O(log4 N)` | 2022，比现有公平结构低 22.2% [51] |
| MARX（仲裁+选择合并） | 比独立 arb+mux 低 | 65nm [33][34] |
| replicated WFA | 最快，比第二名快 30-41% | n=5/8/10 [14] |

本项目 10x10 的 35 级构成（实测）：

```
mask                 2
input rotation       4
wavefront           20   (P=10 stage x 2 gate)
inverse rotation     4
output/vld/ptr       5
----------------------------
total               35
```

对应文献：

- 20 级波前 = WWFA 的 `nT`，T=2 级门；如果库里有 AOI21，cell 可以
  1 级门，波前 20 -> 10，整体约 25 级。这是**单点最大收益**，但依赖库。
- 输入/输出旋转 8 级是 torus/rotate 实现的价格；Becker 的 rotate 变体
  也有这个价格（n=5 慢 11%，n>=8 反超）[14]。
- replicate 去掉旋转，但加 n:1 选择和输入扇出；Becker 的 ASIC 结果说
  它最快 [14]。我们的 delta 分库实验在 generic Yosys 下是 35 vs 35，
  需要用真实库复测。
- 输出 5 级里包含 RR override 的 2:1 选择（约 2 级）。MARX 的
  “仲裁与 mux 合并”是文献里针对这 2 级的做法 [33][34]；FSA 的树形
  公平仲裁可以把 1-of-N 的 RR pick 降到 O(log4 N)，但我们的 RR pick
  本来就在关键路径之外，真正花 depth 的是最后的选择器 [51]。

## 6. 对“DPA vs 当前 WFA”的逐条回答

### Q1：为什么 WFA 做不到严格轮询？

WFA 的优先级是一个全局旋转 `delta`。源 i 的目的顺序是
`(i+delta),(i+delta+1),...`；它授出“从这个起点开始的第一个请求”。
这个映射是阶梯函数：delta 每次 +1，连续几个 delta 会映射到同一个目的。
单源 `S={0,2,5}` 的例子就是 `0,2,2,5,5,5,0,0,0,0`。严格 RR 要求
“授出后起点跳到授出目的 +1”，这必须 per-port 维护，不能靠全局 delta。
文献把 WFA 的公平性定为 weak fairness，并明确说输出阻塞时可能饥饿
[3][4][13]。

### Q2：DPA 可以吗？

- **经典 DPA（全局对角线旋转）不可以**，理由同上；它和 WFA 是同一个
  全局优先级家族。
- **per-port 指针的一层 DPA 可以**做到单源/单目的严格 RR（我们的
  `fair_arbiter_dpa.v` 42/42 通过），但它是 per-port 指针的功劳，不是
  DPA 的对角线旋转；而且它只做一层，不极大。
- **完整 DPA** 要扫完所有对角线，功能上就是 WFA/WWFA；此时它仍然是
  全局对角线优先级，不会自动获得严格 per-port RR。

### Q3：DPA 是否更优？

在“完整扫描 + 极大匹配”这个 apples-to-apples 比较下：

- 深度：DPA `nD`，WWFA `nT`，同量级；DPA 不会更浅。
- ASIC 综合：Becker 的数据显示 DPA 的周期随 n 增长更快；n=10 时
  replicate WFA 快 30-41% [14]。
- 一层 DPA 的 21 级很浅，但它不极大；22% 的授权率不能作为完整 DPA
  的性能。
- 所以“换 DPA 降深度”在文献里没有依据；除非我们接受非极大，或者
  采用 WTF 这类完全不同的 per-port 结构。

### Q4：当前 35 级的构成与文献对比

35 级 = mask 2 + input rotation 4 + wavefront 20 + inverse rotation 4 +
output 5。文献的 WWFA 是 `nT`；我们的 20 级波前正是 n=10、T=2 级门。
DPA 的 `nD` 也是 10 个 cell 延迟，不会变成 10 级以内。旋转器和输出
选择是“无环 + 同拍输出”的固有价格；replicate/MARX 是文献里针对这两项
的优化方向。

### Q5：可落地的优化排序（按深度 > 性能 > 面积/功耗）

1. **wavefront+**：只改 delta 次态；模型上修复 K=5 的 0.500 -> 1.000
   （NS1）/ 0.930（NS4）；授权路径不变。**建议先做这个**。
2. **真实库复测 replicate WFA 和 MARX 输出合并**：Becker 说 replicate
   最快，Dimitrakopoulos 说合并 arb+mux 能省延迟；我们的 generic 结果
   不可靠。需要用户的综合库、目标时钟、AOI21/MUX2 可用性。
3. **AOI21 波前 cell**：20 -> 10 级，整体约 25 级；这是单点最大收益，
   但完全依赖库。
4. **WTF 可行性**：唯一同时声称极大 + 强 RR + 无环的替代架构；但
   `O(n)` 深度、HRA 限定、无公开 RTL。作为“如果 1-3 还不够”的后备。
5. **温度计编码 RR 指针**：纯面积收益（约 -300~400 门），深度不变；
   文献里标准 RR 指针就是温度计码 [33]。

## 7. 本项目模型实验：wavefront+ 细节

模型：`scripts/fairness_compare.py` 的 WFA 匹配 + K-regular 请求矩阵；
persistent 请求，2000 拍；Jain 指数按源的目的计数平均。

三种 delta 更新：

- `none`：`delta = delta + 1`（当前 RTL）。
- `stage`：按当前 schedule 的扫描 stage 计算“第一条有请求的对角线”，
  `delta = delta + d + 1`（wavefront+ 的正确实现）。
- `orig`：按原始 `(j-i) mod P` 对角线计算，忽略 row permutation；
  更省面积，但 NSCHED=4 时效果弱一些（K=5 0.893 vs 0.930）。

结果（src Jain）：

| K | none NS1 | stage NS1 | orig NS1 | none NS4 | stage NS4 | orig NS4 |
|---|----------|-----------|----------|----------|-----------|----------|
| 8 | 0.781 | 1.000 | 1.000 | 0.935 | 0.937 | 0.897 |
| 5 | 0.500 | 1.000 | 1.000 | 0.812 | 0.930 | 0.893 |
| 3 | 0.505 | 1.000 | 1.000 | 0.771 | 0.898 | 0.784 |

随机 10x10 / 9x11：三种更新结果相同（最高优先级对角线几乎总有请求）。
11x9：三种更新结果相同，Jain 仍偏低（N>M 的结构性不均衡）。

结论：wavefront+ 对“对角线对齐的窄带模式”是特效药；对随机流量无副作用；
建议 RTL 实现 `stage` 版本（NSCHED=4 时收益最大），而不是省面积的
`orig` 近似。

## 8. 参考文献

> 说明：以下 60 余项按主题分组；标 * 的为本项目直接精读/引用了正文的
> 文献，其余为摘要/综述级比对。

### 8.1 DPA / WFA / WWFA

[1]* Y. Tamir, H.-C. Chi, "Symmetric Crossbar Arbiters for VLSI Communication
Switches," IEEE Trans. Parallel and Distributed Systems, 4(1):13-27, 1993.
DOI 10.1109/71.205650.

[2]* H.-C. Chi, Y. Tamir, "Decomposed Arbiters for Large Crossbars with
Multi-Queue Input Buffers," ICCD 1991, pp.233-238.
DOI 10.1109/ICCD.1991.139888.

[3]* H.-C. Chi, Y. Tamir, "Starvation Prevention for Arbiters of Crossbars with
Multi-Queue Input Buffers," COMPCON 1994, pp.292-297.
DOI 10.1109/CMPCON.1994.282896.

[4]* H.-C. Chi, "Crossbar Arbitration in Interconnection Networks for
Multiprocessors and Multicomputers," PhD thesis, UCLA, 1994.

[5]* J. Hurt, A. May, X. Zhu, B. Lin, "Design and Implementation of High-Speed
Symmetric Crossbar Schedulers," IEEE ICC 1999, pp.253-258.
DOI 10.1109/ICC.1999.765457.

[6]* M. Keyvani, "VHDL Implementation of a High-Speed Symmetric Crossbar
Switch," MSc thesis, Simon Fraser University, 2001.

[7] J. G. Delgado-Frias, G. B. Ratanpal, "A VLSI Wrapped Wave Front Arbiter for
Crossbar Switches," ACM GLSVLSI 2001. DOI 10.1145/368122.369605.

[8] J. G. Delgado-Frias, G. B. Ratanpal, "A VLSI Crossbar Switch with Wrapped
Wave Front Arbitration," IEEE Trans. Circuits and Systems I, 50(1):135-141,
2003. DOI 10.1109/TCSI.2002.807518.

[9] G. L. Gopalakrishnan, "Developing Micropipeline Wavefront Arbiters," IEEE
Design & Test of Computers, 11(4):55-64, 1994. DOI 10.1109/54.329456.

[10]* W. Olesinski, H. Eberle, N. Gura, "PWWFA: The Parallel Wrapped Wave Front
Arbiter for Large Switches," IEEE HPSR 2007.
DOI 10.1109/HPSR.2007.4281223.

[11] W. Olesinski, H. Eberle, N. Gura, "Parallel Wrapped Wave-Front Arbiter,"
US Patent 8,145,823 B2, 2012.

[12] H. Eberle, N. Gura, W. Olesinski, A. Mejia, "Low-Latency Scheduling in
Large Switches," US Patent 7,912,068 B2, 2011.

[13]* D. U. Becker, W. J. Dally, "Allocator Implementations for Network-on-Chip
Routers," ACM/IEEE SC 2009. DOI 10.1145/1654059.1654112.

[14]* D. U. Becker, "Efficient Microarchitecture for Network-on-Chip Routers,"
PhD thesis, Stanford University, 2012.

[15]* S. Liu, A. Jantsch, Z. Lu, "A Fair and Maximal Allocator for Single-Cycle
On-Chip Homogeneous Resource Allocation," IEEE TVLSI, 22(10):2229-2233, 2014.
DOI 10.1109/TVLSI.2013.2284563.

[16]* S. Liu, "New Circuit Switching Techniques in On-Chip Networks," PhD thesis,
KTH Royal Institute of Technology, 2015.

[17] M. A. Khan, A. Q. Ansari, "Design of 8-Bit Programmable Crossbar Switch for
Network-on-Chip Router," WeST/NeCoM 2011, CCIS 197:526-535.
DOI 10.1007/978-3-642-22543-7_54.

[18] S. A. Ganiee, S. A. Ganiee, J. R. Dar, "FPGA Design of 8 bit 4x4 Crossbar
Switch for Multi Processor System on Chip Using Round Robin Arbitration
Algorithm," IJAREEIE, 4(1), 2015.

[19] A. M. Legkikh, "Comparison Round Robin and Wrapped Wavefront Arbitration
Algorithms Characteristics on the Example of the Arbitration of the Crossbar
Switch," ElConRus 2022. DOI 10.1109/ElConRus54750.2022.9755559.

[20] V. Dvorak, P. Mikusek, "LUT Cascade-Based Implementation of Allocators,"
IEEEI 2008, pp.85-89.

### 8.2 iSLIP / 匹配 / 调度

[21]* N. McKeown, "The iSLIP Scheduling Algorithm for Input-Queued Switches,"
IEEE/ACM Trans. Networking, 7(2):188-201, 1999. DOI 10.1109/90.769767.

[22] T. E. Anderson, S. S. Owicki, J. B. Saxe, C. P. Thacker, "High Speed Switch
Scheduling for Local Area Networks," ACM Trans. Computer Systems,
11(4):319-352, 1993.

[23] P. Gupta, N. McKeown, "Designing and Implementing a Fast Crossbar
Scheduler," IEEE Micro, 19(1):20-28, 1999. DOI 10.1109/40.748793.

[24] N. McKeown, M. Izzard, A. Mekkittikul, W. Ellersick, M. Horowitz, "Tiny
Tera: A Packet Switch Core," IEEE Micro, 17(1):26-33, 1997.

[25] N. McKeown, V. Anantharam, J. Walrand, "Achieving 100% Throughput in an
Input-Queued Switch," IEEE Trans. Communications, 47(8):1260-1267, 1999.

[26] A. Mekkittikul, N. McKeown, "A Starvation-Free Algorithm for Achieving
100% Throughput in an Input-Queued Switch," ICCCN 1996.

[27] D. N. Serpanos, P. I. Antoniadis, "FIRM: A Class of Distributed Scheduling
Algorithms for High-Speed ATM Switches with Multiple Input Queues," IEEE
INFOCOM 2000. DOI 10.1109/INFCOM.2000.832228.

[28] W. Wang, L. Dong, W. Wolf, "iSKIP: A Fair and Efficient Scheduling
Algorithm for Input-Queued Crossbar Switches," IEEE GLOBECOM 2002.
DOI 10.1109/GLOCOM.2002.1189039.

[29] M. J. Karol, M. G. Hluchyj, S. P. Morgan, "Input Versus Output Queueing on
a Space-Division Packet Switch," IEEE Trans. Communications, 35(12):1347-1356,
1987. DOI 10.1109/TCOM.1987.1096719.

[30] W. J. Dally, "Virtual-Channel Flow Control," IEEE Trans. Parallel and
Distributed Systems, 3(2):194-205, 1992.

[31] W. J. Dally, B. Towles, "Principles and Practices of Interconnection
Networks," Morgan Kaufmann, 2004.

### 8.3 仲裁器电路 / 深度

[32]* G. Dimitrakopoulos, N. Chrysos, K. Galanopoulos, "Fast Arbiters for
On-Chip Network Switches," IEEE ICCD 2008, pp.664-670.
DOI 10.1109/ICCD.2008.4751932.

[33]* G. Dimitrakopoulos, E. Kalligeros, "Dynamic-Priority Arbiter and
Multiplexer Soft Macros for On-Chip Networks Switches," DATE 2012.
DOI 10.1109/DATE.2012.6176527.

[34]* G. Dimitrakopoulos, E. Kalligeros, K. Galanopoulos, "Merged Switch
Allocation and Traversal in Network-on-Chip Switches," IEEE Trans. Computers,
62(10):2001-2012, 2013. DOI 10.1109/TC.2012.116.

[35] N. Chrysos, G. Dimitrakopoulos, "Practical High-Throughput Crossbar
Scheduling," IEEE Micro, 29(4):22-35, 2009. DOI 10.1109/MM.2009.55.

[36] N. Chrysos, G. Dimitrakopoulos, "Backlog-Aware Crossbar Schedulers: A New
Algorithm and Its Efficient Hardware Implementation," IEEE HOTI 2008,
pp.67-74. DOI 10.1109/HOTI.2008.18.

[37] L.-S. Peh, W. J. Dally, "A Delay Model for Router Microarchitectures,"
IEEE Micro, 21(1):26-34, 2001. DOI 10.1109/40.903059.

[38] L.-S. Peh, W. J. Dally, "A Delay Model and Speculative Architecture for
Pipelined Routers," IEEE HPCA 2001, pp.255-266.
DOI 10.1109/HPCA.2001.903268.

[39] E. S. Shin, V. J. Mooney III, G. F. Riley, "Round-Robin Arbiter Design and
Generation," ISSS 2002. DOI 10.1109/ISSS.2002.1227185.

[40] H. F. Ugurdag, O. Baskirt, "Fast Parallel Prefix Logic Circuits for n2n
Round-Robin Arbitration," Microelectronics Journal, 43(8):573-581, 2012.
DOI 10.1016/j.mejo.2012.04.005.

[41] J. M. Jou, Y.-L. Lee, "An Optimal Round-Robin Arbiter Design for NoC,"
Journal of Information Science and Engineering, 26(6):2047-2058, 2010.

[42] Y.-L. Lee, J. M. Jou, Y.-Y. Chen, "A High-Speed and Decentralized Arbiter
Design for NoC," IEEE AICCSA 2009, pp.350-353.
DOI 10.1109/AICCSA.2009.5069347.

[43] G. Dimitrakopoulos, C. Kachris, E. Kalligeros, "Scalable Arbiters and
Multiplexers for On-FPGA Interconnection Networks," FPL 2011.
DOI 10.1109/FPL.2011.26.

### 8.4 公平性 / QoS

[44] D. Abts, D. Weisser, "Age-Based Packet Arbitration in Large-Radix k-ary
n-cubes," ACM/IEEE SC 2007. DOI 10.1145/1362622.1362630.

[45] M. M. Lee, J. Kim, D. Abts, M. Marty, J. W. Lee, "Probabilistic
Distance-Based Arbitration: Providing Equality of Service for Many-Core CMPs,"
IEEE/ACM MICRO 2010. DOI 10.1109/MICRO.2010.18.

[46] M. M. Lee, J. Kim, D. Abts, M. Marty, J. W. Lee, "Approximating Age-Based
Arbitration in On-Chip Networks," PACT 2010.
DOI 10.1145/1854273.1854359.

[47] S.-J. Miao, Y. Hsu, "Group Allocation: A Novel Fairness Mechanism for
On-Chip Network," IEEE NESEA 2011.
DOI 10.1109/NESEA.2011.6144932.

[48] S.-J. Miao, Y. Men, Y. Hsu, "Achieving Global Fairness for On-Chip Network
Using Group Allocation," IEEE IPDPSW 2012.
DOI 10.1109/IPDPSW.2012.114.

[49] H. Park, K. Choi, "Adaptively Weighted Round-Robin Arbitration for Equality
of Service in a Many-Core Network-on-Chip," IET Computers & Digital Techniques,
10(1):37-44, 2016. DOI 10.1049/iet-cdt.2015.0049.

[50] S. K. Mandal, J. Tong, R. Ayoub, M. Kishinevsky, A. Abousamra, U. Y. Ogras,
"Theoretical Analysis and Evaluation of NoCs with Weighted Round-Robin
Arbitration," arXiv:2108.09534, 2021/2023.

[51] J. Luo, W. Wu, Q. Xing, M. Xue, "A Low-Latency Fair-Arbiter Architecture
for Network-on-Chip Switches," Applied Sciences, 12(23):12458, 2022.
DOI 10.3390/app122312458.

### 8.5 NoC 分配器 / 路由器

[52] A. Monemi, C. Y. Ooi, M. N. Marsono, "Low Latency Network-on-Chip Router
Microarchitecture Using Request Masking Technique," International Journal of
Reconfigurable Computing, 2015:570836. DOI 10.1155/2015/570836.

[53] G. Michelogiannakis, N. Jiang, D. U. Becker, W. J. Dally, "Packet
Chaining: Efficient Single-Cycle Allocation for On-Chip Networks," IEEE
Computer Architecture Letters, 10(2):33-36, 2011. DOI 10.1109/L-CA.2011.15.

[54] Y.-Y. Chang, Y. S.-C. Huang, M. Poremba, V. Narayanan, Y. Xie, C.-T. King,
"TS-Router: On Maximizing the Quality-of-Allocation in the On-Chip Network,"
IEEE HPCA 2013, pp.390-399. DOI 10.1109/HPCA.2013.6522335.

[55] L. Liu, Y. Sun, Z. Zhu, Y. Yang, "A Congestion-Aware OE Router Employing
Fair Arbitration for Network-on-Chip," J. Semiconductors, 39(12):125006, 2018.
DOI 10.1088/1674-4926/39/12/125006.

[56] A. Mirhosseini, M. Sadrosadati, F. Aghamohammadi, M. Modarressi,
H. Sarbazi-Azad, "BARAN: Bimodal Adaptive Reconfigurable-Allocator
Network-on-Chip," ACM Trans. Parallel Computing, 5(3):11, 2019.
DOI 10.1145/3294049.

[57] J. Debbarma, R. Banik, D. Debbarma, "Energy-Efficient Network-on-Chip
Routers Using a Power Gated Round Robin Arbiter Ensuring Minimal Impact on
Latency," Results in Engineering, 28:108148, 2025.
DOI 10.1016/j.rineng.2025.108148.

[58] S. Rasheed, "A Network-on-Chip Router for Low-Latency and High-Throughput
Dimension-Order Routing," MSc thesis, Texas A&M University, 2014.
（wavefront+ 的命名与定义）

[59] J. Kim, W. J. Dally, B. Towles, A. K. Gupta, "Microarchitecture of a
High-Radix Router," ISCA 2005, pp.420-431.
DOI 10.1109/ISCA.2005.35.

[60] S. Scott, D. Abts, J. Kim, W. J. Dally, "The BlackWidow High-Radix Clos
Network," ISCA 2006, pp.16-28. DOI 10.1109/ISCA.2006.40.

[61] A. Galles, "Spider: A High-Speed Network Interconnect," IEEE Micro,
17(1):34-39, 1997.

[62] W. J. Dally, B. Towles, "Route Packets, Not Wires: On-Chip Interconnection
Networks," DAC 2001, pp.684-689. DOI 10.1109/DAC.2001.935594.

[63] US Patent Application 2006/0095634 A1, "Method and Apparatus for Round
Robin Resource Arbitration with a Fast Request to Grant Response," 2006.

[64] US Patent 9,906,440 B2, "Arbitrating and Multiplexing Circuitry," 2018.

[65] GPGPU-Sim / BookSim, `wavefront.cpp` (`_skip_diags` priority update),
  https://github.com/accel-sim/gpgpu-sim_distribution

### 8.6 补充（摘要级）

[66] M. A. Khan, A. Q. Ansari, "Area-Efficient Programmable Arbiter for
Interlayer Communications in 3-D Network-on-Chip," 2013.

[67] A. Monemi, C. Y. Ooi, M. Palesi, M. N. Marsono, "Ping-Lock Round Robin
Arbiter," Microelectronics Journal, 2017.

[68] A. K. Karanpuria, "Fair Chance Round Robin Arbiter," International Journal
of Computer Applications, 81(14), 2013.

[69] J. Lee, et al., "HCF: A Starvation-Free Practical Algorithm for Maximizing
Throughput in Input-Queued Switches," HPSR 2005.
DOI 10.1109/HPSR.2005.1503196.

[70] "Index-Based Round-Robin Arbiter for NoC Routers," ISVLSI 2015.
DOI 10.1109/ISVLSI.2015.27.

---

## 9. 对当前项目的直接影响（待办）

1. **先实现 wavefront+**（`stage` 版本），用 `tb/tb_jain.sv` 的 MODE=1
   复测 K=5/K=3，并跑 `sim/run_all.sh` 全回归；预期不影响极大性和
   严格 RR。
2. **更正文档/注释**：经典 DPA 的全局旋转不提供严格 per-port RR；
   “DPA 可以严格 RR”只适用于 per-port 指针版本。
3. **用真实综合库复测**：
   - replicate WFA（Becker 最快，30-41%）；
   - MARX 合并 arbiter+mux（省输出级）；
   - AOI21 波前 cell（20 -> 10 级）。
   generic Yosys 的 `ltp -noff` 不足以判断这些。
4. **WTF 可行性**：先确认 HRA 是否能覆盖任意 N×M 请求矩阵；如果不能，
   只提取“逐行瀑布”的思想做一个小原型，不直接替换。
5. **温度计编码 RR 指针**：纯面积优化，等深度方案定型后再做。
