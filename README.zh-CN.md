# 公平仲裁器（波前 / WFA 交叉开关调度器）

参数化的 N 源 × M 目的公平仲裁器：每拍产生一个**正交（一对一）**匹配，**当拍出结果**（零延迟），支持源/目的反压。默认实现是 **replicate/bank 波前（P 个固定 δ 的 WFA 核并行 + one-hot bank 选择）+ 单源/单目的严格 RR 覆盖**：
- 一般混合流量 → bank WFA，保证极大（不浪费调度）、低深度；
- 只有一个源有请求 → 每源 `a_ptr` RR 选择器覆盖，源的目的序列严格轮询；
- 只有一个目的有请求 → 每目的 `g_ptr` RR 选择器覆盖，目的的源序列严格轮询。

**硬保证：每拍都是极大匹配（maximal matching），对任意 N/M 都成立。** 只要某个请求 `(i,j)` 的源 i 和目的 j 都空闲却没有被调度，就是错误——本设计不允许这种情况。10x10、N<M、N>M、非 2 的幂全部覆盖；默认回归上限为 10x10。

**验证汇总**：17 种配置 / 192,860 项检查全部通过；11 种 N/M 配置（2x2 ... 10x10，含 3 个 10x10 变体）每种 773 拍，0 非极大拍、0 浪费对、0 正交违规；长跑随机 soak（3 种配置，最大 10x10，× 1500 拍带随机反压，另加 10x10 × 20,000 拍 / 720,096 个请求瞬间）0 非极大拍、0 不变量违规；WFA 算法级脚本 94,475 例（小规模穷举 + 2..16 全形状 + 所有 δ）0 失败；默认 bank 的严格单源/单目的公平测试 **24/24** 通过；复位 / X 态检查通过。

[English](README.md) · [WFA 电路图](diagram/circuit/README.md) · [旧 iSLIP 方案图](diagram/fair_arbiter_scheme.svg)

## 特性

- **每拍极大匹配（无浪费调度）**：P 条 torus 对角线按波前顺序访问所有 crosspoint；cell 只在 `R & N & W` 时 grant，行/列 token 随后消耗。证明见下节。
- **正交匹配**：同一对角线内一行一个、一列一个；跨对角线由 free token 保证，任何源/目的至多一次。
- **当拍出结果**：cell 是纯组合逻辑，P 级波前完成后直接输出；唯一时序元件是 δ 旋转寄存器。
- **低逻辑级数**：10x10 为 30 级（≤35），8x8 为 26 级；旧旋转 WFA 为 35 级，旧 iSLIP+串行 fill 为 300 级。
- **旋转公平**：δ 每个 grant 后 +1；P 个周期覆盖所有对角线，每个源/目的都轮获得最高优先级。计数公平、无饥饿；严格 per-port RR 顺序做了一升一降的折中。
- **反压 / 复位**：`i_src_bp` / `i_dest_bp` 组合门控；`rst_n` 异步复位；`PTR_RESET=0` 可省 δ 复位。
- **参考实现**：`rtl/reference/fair_arbiter_islip.v` 保留严格双向 RR 的 iSLIP+fill 版本，用于对比。

## 极大性保证（原理）

WFA 按 torus 对角线顺序访问每个 crosspoint 恰好一次。反证：若请求 `(i,j)` 在结束时源 i 和目的 j 都空闲，由于 free 集合只减不增，轮到 `(i,j)` 时两端也一定空闲，cell 必然 grant，矛盾。因此不存在“出口空闲、入口却不调度”的请求对——输出对任意 N/M 都是**极大匹配**。

这是极大，不是最大：某个源可能因为唯一请求的目的已被更早的对角线占用而落选，这是允许的。`scripts/verify_wfa.py` 对小规模穷举全部请求矩阵，并对 2..16 所有形状、所有 δ 做了 94,475 例检查，0 失败；`tb/tb_maximal.sv` 覆盖 11 种 N/M 形状（最大 10x10），0 非极大、0 正交违规。

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

索引与算法对比见 [diagram/circuit/README.md](diagram/circuit/README.md)。默认 RTL
（`rtl/fair_arbiter.v`）是 **replicate/bank 波前 + 单侧公平覆盖**：P 个固定 δ 波前核并行，对角线旋转是综合期布线（0 级），一个寄存器 one-hot `delta_oh` 选择 bank。10x10 综合为 **12661 cells / 30 级**（8x8：6386 / 26）；SKY130HD 为 **7108 cells / 39794 um² / 3877 ps**（8x8：3424 / 20453 / 3634 ps）。旧旋转 WFA 为 5366 / 35（SKY130 5192 ps），旧 iSLIP+fill 为 11821 / 300。一般流量是极大匹配（不浪费调度）但不是最大匹配；单源/单目的序列是严格 RR（24/24）。

