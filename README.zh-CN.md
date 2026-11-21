# 公平仲裁器（波前 / WFA 交叉开关调度器）

参数化的 N 源 × M 目的公平仲裁器：每拍产生一个**正交（一对一）**匹配，**当拍出结果**（零延迟），支持源/目的反压。默认实现是 **WFA/WWFA + 单源/单目的严格 RR 覆盖**：
- 一般混合流量 → WFA，保证极大（不浪费调度）、低深度；
- 只有一个源有请求 → 每源 `a_ptr` RR 选择器覆盖，源的目的序列严格轮询；
- 只有一个目的有请求 → 每目的 `g_ptr` RR 选择器覆盖，目的的源序列严格轮询。

**硬保证：每拍都是极大匹配（maximal matching），对任意 N/M 都成立。** 只要某个请求 `(i,j)` 的源 i 和目的 j 都空闲却没有被调度，就是错误——本设计不允许这种情况。10x10、9x11、N<M、N>M、非 2 的幂全部覆盖。

**验证汇总**：22 种配置 / 295,797 项检查全部通过；18 种 N/M 形状（2x2 ... 16x16，含 10x10）每种 773 拍，0 非极大拍、0 浪费对、0 正交违规；长跑随机 soak（4 种形状 × 1500 拍带随机反压，另加 10x10 × 20,000 拍 / 720,096 个请求瞬间）0 非极大拍、0 不变量违规；WFA 算法级脚本 94,475 例（小规模穷举 + 2..16 全形状 + 所有 δ）0 失败；严格单源/单目的公平测试 **42/42** 通过；复位 / X 态检查通过。

[English](README.md) · [WFA 电路图](diagram/circuit/README.md) · [旧 iSLIP 方案图](diagram/fair_arbiter_scheme.svg)

## 特性

- **每拍极大匹配（无浪费调度）**：P 条 torus 对角线按波前顺序访问所有 crosspoint；cell 只在 `R & N & W` 时 grant，行/列 token 随后消耗。证明见下节。
- **正交匹配**：同一对角线内一行一个、一列一个；跨对角线由 free token 保证，任何源/目的至多一次。
- **当拍出结果**：cell 是纯组合逻辑，P 级波前完成后直接输出；唯一时序元件是 δ 旋转寄存器。
- **低逻辑级数**：10x10 为 35 级（目标 ≤40），旧 iSLIP+串行 fill 为 300 级；8x8 为 28 级。
- **旋转公平**：δ 每个 grant 后 +1；P 个周期覆盖所有对角线，每个源/目的都轮获得最高优先级。计数公平、无饥饿；严格 per-port RR 顺序做了一升一降的折中。
- **反压 / 复位**：`i_src_bp` / `i_dest_bp` 组合门控；`rst_n` 异步复位；`PTR_RESET=0` 可省 δ 复位。
- **参考实现**：`rtl/reference/fair_arbiter_islip.v` 保留严格双向 RR 的 iSLIP+fill 版本，用于对比。

## 极大性保证（原理）

WFA 按 torus 对角线顺序访问每个 crosspoint 恰好一次。反证：若请求 `(i,j)` 在结束时源 i 和目的 j 都空闲，由于 free 集合只减不增，轮到 `(i,j)` 时两端也一定空闲，cell 必然 grant，矛盾。因此不存在“出口空闲、入口却不调度”的请求对——输出对任意 N/M 都是**极大匹配**。

这是极大，不是最大：某个源可能因为唯一请求的目的已被更早的对角线占用而落选，这是允许的。`scripts/verify_wfa.py` 对小规模穷举全部请求矩阵，并对 2..16 所有形状、所有 δ 做了 94,475 例检查，0 失败；`tb/tb_maximal.sv` 覆盖 18 种 N/M 形状，0 非极大、0 正交违规。

旧 iSLIP+**残余填充**参考实现用“按源串行独裁”达到同样的极大性（见 `rtl/reference/fair_arbiter_islip.v` 和 `docs/scheme.md`），保留用于严格 per-port RR 对比。

## 电路级方案图（PNG，总 / 分）

低深度 **波前仲裁器（WFA / WWFA）** 变体的电路级 PNG 图：

- [总图](diagram/circuit/wfa_00_overview.png)
- [Crosspoint cell 门级电路](diagram/circuit/wfa_01_cell.png)
- [对角线波前阵列](diagram/circuit/wfa_02_diagonal.png)
- [δ 旋转与公平性](diagram/circuit/wfa_03_rotation.png)
- [不浪费调度示例](diagram/circuit/wfa_04_nowaste.png)
- [深度 / 面积指标](diagram/circuit/wfa_05_depth.png)
- [单源/单目的严格 RR 覆盖](diagram/circuit/wfa_06_fairness.png)
- [fair 变体：iSLIP 首轮 + WFA fill](diagram/circuit/wfa_07_fair_hybrid.png)

