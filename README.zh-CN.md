# 公平仲裁器（波前 / WFA 交叉开关调度器）

参数化的 N 源 × M 目的公平仲裁器：每拍产生一个**正交（一对一）**匹配，**当拍出结果**（零延迟），支持源/目的反压。默认实现是 **Wavefront Arbiter（WFA/WWFA）**：P=max(N,M) 条 torus 对角线、P 级组合波前，唯一状态是一个小的旋转起点寄存器。

**硬保证：每拍都是极大匹配（maximal matching），对任意 N/M 都成立。** 只要某个请求 `(i,j)` 的源 i 和目的 j 都空闲却没有被调度，就是错误——本设计不允许这种情况。10x10、9x11、N<M、N>M、非 2 的幂全部覆盖。

**验证汇总**：22 种配置 / 295,797 项检查全部通过；18 种 N/M 形状（2x2 ... 16x16，含 10x10）每种 773 拍，0 非极大拍、0 浪费对、0 正交违规；长跑随机 soak（4 种形状 × 1500 拍带随机反压，另加 10x10 × 20,000 拍 / 720,096 个请求瞬间）0 非极大拍、0 不变量违规；WFA 算法级脚本 94,475 例（小规模穷举 + 2..16 全形状 + 所有 δ）0 失败；复位 / X 态检查通过。

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

索引与算法对比见 [diagram/circuit/README.md](diagram/circuit/README.md)。WFA RTL
（`rtl/fair_arbiter.v`，默认 RTL）10x10 综合为 2062 cells /
35 级，而旧 iSLIP+fill 为 11821 cells / 300 级。WFA 是极大匹配（不浪费调度）
但不是最大匹配，且源/目的 RR 顺序是一升一降的折中；8x8/10x10 满足 ≤40 级，
16x16 超 8 级，索引文档给出了 2 拍流水 / 分层优化方案。

## 文件结构

```
rtl/fair_arbiter.v          默认 WFA RTL（N、M、PTR_RESET；ITER/AUGMENT 兼容但忽略）
rtl/reference/fair_arbiter_islip.v  严格 RR 的 iSLIP+fill 参考实现
tb/tb_fair_arbiter.sv       主回归（17 场景 × 22 配置，含 10x10）
tb/tb_maximal.sv            极大性 / 正交性 / 输出一致性检查（18 种 N/M）
tb/tb_soak.sv               长跑随机 soak（数千拍 + 随机反压，含 10x10 两万拍）
tb/tb_perf.sv               吞吐基准
tb/tb_x_check.sv            复位 / X 态检查
scripts/verify_wfa.py       WFA 算法级穷举极大性 / 正交性验证
scripts/verify_maximal.py   旧 iSLIP+fill 参考实现的同类验证
diagram/circuit/            WFA 电路级 PNG 方案图（总 / 分）
diagram/                    旧 iSLIP 方案图 + 算法动画（SVG）
docs/scheme.md              设计原理与方案图
docs/testpoints.md          测试点分解与结果
docs/ppa.md                 综合 / PPA 报告
synth/synth.ys              Yosys 综合 / 深度扫描（WFA）
synth/synth_islip.ys        旧 iSLIP 参考实现的综合扫描
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
python scripts/verify_wfa.py
```

## 综合（PPA）

```bash
yosys -s synth/synth.ys     # WFA 规模 / 复位 / 深度扫描
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
