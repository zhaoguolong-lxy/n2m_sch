# 公平仲裁器（iSLIP 交叉开关调度器）

参数化的 N 源 × M 目的公平仲裁器：每拍产生一个**正交（一对一）**匹配，源侧、目的侧**双向 round-robin 公平**，**当拍出结果**（零延迟），支持源/目的反压。

[English](README.md) · [方案图](diagram/fair_arbiter_scheme.svg) · [算法动画](diagram/fair_arbiter_animation.svg)

## 特性

- **正交匹配**：每源至多命中 1 个目的、每目的至多命中 1 个源，同一拍无重复。
- **双向公平**：源侧 `a_ptr` 轮询目的、目的侧 `g_ptr` 轮询源；指针仅在"首轮真正匹配"时推进，乱序最小。
- **当拍出结果**：grant/accept 全部组合逻辑，唯一时序元件是指针寄存器，零延迟。
- **ITER 参数化**：`ITER=1` 面积/时序最优；`ITER=2..3` 吞吐甜点（每 +1 轮 ≈ 首拍多 1 个匹配）。
- **纯可综合 RTL**：无 `assert`、无系统任务，核心用算术最低置位 `x & ~(x-1)`（少用 function）。
- **反压 / 复位**：`i_src_bp` / `i_dest_bp` 组合门控；`rst_n` 异步复位（低有效）；指针默认带复位（仿真无 X）。

## 文件结构

```
rtl/fair_arbiter.v          可综合 RTL（N、M、PTR_RESET、ITER 参数）
tb/tb_fair_arbiter.sv       自检 testbench（17 场景 × 13 配置）
diagram/                    方案图 + 算法动画（SVG，浏览器直接打开）
docs/scheme.md              设计原理与方案图
docs/testpoints.md          测试点分解与结果
docs/ppa.md                 综合 / PPA 报告
synth/synth.ys              Yosys 综合脚本
sim/run_sim.sh              Icarus 仿真脚本
```

## 仿真

需 Icarus Verilog（`iverilog`）。Windows 下用 oss-cad-suite 时，先把 `bin` 和 `lib` 加入 PATH：

```bash
iverilog -g2012 -Wall -s tb_top -o sim/sim.vvp rtl/fair_arbiter.v tb/tb_fair_arbiter.sv
vvp sim/sim.vvp
```

预期输出 `RESULT: ALL CONFIGURATIONS PASSED`（141,213 项检查）。

## 综合（PPA）

```bash
yosys -s synth/synth.ys     # 输出 ITER 扫描、复位对比、规模对比的面积统计
```

## 参数

| 参数 | 含义 | 默认 |
|------|------|------|
| N | 源数量（≥ 2） | 8 |
| M | 目的数量（≥ 2） | 8 |
| PTR_RESET | 0=指针无复位（省面积），1=异步复位 | 1 |
| ITER | 贪心匹配迭代轮数 | 4 |
| AUGMENT | 1=交换/增广一轮（近最大匹配） | 1 |

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
