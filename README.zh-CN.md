# 公平仲裁器（iSLIP 交叉开关调度器）

参数化的 N 源 × M 目的公平仲裁器：每拍产生一个**正交（一对一）**匹配，源侧、目的侧**双向 round-robin 公平**，**当拍出结果**（零延迟），支持源/目的反压。

**硬保证：每拍都是极大匹配（maximal matching），对任意 N/M 都成立。** 只要某个请求 `(i,j)` 的源 i 和目的 j 都空闲却没有被调度，就是错误——本设计不允许这种情况。10x10、9x11、N<M、N>M、非 2 的幂全部覆盖。

**验证汇总**：22 种配置 / 294,356 项检查全部通过；18 种 N/M 形状（2x2 ... 16x16，含 10x10）每种 773 拍，0 非极大拍、0 浪费对、0 正交违规；长跑随机 soak（4 种形状 × 1500 拍带随机反压，另加 10x10 × 20,000 拍 / 720,096 个请求瞬间）0 非极大拍、0 不变量违规；算法级脚本 67,118 例（小规模穷举 + 2..16 全形状）0 失败；复位 / X 态检查通过。

[English](README.md) · [方案图](diagram/fair_arbiter_scheme.svg) · [算法动画](diagram/fair_arbiter_animation.svg)

## 特性

- **每拍极大匹配（无浪费调度）**：`ITER` 轮 iSLIP + 可选 `AUGMENT` 交换 + **残余填充**。填充阶段只增不删，保证不存在"两端都空闲的请求对"。
- **正交匹配**：每源至多命中 1 个目的、每目的至多命中 1 个源，同一拍无重复。
- **双向公平**：源侧 `a_ptr` 轮询目的、目的侧 `g_ptr` 轮询源；指针仅在"首轮真正匹配"时推进，乱序最小。
- **当拍出结果**：grant/accept/swap/fill 全部组合逻辑，唯一时序元件是指针寄存器，零延迟。
- **ITER 参数化**：`ITER=1` 面积/时序最优；`ITER=4`（默认）在随机流量下匹配规模更大。
- **AUGMENT 参数化**：`AUGMENT=1` 增加长度 3 增广（交换），把随机流量匹配规模从 89-91%（8x8/10x10，`AUGMENT=0`）提升到 97-98%，N≠M 时接近 100%；`AUGMENT=0` 保持严格 iSLIP 公平（极大性仍由填充保证）。
- **纯可综合 RTL**：无 `assert`、无系统任务，核心用算术最低置位 `x & ~(x-1)`（少用 function）。
- **反压 / 复位**：`i_src_bp` / `i_dest_bp` 组合门控；`rst_n` 异步复位（低有效）；指针默认带复位（仿真无 X）。

## 极大性保证（原理）

有限轮 iSLIP 对任意请求矩阵不保证极大；并行交换也可能"移走一个匹配但没完成替换"。因此最后一级是**残余填充**，只对仍然空闲的源/目的**增加**匹配：

```
for i = 0 .. N-1:
    若源 i 仍未匹配: 在"仍空闲且被 i 请求"的目的中选一个匹配
```

- 增加匹配**不可能制造**新的浪费对（浪费对要求两端都空闲，增加边只会减少空闲端点）。
- 填充结束时不可能残留浪费对：若 `(i,j)` 仍满足 `req=1` 且源 i 空闲、目的 j 空闲，由于空闲集合只减不增，j 在轮到 i 时仍空闲，i 必然会取一个目的，矛盾。
- 所以最终匹配对任意 N/M、任意请求矩阵都是极大的。填充还顺带修复交换的"未完成 move"。

形式化/穷举验证：`scripts/verify_maximal.py` 对小规模**穷举全部请求矩阵**，并对 2..16 的所有 N/M 形状、对抗模式、任意初始匹配做了 67,118 例检查，0 失败。RTL 层 `tb/tb_maximal.sv` 覆盖 18 种 N/M 形状 × 随机/对抗流量，0 非极大、0 正交违规。

## 电路级方案图（PNG，总 / 分）

低深度 **波前仲裁器（WFA / WWFA）** 变体的电路级 PNG 图：