索引与算法对比见 [diagram/circuit/README.md](diagram/circuit/README.md)。WFA RTL
（`rtl/fair_arbiter.v`，默认 RTL）是 4 调度波前 + 单侧公平覆盖，10x10 综合为 **10711 cells / 35 级**（4 个波前和覆盖逻辑并行）；单调度版本（NSCHED=1）为 5274 cells / 35 级。纯 WFA 为 2062 cells / 35 级，旧 iSLIP+fill 为 11821 cells / 300 级。一般流量是极大匹配（不浪费调度）但不是最大匹配；单源/单目的序列是严格 RR（42/42）。8x8/10x10/9x11/11x9 均 ≤40（31/35/36/38），16x16 不在本变体目标内。

## fast / fair 两个版本

两个版本的顶层接口完全一致，只是内部调度不同。

| 版本 | RTL | 单源/单目的严格 RR | 多源公平 | 10x10 PPA |
|------|-----|--------------------|----------|-----------|
| **fast（默认）** | `rtl/fair_arbiter.v` | **42/42** | 4 调度 WFA（Jain 0.89-0.93 src / 0.92-0.95 dst） | **10711 cells / 35 级** |
| **fair（可选）** | `rtl/fair_arbiter_fair.v` | **42/42** | iSLIP 首轮 + WFA fill（Jain 0.87-0.90 src / 0.91-0.93 dst） | 5119 cells / 74 级 |
| 严格参考 | `rtl/reference/fair_arbiter_islip.v` | 全流量严格 | iSLIP+串行 fill | 11821 / 300 |

### 多调度公平（面积换公平）

`rtl/fair_arbiter.v` 并行跑 `NSCHED` 个波前。第 s 个调度把 core 的行按
`r -> (c_s*r) mod N` 置换（`c_s` 与 N 互质，纯布线，无 mux），输出每 P 个授予
切换一次调度：

| 方案 | src Jain（10x10） | dst Jain（10x10） | 10x10 cells / 级数 |
|------|-------------------|-------------------|--------------------|
| NSCHED=1 | 0.819-0.834 | 0.804-0.891 | 5274 / 35 |
| NSCHED=2 | 0.851-0.876 | 0.873-0.905 | 7155 / 36 |
| **NSCHED=4（默认）** | **0.890-0.929** | **0.918-0.952** | 10711 / 35 |
| fair 变体 | 0.866-0.895 | 0.912-0.934 | 5119 / 74 |

RTL 检查 `tb/tb_jain.sv` 实测 NSCHED=4 为 0.914-0.933 src / 0.895-0.934 dst。
`NSCHED` 是参数：NSCHED=1 回到最小面积，NSCHED=2 是中间点。

fair 版验证：主回归 295,848 checks PASS；极大性 18/18；4 形状 soak × 1500
PASS；10x10 × 20,000 soak PASS（146,021 grants，0 违规）；严格公平 42/42。fair 版多源 Jain 平均（10x10 模型，3000 拍持续矩阵）：纯 WFA src
0.819-0.834 / dst 0.804-0.891；fair src 0.866-0.895 / dst 0.912-0.934。
全交叉开关两者都是 1.000。fair 版不是“全流量严格 RR”的数学保证
（fill-only 端口是近似），但它是当前单拍下最好的折中。

运行 fair 版：

```bash
iverilog -g2012 -DFAIR_DUT -s tb_top -o sim/sim_fair.vvp     rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fair_arbiter.sv
vvp sim/sim_fair.vvp

iverilog -g2012 -s tb_fairness_fair_top -o sim/fairness_fair.vvp     rtl/wfa_core.v rtl/fair_arbiter_fair.v tb/tb_fairness_fair.sv
vvp sim/fairness_fair.vvp
```

## 文件结构