可选的 **4 调度公平顶层**（`rtl/fair_arbiter_sched4.v`，模块 `fair_arbiter_sched4`）保持相同接口，在一个 bank 上时分复用 4 组固定调度置换，并用寄存器化的“度数均匀”检测在 K-regular 流量下回到单波前+ 调度。随机 10x10 Jain 为 **0.914-0.933 src / 0.895-0.934 dst**，K-regular **1.000**；**12129 cells / 28 级（AOI 能力映射）**，旧 NAND/NOR-only 映射为 15199 cells / 40 级；SKY130HD **9040 cells / 53953 um² / 4522 ps**。它是公平优先模式，不是默认深度优先顶层。完整对比见 `docs/optimization.md`。

## fast / fair 两个版本

两个版本的顶层接口完全一致，只是内部调度不同。

| 版本 | RTL | 单源/单目的严格 RR | 多源公平 | 10x10 PPA |
|------|-----|--------------------|----------|-----------|
| **fast（默认，bank）** | `rtl/fair_arbiter.v` | **24/24** | bank WFA（Jain 0.821-0.887 src / 0.805-0.871 dst） | **12661 cells / 30 级；SKY130 7108 / 39794um² / 3877ps** |
| 旧旋转 WFA，4 调度 | `rtl/reference/fair_arbiter_rot.v` `NSCHED=4` | **42/42（历史）** | 4 调度 WFA（Jain 0.914-0.933 src / 0.895-0.934 dst） | 11255 cells / 36 级 |
| **fair（可选）** | `rtl/fair_arbiter_fair.v` | **24/24** | iSLIP 首轮 + WFA fill（Jain 0.87-0.90 src / 0.91-0.93 dst） | 5119 cells / 74 级 |
| **公平顶层（可选）** | `rtl/fair_arbiter_sched4.v` | **24/24** | 4 调度 + 自适应门控（Jain 0.914-0.933 src / 0.895-0.934 dst，K-reg 1.000） | 12129 / 28 级（AOI 映射；旧映射 15199 / 40 级）；SKY 9040 / 53953 / 4522 ps |
| 严格参考 | `rtl/reference/fair_arbiter_islip.v` | 全流量严格 | iSLIP+串行 fill | 11821 / 300 |

### 多调度公平（旧旋转参考）

默认 bank 是单调度。旧旋转参考 `rtl/reference/fair_arbiter_rot.v` 仍支持并行
`NSCHED` 个波前。第 s 个调度把 core 的行按 `r -> (c_s*r) mod N` 置换
（`c_s` 与 N 互质，纯布线，无 mux），输出每 P 个授予切换一次调度：

| 方案 | src Jain（10x10） | dst Jain（10x10） | 10x10 cells / 级数 |
|------|-------------------|-------------------|--------------------|
| **bank（默认）** | **0.821-0.887** | **0.805-0.871** | **12661 / 30** |
| 旧旋转 NSCHED=2 | 0.867-0.901 | 0.873-0.905 | 7395 / 35 |
| 旧旋转 NSCHED=4 | 0.914-0.933 | 0.895-0.934 | 11255 / 36 |
| fair 变体 | 0.866-0.895 | 0.912-0.934 | 5119 / 74 |

默认 bank 的 RTL 检查 `tb/tb_jain.sv` 实测 0.821-0.887 src / 0.805-0.871 dst
（三个持续模式），K-regular 为 1.000。`NSCHED` 参数只为旧旋转参考保留，默认
bank 顶层忽略它。

### 共享队列排空

每个源一个多目的共享队列时，排空速度主要取决于前级暴露多少队列内容。
10x10、每源 200 包：只看队头 337 拍，窗口 4 258 拍，全缓冲 235 拍。仲裁器的
极大匹配不浪费周期；只追求最大基数的参考反而更差（410 拍，饿死部分源）。
详见 `docs/perf.md`。