- [总图](diagram/circuit/wfa_00_overview.png)
- [Crosspoint cell 门级电路](diagram/circuit/wfa_01_cell.png)
- [对角线波前阵列](diagram/circuit/wfa_02_diagonal.png)
- [δ 旋转与公平性](diagram/circuit/wfa_03_rotation.png)
- [不浪费调度示例](diagram/circuit/wfa_04_nowaste.png)
- [深度 / 面积指标](diagram/circuit/wfa_05_depth.png)

索引与算法对比见 [diagram/circuit/README.md](diagram/circuit/README.md)。WFA RTL
（`rtl/fair_arbiter_torus.v`）与主设计端口/参数兼容；10x10 综合为 3699 cells /
39 级，而旧 iSLIP+fill 为 11821 cells / 300 级。WFA 是极大匹配（不浪费调度）
但不是最大匹配，且源/目的 RR 顺序是一升一降的折中；8x8/10x10 满足 ≤40 级，
9x11/11x9/16x16 超 1-8 级，索引文档给出了 2 拍流水 / 分层优化方案。

## 文件结构

```
rtl/fair_arbiter.v          可综合 RTL（N、M、PTR_RESET、ITER、AUGMENT 参数）
tb/tb_fair_arbiter.sv       主回归（17 场景 × 22 配置，含 10x10）
tb/tb_maximal.sv            极大性 / 正交性 / 输出一致性检查（18 种 N/M）
tb/tb_soak.sv               长跑随机 soak（数千拍 + 随机反压，含 10x10 两万拍）
tb/tb_perf.sv               吞吐基准
tb/tb_x_check.sv            复位 / X 态检查
scripts/verify_maximal.py   算法级穷举极大性验证
diagram/                    方案图 + 算法动画（SVG，浏览器直接打开）
docs/scheme.md              设计原理与方案图
docs/testpoints.md          测试点分解与结果
docs/ppa.md                 综合 / PPA 报告
synth/synth.ys              Yosys 综合脚本
sim/run_sim.sh              Icarus 仿真脚本
sim/run_all.sh              全套验证（主回归 + 极大性 + X 检查 + 性能 + 穷举）
```

## 仿真

需 Icarus Verilog（`iverilog`）。Windows 下用 oss-cad-suite 时，先把 `bin` 和 `lib` 加入 PATH：

```bash
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

预期输出 `RESULT: ALL CONFIGURATIONS PASSED`。

极大性检查（18 种 N/M，含 10x10，长随机 + 对抗模式）：

```bash
iverilog -g2012 -s tb_maximal_top -o sim/maximal.vvp rtl/fair_arbiter.v tb/tb_maximal.sv
vvp sim/maximal.vvp
```

长跑随机 soak（4 种形状 × 1500 拍带随机反压，另加 10x10 × 20000 拍）：

```bash
iverilog -g2012 -s tb_soak_top   -o sim/soak.vvp   rtl/fair_arbiter.v tb/tb_soak.sv
iverilog -g2012 -s tb_soak10_top -o sim/soak10.vvp rtl/fair_arbiter.v tb/tb_soak.sv
vvp sim/soak.vvp
vvp sim/soak10.vvp
```

全套验证（主回归 + 极大性 + soak + X + 性能 + 穷举）：

```bash
bash sim/run_all.sh
```

算法级穷举：

```bash
python scripts/verify_maximal.py
```

## 综合（PPA）

```bash
yosys -s synth/synth.ys     # ITER / AUGMENT / 规模扫描 + 面积统计
```

## 参数

| 参数 | 含义 | 默认 |
|------|------|------|
| N | 源数量（≥ 2） | 8 |
| M | 目的数量（≥ 2） | 8 |
| PTR_RESET | 0=指针无复位（省面积），1=异步复位 | 1 |
| ITER | 贪心匹配迭代轮数 | 4 |
| AUGMENT | 1=交换/增广（提升规模，放松公平性），0=纯 iSLIP | 1 |

残余填充始终存在，是极大性的保证；`AUGMENT` 只影响匹配**规模**（不影响极大性）。`AUGMENT=1` 的交换内部用固定最低索引优先级，固定请求矩阵下可能饿死某个 pair，因此 S16 饥饿测试只在 `AUGMENT=0` 时运行——这是"性能最大化、牺牲一点 RR 公平性"的明确取舍。

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