```
rtl/fair_arbiter.v          顶层 WFA wrapper（原始接口不变；N、M、PTR_RESET）
rtl/wfa_core.v              内部 P 级波前核心（内部扁平接口）
rtl/fair_arbiter_fair.v    可选 fair 版（iSLIP 首轮 + WFA fill）
rtl/reference/fair_arbiter_islip.v  严格 RR 的 iSLIP+fill 参考实现
tb/tb_fair_arbiter.sv       主回归（17 场景 × 22 配置，含 10x10）
tb/tb_maximal.sv            极大性 / 正交性 / 输出一致性检查（18 种 N/M）
tb/tb_soak.sv               长跑随机 soak（数千拍 + 随机反压，含 10x10 两万拍）
tb/tb_jain.sv               RTL 上测多源 Jain（NSCHED 1/2/4）
tb/tb_fairness.sv           严格公平测试（fast 版）
tb/tb_fairness_fair.sv      严格公平测试（fair 版）
tb/tb_perf.sv               吞吐基准
tb/tb_x_check.sv            复位 / X 态检查
scripts/verify_wfa.py       WFA 算法级穷举极大性 / 正交性验证
scripts/fairness_compare.py  多源 Jain 模型：WFAx1/x2/x4 vs fair
scripts/queue_drain.py      共享队列排空模型（窗口扫描）
scripts/verify_maximal.py   旧 iSLIP+fill 参考实现的同类验证
diagram/circuit/            WFA 电路级 PNG 方案图（总 / 分）
diagram/                    旧 iSLIP 方案图 + 算法动画（SVG）
docs/scheme.md              设计原理与方案图
docs/testpoints.md          测试点分解与结果
docs/ppa.md                 综合 / PPA 报告
synth/synth.ys              Yosys 综合 / 深度扫描（WFA）
synth/synth_islip.ys        旧 iSLIP 参考实现的综合扫描
synth/synth_fair.ys         fair 变体的综合 / 深度扫描
sim/run_sim.sh              Icarus 仿真脚本
sim/run_all.sh              全套验证（主回归 + 极大性 + X 检查 + 性能 + 穷举）
```

## 仿真

需 Icarus Verilog（`iverilog`）。Windows 下用 oss-cad-suite 时，先把 `bin` 和 `lib` 加入 PATH：

```bash
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

预期输出 `RESULT: ALL CONFIGURATIONS PASSED`。

极大性检查（18 种 N/M，含 10x10，长随机 + 对抗模式）：

```bash
iverilog -g2012 -s tb_maximal_top -o sim/maximal.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp
```

长跑随机 soak（4 种形状 × 1500 拍带随机反压，另加 10x10 × 20000 拍）：

```bash
iverilog -g2012 -s tb_soak_top   -o sim/soak.vvp   rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_soak.sv
iverilog -g2012 -s tb_soak10_top -o sim/soak10.vvp rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp
vvp sim/soak10.vvp
```

严格公平测试（单源多目的 / 单目的多源，all/even/odd，7 种形状）：

```bash
iverilog -g2012 -s tb_fairness_top -o sim/fairness.vvp     rtl/wfa_core.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp
```

全套验证（主回归 + 极大性 + soak + 公平 + X + 性能 + 穷举）：

```bash
bash sim/run_all.sh
```

算法级穷举：

```bash
python scripts/verify_wfa.py
```

## 综合（PPA）

```bash
bash synth/run_synth.sh      # fast：逐形状面积/深度
bash synth/run_synth.sh fair # 可选 fair 变体
```

## 参数

| 参数 | 含义 | 默认 |
|------|------|------|
| N | 源数量（≥ 2） | 8 |
| M | 目的数量（≥ 2） | 8 |
| PTR_RESET | 0=δ 无复位（省面积），1=异步复位 | 1 |
| ITER | 旧参数，WFA 忽略（保留 TB 兼容） | 4 |
| AUGMENT | 旧参数，WFA 忽略 | 1 |

WFA 随机流量匹配规模：8x8 86%、10x10 89%、16x16 92%，N≠M 时 96-100%。这低于旧 iSLIP+augment 的 97-98%，因为 WFA 是极大而非最大匹配——这是换深度的明确取舍。旧参考实现的 `ITER`/`AUGMENT` 行为见 `docs/ppa.md`。

## 接口

```
clk, rst_n                        时钟；异步复位（低有效）
i_src_dest_req[N-1:0][M-1:0]      源 n 请求目的 m
i_src_bp[N-1:0]                   源 n 反压
i_dest_bp[M-1:0]                  目的 m 反压
o_grant_rand_vld[N-1:0][M-1:0]    命中矩阵（正交）
o_grant_src_vld[N-1:0]            源 n 是否命中
o_grant_src_ptr[N-1:0][$clog2(M)-1:0]  源 n 命中的目的号
o_grant_dest_vld[M-1:0]           目的 m 是否命中
o_grant_dest_ptr[M-1:0][$clog2(N)-1:0] 目的 m 命中的源号
```

## 许可证

[MIT](LICENSE)