fair 版验证：主回归 192,884 checks PASS；极大性 11/11；3 形状 soak × 1500
PASS；10x10 × 20,000 soak PASS（146,049 grants，0 违规）；严格公平 24/24
（4 形状）。fair 版多源 Jain 平均（10x10 模型，3000 拍持续矩阵）：纯 WFA src
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
rtl/fair_arbiter.v          默认 bank 顶层（原始接口不变；N、M、PTR_RESET）
rtl/fair_arbiter_sched4.v   可选 4 调度公平顶层（相同接口）
rtl/wfa_core_fixed.v        固定 δ 的 P 级波前核（bank 使用）
rtl/wfa_core.v              旋转 δ 的 P 级波前核（旧参考）
rtl/reference/fair_arbiter_rot.v  旧旋转多调度顶层（NSCHED=1..4）
rtl/fair_arbiter_fair.v    可选 fair 版（iSLIP 首轮 + WFA fill）
rtl/reference/fair_arbiter_islip.v  严格 RR 的 iSLIP+fill 参考实现
rtl/reference/fair_arbiter_dpa.v    单遍 DPA（21 级，非极大）
tb/tb_fair_arbiter.sv       主回归（17 场景 × 17 配置，最大 10x10）
tb/tb_maximal.sv            极大性 / 正交性 / 输出一致性检查（11 种 N/M）
tb/tb_soak.sv               长跑随机 soak（数千拍 + 随机反压，含 10x10 两万拍）
tb/tb_jain.sv               RTL 上测默认 bank 的多源 Jain
tb/tb_fairness.sv           严格公平测试（fast 版）
tb/tb_fairness_fair.sv      严格公平测试（fair 版）
tb/tb_perf.sv               吞吐基准
tb/tb_x_check.sv            复位 / X 态检查
scripts/verify_wfa.py       WFA 算法级穷举极大性 / 正交性验证
scripts/fairness_compare.py  多源 Jain 模型：WFAx1/x2/x4 vs fair
scripts/fairness_explore.py  bank 选择策略 / 调度置换公平性模型
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
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

预期输出 `RESULT: ALL CONFIGURATIONS PASSED`。

极大性检查（11 种 N/M，最大 10x10，长随机 + 对抗模式）：

```bash
iverilog -g2012 -s tb_maximal_top -o sim/maximal.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp
```

长跑随机 soak（3 种形状，最大 10x10，× 1500 拍带随机反压，另加 10x10 × 20000 拍）：

```bash
iverilog -g2012 -s tb_soak_top   -o sim/soak.vvp   rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
iverilog -g2012 -s tb_soak10_top -o sim/soak10.vvp rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp
vvp sim/soak10.vvp
```

严格公平测试（单源多目的 / 单目的多源，all/even/odd，4 种形状，最大 10x10）：

```bash
iverilog -g2012 -s tb_fairness_top -o sim/fairness.vvp     rtl/wfa_core_fixed.v rtl/fair_arbiter.v tb/tb_fairness.sv
vvp sim/fairness.vvp
```

可选 4 调度公平顶层（编译 wrapper 替代默认顶层）：

```bash
iverilog -g2012 -s tb_jain_top -o sim/jain4.vvp \
    rtl/wfa_core_fixed.v rtl/fair_arbiter_sched4.v \
    tb/fair_arbiter_sched4_wrap.v tb/tb_jain.sv
vvp sim/jain4.vvp
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
bash synth/run_synth.sh        # 默认 bank：逐形状面积/深度
bash synth/run_synth.sh fair   # 可选 fair 变体
bash synth/run_synth.sh sky130 # SKY130HD 单元级/ABC 延迟

# 可选 4 调度公平顶层，AOI 能力通用映射
FAIR_SCHED=4 MAP=cmos bash synth/run_synth.sh fast
# 可选 4 调度公平顶层，SKY130HD
FAIR_SCHED=4 bash synth/run_synth.sh sky130
```

## 参数

| 参数 | 含义 | 默认 |
|------|------|------|
| N | 源数量（≥ 2） | 8 |
| M | 目的数量（≥ 2） | 8 |
| PTR_RESET | 0=bank δ 无复位（省面积），1=异步复位 | 1 |
| NSCHED | 兼容旧参数；默认 bank 顶层忽略 | 1 |
| WAVEFRONT_PLUS | 1=寄存器 presence 跳空；0=δ+1 | 1 |
| AOI_STYLE | 1=AOI21 形式 token 更新；0=AND/NAND | 1 |
| SEL_OH | 1=寄存器 one-hot bank 选择；0=二进制选择 | 1 |
| ITER | 旧参数，bank/WFA 忽略 | 4 |
| AUGMENT | 旧参数，bank/WFA 忽略 | 1 |

WFA 随机流量匹配规模：8x8 86%、10x10 89%，N≠M 时 96-100%。这低于旧 iSLIP+augment 的 97-98%，因为 WFA 是极大而非最大匹配——这是换深度的明确取舍。旧参考实现的 `ITER`/`AUGMENT` 行为见 `docs/ppa.md`。

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
