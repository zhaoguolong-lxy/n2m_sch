#!/usr/bin/env python3
"""Generate PNG circuit diagrams for the Wavefront (WFA/WWFA) arbiter.

All output is PNG (rendered directly from an internal SVG model; no SVG files
are written).  Run: python scripts/gen_wfa_diagrams.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_circuit_diagrams import (  # noqa: E402
    SVG, BG, TXT, DIM, MUTED, CYAN, GREEN, VIOLET, AMBER, ROSE, BLUE,
    ORANGE, WIRE, FILLS,
)

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "diagram", "circuit")


def diamond(d, cx, cy, r=20, color=BLUE, label="MUX"):
    d.add('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" '
          'fill="%s" stroke="%s" stroke-width="1.4"/>'
          % (cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy,
             FILLS[BLUE], color))
    d.txt(cx, cy + 3, label, 7, TXT, "middle")


def grid4(d, x, y, cell=34, colors=None, labels=None, title=None,
          real=None):
    """Draw a 4x4 cell grid with optional diagonal colors and labels."""
    for i in range(4):
        for j in range(4):
            cx = x + j * cell
            cy = y + i * cell
            c = colors[i][j] if colors else MUTED
            fill = FILLS.get(c, FILLS[MUTED])
            d.add('<rect x="%d" y="%d" width="%d" height="%d" rx="2" '
                  'fill="%s" stroke="%s" stroke-width="1"/>'
                  % (cx, cy, cell - 2, cell - 2, fill, c))
            lab = labels[i][j] if labels else ""
            if lab:
                d.txt(cx + (cell - 2) / 2, cy + (cell - 2) / 2 + 3,
                      lab, 7.5, TXT, "middle")
            if real is not None and not real[i][j]:
                d.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" '
                      'stroke-width="1" opacity="0.5"/>'
                      % (cx + 3, cy + 3, cx + cell - 5, cy + cell - 5, MUTED))
    if title:
        d.txt(x, y - 6, title, 8.5, DIM)


def arrow_label(d, x, y, text, color=DIM, size=8):
    d.txt(x, y, text, size, color, "middle")


# ===========================================================================
# 00 - overview
# ===========================================================================
def d00(path):
    d = SVG(1700, 1050)
    d.txt(30, 38, "波前仲裁器（WFA / WWFA）— 总图", 20, TXT, weight=700)
    d.txt(30, 58, "P = max(N,M) 级对角线波前 · 单拍输出 · N>M 自动转置 · "
                  "单源/单目的严格 RR 覆盖与 WFA 并行", 10.5, DIM)

    # inputs
    d.chip(30, 92, 150, 34, "clk", None, CYAN, title_size=10)
    d.chip(30, 136, 150, 34, "rst_n", None, CYAN, title_size=10)
    d.chip(30, 188, 220, 66, "i_src_dest_req", "[N-1:0][M-1:0]", CYAN)
    d.chip(30, 270, 220, 48, "i_src_bp [N]", None, CYAN, title_size=9)
    d.chip(30, 330, 220, 48, "i_dest_bp [M]", None, CYAN, title_size=9)

    # pad block
    d.region(290, 150, 200, 260, "① 对称化 / 填充 / 门控")
    d.txt(300, 180, "N>M: 先转置（纯连线）", 8.5, TXT, weight=600)
    d.txt(300, 194, "Nc=min, Mc=max, P=Mc", 7.5, DIM)
    d.txt(300, 208, "真实 Nc x Mc + dummy 0", 7.5, DIM)
    colors = [[MUTED] * 4 for _ in range(4)]
    real = [[True] * 4 for _ in range(4)]
    labels = [[""] * 4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            labels[i][j] = "R" if (i < 3 and j < 3) else "-"
            colors[i][j] = CYAN if (i < 3 and j < 3) else MUTED
    grid4(d, 306, 228, 30, colors, labels, real=real)
    d.txt(306, 370, "R = req & rst_n & ~src_bp & ~dest_bp", 7.5, DIM)
    d.txt(306, 384, "dummy 行/列恒 0；输出 req_pad[P x P]", 7.5, DIM)

    # rotate block
    d.region(520, 150, 190, 190, "② 列旋转 δ")
    d.txt(530, 180, "每行一个 P 路 MUX", 8.5, DIM)
    for k, ch in enumerate("abcd"):
        d.add('<rect x="%d" y="198" width="26" height="24" rx="2" '
              'fill="%s" stroke="%s"/>' % (532 + k * 30, FILLS[CYAN], CYAN))
        d.txt(545 + k * 30, 214, ch, 9, TXT, "middle")
    d.wire([(652, 210), (672, 210)], ORANGE, arrow=True)
    for k, ch in enumerate("cdab"):
        d.add('<rect x="%d" y="234" width="26" height="24" rx="2" '
              'fill="%s" stroke="%s"/>' % (532 + k * 30, FILLS[GREEN], GREEN))
        d.txt(545 + k * 30, 250, ch, 9, TXT, "middle")
    d.txt(640, 250, "→ 物理列 (j+δ)%P", 8, DIM)
    d.txt(530, 290, "行 i 不变；δ 决定哪一列先被", 7.5, DIM)
    d.txt(530, 303, "波前看到（优先级旋转）", 7.5, DIM)
    d.wire([(490, 280), (520, 280)], ORANGE, bus=True, arrow=True)

    # wavefront core
    d.region(740, 108, 500, 460, "③ 波前核心：P 级 × P cell", GREEN)
    d.txt(752, 138, "4x4 示例：颜色 = 对角线 d = (j-i) mod P", 8.5, DIM)
    # 4x4 diagonal colors 0..3
    dcolors = [CYAN, GREEN, VIOLET, AMBER]
    cols = [[dcolors[(j - i) % 4] for j in range(4)] for i in range(4)]
    grid4(d, 760, 156, 38, cols)
    # N/W arrows on grid
    for i in range(4):
        for j in range(4):
            cx = 760 + j * 38 + 18
            cy = 156 + i * 38 + 18
            if i > 0:
                d.wire([(cx - 4, cy - 16), (cx - 4, cy - 8)], GREEN,
                       arrow=True)
            if j > 0:
                d.wire([(cx - 16, cy - 4), (cx - 8, cy - 4)], GREEN,
                       arrow=True)
    d.txt(760, 326, "N / W = 上方 / 左侧尚无 grant", 7.5, DIM)
    d.txt(760, 340, "S / E = 把“仍空闲”传给下方 / 右侧", 7.5, DIM)
    # stage list
    stages = [
        ("Stage 0", "d=0: (0,0)(1,1)(2,2)(3,3)", CYAN),
        ("Stage 1", "d=1: (0,1)(1,2)(2,3)(3,0)", GREEN),
        ("Stage 2", "d=2: (0,2)(1,3)(2,0)(3,1)", VIOLET),
        ("Stage 3", "d=3: (0,3)(1,0)(2,1)(3,2)", AMBER),
    ]
    for k, (t, s, c) in enumerate(stages):
        y = 162 + k * 66
        d.add('<rect x="930" y="%d" width="292" height="52" rx="5" '
              'fill="%s" stroke="%s" stroke-width="1"/>'
              % (y, FILLS.get(c, FILLS[MUTED]), c))
        d.txt(940, y + 17, t, 9, c, weight=600)
        d.txt(940, y + 32, s, 7.5, DIM)
    d.txt(930, 438, "每级 P 个 cell：一行一个、一列一个", 8, DIM)
    d.txt(930, 452, "同级 cell 可并行；级间传 row/col token", 8, DIM)
    d.txt(930, 466, "共 P 级（不是 N+M-1，也没有串行 fill）", 8, GREEN)
    # token bus between stages
    d.wire([(920, 180), (920, 420)], GREEN, bus=True, arrow=False, dash="3,3")
    d.wire([(760, 360), (760, 380), (920, 380)], GREEN, bus=True, arrow=False)
    # internal labels
    d.txt(760, 540, "G = R & N & W ;  S = N & ~G ;  E = W & ~G", 8.5, TXT)
    d.txt(760, 556, "grant 同时消耗行与列；未 grant 时 token 原样下传", 8, DIM)
    d.wire([(700, 280), (740, 280)], ORANGE, bus=True, arrow=True)

    # inverse rotation
    d.region(1280, 150, 150, 160, "④ 逆旋转")
    d.txt(1290, 180, "物理 (i,j)", 8.5, DIM)
    d.txt(1290, 194, "← 逻辑 (i,(j-δ)%P)", 8, DIM)
    d.wire([(1240, 250), (1280, 250)], ORANGE, bus=True, arrow=True)
    d.wire([(1430, 250), (1460, 250)], ORANGE, bus=True, arrow=True)

    # output logic
    d.region(1460, 150, 210, 270, "⑤ 输出逻辑", ORANGE)
    d.txt(1472, 180, "行 OR → src_vld[N]", 8.5, DIM)
    d.txt(1472, 198, "列 OR → dest_vld[M]", 8.5, DIM)
    d.txt(1472, 220, "one-hot → binary", 8.5, DIM)
    d.txt(1472, 236, "  → src_ptr[N][CWM]", 8, DIM)
    d.txt(1472, 252, "  → dest_ptr[M][CWN]", 8, DIM)
    d.txt(1472, 280, "match = 物理 grant", 8, ORANGE)
    d.txt(1472, 294, "直接展开 o_grant_rand_vld", 7.5, DIM)
    d.txt(1472, 320, "极大性已由波前保证", 8, GREEN)
    d.txt(1472, 334, "此级只做编码/扇出", 7.5, DIM)
    d.txt(1472, 360, "无 iSLIP 迭代、无 augment", 7.5, DIM)
    d.txt(1472, 374, "单源/单目的 RR 覆盖并行", 7.5, GREEN)
    d.txt(1472, 394, "final = 覆盖 ? RR pair : WFA", 7.5, CYAN)
    d.txt(1472, 408, "N>M 时输出转置回 N x M", 7.0, DIM)

    # output chips
    outs = [
        (430, 58, "o_grant_rand_vld", "[N·M] 物理匹配"),
        (500, 40, "o_grant_src_vld [N]", None),
        (548, 46, "o_grant_src_ptr", "[N][CWM]"),
        (604, 40, "o_grant_dest_vld [M]", None),
        (652, 46, "o_grant_dest_ptr", "[M][CWN]"),
    ]
    for (y, h, t, s) in outs:
        d.chip(1460, y, 210, h, t, s, CYAN, title_size=8.6, sub_size=7.5)
    d.wire([(1670, 405), (1682, 405), (1682, 675)], ORANGE, bus=True,
           arrow=False)
    for y in (459, 520, 571, 624, 675):
        d.wire([(1682, y), (1670, y)], ORANGE, arrow=True)

    # delta register
    d.region(740, 620, 500, 130, "⑥ 旋转起点 δ（唯一时序状态）", VIOLET)
    d.dff(790, 654, 100, 70, "δ", "0..P-1")
    d.txt(800, 742, "clk / rst_n", 7.5, DIM)
    d.add('<rect x="920" y="664" width="70" height="38" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[AMBER], AMBER))
    d.txt(955, 687, "+1 mod P", 8, TXT, "middle")
    d.wire([(890, 690), (920, 690)], VIOLET, arrow=True)
    d.wire([(990, 683), (1020, 683), (1020, 656), (890, 656)], VIOLET,
           arrow=True)
    d.txt(1040, 680, "any_req 使能", 8, VIOLET)
    d.txt(1040, 694, "（无请求保持）", 7.5, DIM)
    d.txt(1040, 724, "δ 送 ② ④；复位 0", 8, DIM)
    # delta to rotate/inverse
    d.wire([(1020, 654), (1020, 600), (605, 600), (605, 340)], VIOLET,
           bus=True, arrow=True)
    d.wire([(1020, 600), (1355, 600), (1355, 310)], VIOLET, bus=True,
           arrow=True)
    d.tag(700, 610, "δ", VIOLET)
    d.tag(1355, 610, "δ", VIOLET)
    # any_req = |eff_req enable comes from the request/pad path, not the WFA
    d.wire([(490, 410), (490, 592), (1120, 592), (1120, 660), (1020, 660)],
           GREEN, arrow=True)
    d.tag(1300, 582, "any_req = |eff_req", GREEN)

    # depth panel
    d.region(30, 700, 680, 300, "深度指标（Yosys generic gate levels）", AMBER)
    rows = [("8x8", "P=8", "28", GREEN), ("10x10", "P=10", "35", GREEN),
            ("9x11", "P=11", "36", GREEN), ("11x9", "P=11", "35", GREEN),
            ("16x16", "P=16", "—", MUTED)]
    d.txt(50, 732, "配置", 9, DIM, weight=600)
    d.txt(190, 732, "P", 9, DIM, weight=600)
    d.txt(300, 732, "级数", 9, DIM, weight=600)
    d.txt(430, 732, "结论", 9, DIM, weight=600)
    for k, (cfg, p, lv, c) in enumerate(rows):
        y = 760 + k * 36
        d.txt(50, y, cfg, 11, TXT, weight=600)
        d.txt(190, y, p, 10, DIM)
        d.txt(300, y, lv, 11, c, weight=600)
        if c == GREEN:
            d.txt(430, y, "满足 ≤40", 9, GREEN)
        elif c == MUTED:
            d.txt(430, y, "非本变体目标", 9, MUTED)
        else:
            d.txt(430, y, "需优化", 9, c)
        d.add('<line x1="40" y1="%d" x2="700" y2="%d" stroke="%s" '
              'stroke-width="0.5"/>' % (y + 10, y + 10, MUTED))
    d.txt(50, 950, "目标线 40：8x8 / 10x10 / 9x11 / 11x9 达标；16x16 不在本变体目标内", 8.5, AMBER)

    # notes
    d.region(740, 780, 930, 220, "算法要点 / 优化方向", ORANGE)
    notes = [
        "WFA 是可证明的极大（maximal）匹配：每个请求 cell 都被波前访问一次；",
        "若某请求对两端在结束时都空闲，则轮到它时两端也空闲，必 grant。",
        "极大 ≠ 最大：允许某个源因唯一目的已被更早的对角线占用而落选。",
        "深度 = P 级 × 单 cell 延时 + 旋转/编码；没有 ITER 展开、没有串行 fill。",
        "16x16 超过 40：可把波前按 2 拍流水（每拍 P/2 级，~24 级），或按 4x4",
        "分层先局部 WFA 再二级仲裁；代价分别是 latency +1 / 面积与连线增加。",
    ]
    for k, s in enumerate(notes):
        d.txt(756, 810 + k * 26, s, 8.5, TXT if k < 4 else DIM)

    d.render(path, 2.0)


# ===========================================================================
# 01 - cell
# ===========================================================================
def d01(path):
    d = SVG(1400, 860)
    d.txt(30, 38, "Crosspoint Cell — 波前单元电路", 20, TXT, weight=700)
    d.txt(30, 58, "G = R & N & W ;  S = N & ~(R & W) ;  E = W & ~(R & N)  "
                  "（全部高有效）", 10.5, DIM)

    # context 3x3
    d.region(30, 100, 330, 330, "cell 在阵列中的位置")
    for i in range(3):
        for j in range(3):
            x = 70 + j * 90
            y = 150 + i * 90
            c = GREEN if (i == 1 and j == 1) else MUTED
            d.add('<rect x="%d" y="%d" width="74" height="74" rx="5" '
                  'fill="%s" stroke="%s" stroke-width="1.4"/>'
                  % (x, y, FILLS.get(c, FILLS[MUTED]), c))
            d.txt(x + 37, y + 42, "(%d,%d)" % (i, j), 9,
                  TXT if c == GREEN else DIM, "middle")
    d.txt(195, 420, "N/W 从上方/左侧来，S/E 去下方/右侧", 8.5, DIM)
    d.txt(195, 438, "wrap 版本从边缘绕回（见图 02）", 8.5, DIM)
    # token arrows into/out of the center cell (1,1) at 160..234, 240..314
    d.wire([(130, 277), (160, 277)], GREEN, arrow=True)
    d.txt(138, 267, "W", 9, GREEN, "middle")
    d.wire([(197, 210), (197, 240)], GREEN, arrow=True)
    d.txt(207, 226, "N", 9, GREEN, "middle")
    d.wire([(197, 314), (197, 344)], GREEN, arrow=True)
    d.txt(207, 334, "S", 9, GREEN, "middle")
    d.wire([(234, 277), (264, 277)], GREEN, arrow=True)
    d.txt(250, 267, "E", 9, GREEN, "middle")

    # gate schematic
    d.region(400, 100, 560, 560, "门级电路")
    # G = R & N & W (single 3-input AND)
    d.txt(420, 140, "grant 分支", 9, CYAN, weight=600)
    d.add('<path d="M 580 162 L 620 162 A 18 18 0 0 1 620 198 L 580 198 Z" '
          'fill="%s" stroke="%s" stroke-width="1.4"/>' % (FILLS[GREEN], GREEN))
    d.txt(612, 184, "&", 8, "#d1fae5", "middle")
    for yy, cc, lab in ((168, CYAN, "R"), (180, GREEN, "N"), (192, GREEN, "W")):
        d.wire([(470, yy), (580, yy)], cc, arrow=False)
        d.txt(474, yy - 4, lab, 9, cc)
    d.wire([(638, 180), (690, 180)], GREEN, arrow=True)
    d.txt(706, 184, "G", 11, GREEN, "start", 700)
    d.txt(470, 228, "G = R & N & W", 9, TXT)

    # S = N & ~(R & W)
    d.txt(420, 280, "south token", 9, VIOLET, weight=600)
    d.andg(560, 330, 2, GREEN)
    d.notg(620, 330, GREEN)
    d.andg(700, 330, 2, VIOLET)
    d.wire([(470, 318), (533, 318), (533, 323)], CYAN, arrow=False)
    d.wire([(470, 342), (533, 342), (533, 337)], GREEN, arrow=False)
    d.wire([(588, 330), (596, 330)], GREEN, arrow=True)
    d.wire([(644, 330), (673, 330), (673, 323)], GREEN, arrow=False)
    d.wire([(470, 306), (680, 306), (680, 337), (673, 337)], GREEN, arrow=False)
    d.wire([(728, 330), (770, 330)], VIOLET, arrow=True)
    d.txt(786, 334, "S", 11, VIOLET, "start", 700)
    d.txt(470, 292, "R", 9, CYAN)
    d.txt(522, 316, "N", 9, GREEN)
    d.txt(470, 334, "W", 9, GREEN)
    d.txt(470, 366, "S = N & ~(R & W)", 9, TXT)
    d.txt(470, 380, "（未 grant 时 N 原样下传）", 7.5, DIM)

    # E = W & ~(R & N)
    d.txt(420, 430, "east token", 9, AMBER, weight=600)
    d.andg(560, 480, 2, GREEN)
    d.notg(620, 480, GREEN)
    d.andg(700, 480, 2, AMBER)
    d.wire([(470, 468), (533, 468), (533, 473)], CYAN, arrow=False)
    d.wire([(470, 492), (533, 492), (533, 487)], GREEN, arrow=False)
    d.wire([(588, 480), (596, 480)], GREEN, arrow=True)
    d.wire([(644, 480), (673, 480), (673, 473)], GREEN, arrow=False)
    d.wire([(470, 456), (680, 456), (680, 487), (673, 487)], GREEN, arrow=False)
    d.wire([(728, 480), (770, 480)], AMBER, arrow=True)
    d.txt(786, 484, "E", 11, AMBER, "start", 700)
    d.txt(470, 442, "R", 9, CYAN)
    d.txt(522, 466, "W", 9, GREEN)
    d.txt(470, 496, "N", 9, GREEN)
    d.txt(470, 516, "E = W & ~(R & N)", 9, TXT)
    d.txt(470, 530, "（未 grant 时 W 原样右传）", 7.5, DIM)

    d.txt(420, 580, "grant 同时消耗两个 token；未 grant 时 token 原样下传", 8.5, GREEN)
    d.txt(420, 596, "cell 无寄存器，纯组合；P 级串联构成波前", 8.5, DIM)
    d.txt(420, 612, "关键路径：N/W → G → S/E，约 2 级门", 8.5, AMBER)

    # truth table
    d.region(1000, 100, 370, 470, "真值表（1 = 空闲 / 有请求）")
    cols = ["R", "N", "W", "G", "S", "E"]
    xs = [1020, 1070, 1120, 1170, 1220, 1270]
    for x, c in zip(xs, cols):
        d.txt(x, 136, c, 9, CYAN if c == "G" else DIM, "middle", 600)
    rows = [(0, 0, 0, 0, 0, 0), (0, 0, 1, 0, 0, 1),
            (0, 1, 0, 0, 1, 0), (0, 1, 1, 0, 1, 1),
            (1, 0, 0, 0, 0, 0), (1, 0, 1, 0, 0, 1),
            (1, 1, 0, 0, 1, 0), (1, 1, 1, 1, 0, 0)]
    for k, row in enumerate(rows):
        y = 164 + k * 40
        for x, v in zip(xs, row):
            hot = (v == 1)
            d.txt(x, y, str(v), 11, GREEN if hot else MUTED, "middle",
                  600 if hot else 400)
        d.add('<line x1="1010" y1="%d" x2="1360" y2="%d" stroke="%s" '
              'stroke-width="0.4"/>' % (y + 12, y + 12, MUTED))
    d.txt(1185, 520, "只有 R=N=W=1 才 grant", 8.5, TXT, "middle")
    d.txt(1185, 536, "grant 后 S=E=0（行/列都被占用）", 8.5, DIM, "middle")

    # bottom notes
    d.region(30, 690, 1340, 140, "为什么这保证“不浪费调度”")
    d.txt(46, 720, "波前按对角线顺序访问每个 crosspoint。若请求 (i,j) 在结束时两端都空闲，"
                   "则轮到它时两端也空闲（free 集合只会缩小），", 9, TXT)
    d.txt(46, 740, "cell 必然 grant，矛盾。因此不存在“出口空闲、入口却不调度”的请求对——"
                   "输出是极大匹配。", 9, TXT)
    d.txt(46, 764, "注意：极大 ≠ 最大。某源可能因为唯一目的已被更早的对角线占用而落选，"
                   "这是允许的（示例见图 04）。", 8.5, AMBER)

    d.render(path, 2.0)


# ===========================================================================
# 02 - diagonal array / stages
# ===========================================================================
def d02(path):
    d = SVG(1600, 1000)
    d.txt(30, 38, "对角线波前阵列 — P 级 × P cell", 20, TXT, weight=700)
    d.txt(30, 58, "4x4 示例：每级取同色对角线；级内无行/列冲突，可并行 grant",
          10.5, DIM)

    # 4x4 physical array
    d.region(40, 100, 430, 480, "物理 crosspoint 阵列（torus 4x4）")
    dcolors = [CYAN, GREEN, VIOLET, AMBER]
    cols = [[dcolors[(j - i) % 4] for j in range(4)] for i in range(4)]
    labels = [[f"{i}{j}" for j in range(4)] for i in range(4)]
    grid4(d, 80, 150, 80, cols, labels)
    # arrows
    for i in range(4):
        for j in range(4):
            cx = 80 + j * 80 + 38
            cy = 150 + i * 80 + 38
            if i > 0:
                d.wire([(cx - 6, cy - 36), (cx - 6, cy - 20)], GREEN, arrow=True)
            if j > 0:
                d.wire([(cx - 36, cy - 6), (cx - 20, cy - 6)], GREEN, arrow=True)
    # wrap arrows (dashed)
    d.wire([(400, 200), (440, 200), (440, 300), (404, 300)], MUTED,
           arrow=True, dash="4,3")
    d.wire([(200, 470), (200, 500), (300, 500), (300, 474)], MUTED,
           arrow=True, dash="4,3")
    d.txt(440, 250, "wrap", 7.5, MUTED)
    d.txt(440, 264, "S/E 绕回", 7.5, MUTED)
    d.txt(60, 540, "cell 标号 = (source, dest)；颜色 = d = (j-i) mod 4", 8.5, DIM)
    d.txt(60, 556, "每级取一种颜色：4 个 cell，一行一个、一列一个", 8.5, DIM)

    # stage list
    d.region(510, 100, 1050, 480, "P 级串联（每级 P 个 cell 并行）")
    stages = [
        ("Stage d=0", [(0, 0), (1, 1), (2, 2), (3, 3)], CYAN),
        ("Stage d=1", [(0, 1), (1, 2), (2, 3), (3, 0)], GREEN),
        ("Stage d=2", [(0, 2), (1, 3), (2, 0), (3, 1)], VIOLET),
        ("Stage d=3", [(0, 3), (1, 0), (2, 1), (3, 2)], AMBER),
    ]
    for k, (title, cells, c) in enumerate(stages):
        y = 140 + k * 96
        d.add('<rect x="530" y="%d" width="1010" height="78" rx="6" '
              'fill="%s" stroke="%s" stroke-width="1"/>'
              % (y, FILLS.get(c, FILLS[MUTED]), c))
        d.txt(544, y + 18, title, 9.5, c, weight=600)
        for m, (i, j) in enumerate(cells):
            x = 650 + m * 150
            d.add('<rect x="%d" y="%d" width="120" height="42" rx="4" '
                  'fill="%s" stroke="%s"/>' % (x, y + 24, FILLS[GREEN], GREEN))
            d.txt(x + 60, y + 42, "cell (%d,%d)" % (i, j), 8.5, TXT, "middle")
            d.txt(x + 60, y + 56, "R / N / W", 7, DIM, "middle")
            # cells of the same diagonal evaluate in parallel (no intra-stage
            # serial arrows)
        d.txt(1460, y + 45, "P cells 并行", 7.5, c, "middle")
        # row/col free bus
        d.wire([(530 + 470, y + 78), (530 + 470, y + 96)], GREEN, bus=True,
               arrow=True)
    d.txt(540, 530, "row_free[P] / col_free[P] 在级间传递；每级清零被 grant 的行与列",
          8.5, DIM)
    d.txt(540, 546, "G = R & row_free[i] & col_free[j]", 8.5, TXT)
    d.txt(540, 562, "row_free'[i] = row_free[i] & ~G ;  col_free'[j] = col_free[j] & ~G",
          8.5, TXT)

    # bottom token flow
    d.region(40, 620, 1520, 330, "级间 token 流与关键路径")
    # chain of stages
    for k in range(5):
        x = 90 + k * 280
        d.chip(x, 680, 200, 70, "Stage %d" % k if k < 4 else "输出",
               "d=%d" % k if k < 4 else "match", GREEN if k < 4 else ORANGE,
               title_size=10)
        if k < 4:
            d.wire([(x + 200, 715), (x + 280, 715)], GREEN, bus=True, arrow=True)
    d.txt(90, 780, "每级延时 ≈ 2 个门（NAND + AND）；P 级串联", 9, TXT)
    d.txt(90, 798, "P=10 → 20 级波前 + 旋转/编码 ≈ 39 级（Yosys 实测）", 9, GREEN)
    d.txt(90, 816, "没有 ITER 展开，也没有 N 级串行 fill；深度从 O(N·优先级选择) 降到 O(P)",
          9, TXT)
    d.txt(90, 840, "P≥11 超过 40：见深度优化图（2 拍流水 / 4x4 分层）", 9, AMBER)

    d.render(path, 2.0)


# ===========================================================================
# 03 - rotation / fairness
# ===========================================================================
def d03(path):
    d = SVG(1600, 920)
    d.txt(30, 38, "旋转优先级 δ 与公平性", 20, TXT, weight=700)
    d.txt(30, 58, "δ 是唯一状态；每个 grant 后 +1。P 个周期覆盖所有对角线和所有端口",
          10.5, DIM)

    # barrel shifter
    d.region(40, 100, 720, 300, "列旋转（每行一个 P 路 MUX）")
    d.txt(70, 140, "物理列", 8.5, DIM)
    for k, ch in enumerate("abcd"):
        y = 160 + k * 40
        d.add('<rect x="70" y="%d" width="38" height="30" rx="3" '
              'fill="%s" stroke="%s"/>' % (y, FILLS[CYAN], CYAN))
        d.txt(89, y + 20, ch, 10, TXT, "middle")
        d.wire([(108, y + 15), (280, y + 15)], CYAN, arrow=False)
    # 4:1 mux
    d.add('<path d="M 280 150 L 370 175 L 370 305 L 280 330 Z" '
          'fill="%s" stroke="%s" stroke-width="1.4"/>' % (FILLS[BLUE], BLUE))
    d.txt(325, 240, "P:1", 9, TXT, "middle")
    d.wire([(325, 330), (325, 358)], VIOLET, arrow=True)
    d.txt(325, 374, "δ", 9, VIOLET, "middle")
    d.txt(430, 140, "逻辑列（δ=2 示例）", 8.5, DIM)
    for k, ch in enumerate("cdab"):
        y = 160 + k * 40
        d.add('<rect x="430" y="%d" width="38" height="30" rx="3" '
              'fill="%s" stroke="%s"/>' % (y, FILLS[GREEN], GREEN))
        d.txt(449, y + 20, ch, 10, TXT, "middle")
        d.wire([(370, y + 15), (430, y + 15)], GREEN, arrow=True)
    d.txt(490, 200, "req_w[i][j] =", 9, TXT)
    d.txt(490, 218, "  req_pad[i][(j+δ)%P]", 9, TXT)
    d.txt(490, 242, "逆旋转：", 9, TXT)
    d.txt(490, 260, "  match[i][j] =", 9, TXT)
    d.txt(490, 278, "  grant_w[i][(j-δ)%P]", 9, TXT)
    d.txt(490, 304, "旋转只是 MUX，不改变", 8.5, DIM)
    d.txt(490, 320, "匹配结构；δ 只影响优先级", 8.5, DIM)

    # delta register
    d.region(800, 100, 760, 300, "δ 寄存器与更新")
    d.dff(860, 160, 120, 84, "δ", "CWP bits")
    d.add('<rect x="1020" y="176" width="90" height="44" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[AMBER], AMBER))
    d.txt(1065, 202, "+1 mod P", 8.5, TXT, "middle")
    d.wire([(980, 202), (1020, 202)], VIOLET, arrow=True)
    d.wire([(1110, 198), (1160, 198), (1160, 150), (920, 150), (920, 160)],
           VIOLET, arrow=True)
    d.txt(1180, 190, "any_req", 8.5, GREEN)
    d.txt(1180, 204, "有请求就转", 8, DIM)
    d.txt(860, 270, "复位 δ=0", 8.5, DIM)
    d.txt(860, 286, "无请求保持（空闲不空转）", 8.5, DIM)
    d.txt(860, 310, "P 个周期覆盖所有对角线", 8.5, GREEN)
    d.txt(860, 326, "所有 row/column 轮获得最高优先级", 8.5, GREEN)
    d.txt(860, 350, "δ 同时送列旋转和逆旋转", 8.5, VIOLET)

    # fairness timeline
    d.region(40, 430, 720, 430, "源侧 / 目的侧时序（4x4，无竞争）")
    # source timeline
    d.txt(60, 466, "源 0 请求全部目的：", 9, CYAN, weight=600)
    for k in range(4):
        x = 90 + k * 150
        d.chip(x, 480, 120, 50, "cycle %d" % k, "δ=%d → dst %d" % (k, k),
               CYAN, title_size=8.5, sub_size=7.5)
        if k < 3:
            d.wire([(x + 120, 505), (x + 150, 505)], CYAN, arrow=True)
    d.txt(60, 552, "→ 目的 0,1,2,3，上升循环", 8.5, GREEN)
    # dest timeline
    d.txt(60, 594, "目的 0 被全部源请求：", 9, AMBER, weight=600)
    seq = [0, 3, 2, 1]
    for k in range(4):
        x = 90 + k * 150
        d.chip(x, 608, 120, 50, "cycle %d" % k, "δ=%d → src %d" % (k, seq[k]),
               AMBER, title_size=8.5, sub_size=7.5)
        if k < 3:
            d.wire([(x + 120, 633), (x + 150, 633)], AMBER, arrow=True)
    d.txt(60, 680, "→ 源 0,3,2,1，下降循环（同一 δ 的对偶方向）", 8.5, AMBER)
    d.txt(60, 710, "计数公平：每 P 拍每个源/目的各 1 次；", 9, TXT)
    d.txt(60, 728, "严格“都按 0,1,2...”的顺序是 WFA 的取舍：", 8.5, DIM)
    d.txt(60, 744, "两个方向由同一个对角线旋转耦合，必然一升一降。", 8.5, DIM)
    d.txt(60, 772, "极大性（不浪费调度）不受影响。", 9, GREEN)
    d.txt(60, 796, "如需严格双向 RR：加 per-port 指针或用 iSLIP 变体（深度更大）。",
          8.5, AMBER)

    # full crossbar permutation
    d.region(800, 430, 760, 430, "全交叉开关：δ 产生 P 个置换")
    for k in range(4):
        x = 830 + (k % 2) * 360
        y = 470 + (k // 2) * 170
        d.add('<rect x="%d" y="%d" width="300" height="140" rx="6" '
              'fill="rgba(8,51,68,0.25)" stroke="%s"/>' % (x, y, CYAN))
        d.txt(x + 10, y + 18, "δ=%d" % k, 9, CYAN, weight=600)
        for i in range(4):
            for j in range(4):
                on = (j == (i + k) % 4)
                c = GREEN if on else MUTED
                d.add('<rect x="%d" y="%d" width="26" height="26" rx="2" '
                      'fill="%s" stroke="%s"/>'
                      % (x + 20 + j * 32, y + 36 + i * 24,
                         FILLS[GREEN] if on else "none", c))
                if on:
                    d.txt(x + 33 + j * 32, y + 53 + i * 24, "1", 7.5, TXT,
                          "middle")
    d.txt(820, 810, "每拍都是 min(N,M) 个正交 grant；δ 旋转分配", 8.5, DIM)
    d.txt(820, 826, "没有 ITER 收敛过程，第一拍即满", 8.5, GREEN)

    d.render(path, 2.0)


# ===========================================================================
# 04 - no-waste example
# ===========================================================================
def d04(path):
    d = SVG(1500, 950)
    d.txt(30, 38, "“不浪费调度”判定与示例", 20, TXT, weight=700)
    d.txt(30, 58, "允许：S1→B, S3→C, S2 落选（B 已被占）· 禁止：C 空闲但 S3 不调度",
          10.5, DIM)

    # request matrix
    d.region(40, 100, 420, 360, "请求矩阵（N=3, M=3）")
    xs = [150, 230, 310]
    ys = [180, 250, 320]
    for x, c in zip(xs, "ABC"):
        d.txt(x, 160, c, 10, CYAN, "middle", 600)
    for y, c in zip(ys, ["S1", "S2", "S3"]):
        d.txt(100, y + 5, c, 10, CYAN, "middle", 600)
    mat = [[1, 1, 1], [0, 1, 0], [0, 0, 1]]
    for i in range(3):
        for j in range(3):
            d.add('<rect x="%d" y="%d" width="56" height="46" rx="3" '
                  'fill="%s" stroke="%s"/>'
                  % (xs[j] - 28, ys[i] - 20,
                     FILLS[GREEN] if mat[i][j] else "none",
                     GREEN if mat[i][j] else MUTED))
            d.txt(xs[j], ys[i] + 4, "1" if mat[i][j] else "0", 11,
                  TXT if mat[i][j] else MUTED, "middle")
    d.txt(60, 410, "S1 → {A,B,C}", 9, TXT)
    d.txt(60, 428, "S2 → {B}", 9, TXT)
    d.txt(60, 446, "S3 → {C}", 9, TXT)

    # stage trace
    d.region(500, 100, 430, 360, "一种波前顺序（示意）")
    steps = [
        ("① 轮到 (S1,B)", "R=1, N=1, W=1 → G=1", "S1/B 被占用", GREEN),
        ("② 轮到 (S2,B)", "B 已占用：N/W=0", "G=0（合法落选）", AMBER),
        ("③ 轮到 (S3,C)", "C 仍空闲：G=1", "S3/C 被占用", GREEN),
    ]
    for k, (t, eq, res, c) in enumerate(steps):
        y = 140 + k * 100
        d.add('<rect x="520" y="%d" width="390" height="84" rx="5" '
              'fill="%s" stroke="%s"/>' % (y, FILLS.get(c, FILLS[MUTED]), c))
        d.txt(534, y + 20, t, 9.5, c, weight=600)
        d.txt(534, y + 40, eq, 8.5, TXT)
        d.txt(534, y + 58, res, 8.5, DIM)
    d.txt(520, 444, "结果：S1→B, S3→C, S2 空闲；B 忙，所以 S2 落选合法", 8.5, GREEN)

    # allowed / forbidden
    d.region(960, 100, 500, 220, "允许（极大）", GREEN)
    d.txt(980, 132, "S1→B, S3→C, S2 空闲", 10, TXT, weight=600)
    d.txt(980, 154, "检查每个“落选源”：", 8.5, DIM)
    d.txt(980, 174, "S2 只请求 B，B 已被 S1 占用 → OK", 8.5, GREEN)
    d.txt(980, 194, "没有“两端都空闲”的请求对", 8.5, GREEN)
    d.txt(980, 214, "size=2（不是最大，但极大）", 8.5, AMBER)

    d.region(960, 340, 500, 150, "禁止（非极大）", ROSE)
    d.txt(980, 372, "S1→B, S2 空闲, S3 空闲", 10, TXT, weight=600)
    d.txt(980, 394, "S3 请求 C，且 C 空闲、S3 空闲", 8.5, ROSE)
    d.txt(980, 414, "存在 (i,j): req=1 & src idle & dst idle", 8.5, ROSE)
    d.txt(980, 434, "这就是“明明出口没被占用，入口还不调度”", 8.5, ROSE)
    d.txt(980, 454, "size=1，非极大 → 不允许", 8.5, ROSE)

    # formula / criterion
    d.region(40, 500, 1420, 150, "判定公式（每一拍、每个 N/M 组合）")
    d.txt(60, 540, "error  <=>  exists (i,j):  i_src_dest_req[i][j] = 1", 11, TXT)
    d.txt(60, 568, "                              and o_grant_src_vld[i] = 0", 11, TXT)
    d.txt(60, 596, "                              and o_grant_dest_vld[j] = 0", 11, TXT)
    d.txt(850, 560, "等价于：输出匹配是极大的", 10, GREEN, weight=600)
    d.txt(850, 584, "（不存在长度 1 的增广路）", 8.5, DIM)
    d.txt(850, 606, "不是要求最大匹配（size 最大）", 8.5, AMBER)

    # maximum comparison
    d.region(40, 690, 1420, 220, "三种匹配对比")
    headers = ["匹配", "size", "极大？", "允许？", "说明"]
    xs = [70, 330, 430, 550, 690]
    for x, h in zip(xs, headers):
        d.txt(x, 724, h, 9, CYAN, weight=600)
    rows = [
        ("S1→A, S2→B, S3→C", "3", "是", "是", "最大匹配（WFA 不追求）", GREEN),
        ("S1→B, S3→C, S2 空", "2", "是", "是", "B 忙，S2 合法落选", AMBER),
        ("S1→B, S2 空, S3 空", "1", "否", "否", "C 空闲却未调度", ROSE),
    ]
    for k, (m, sz, mx, ok, note, c) in enumerate(rows):
        y = 760 + k * 42
        d.txt(70, y, m, 9, TXT)
        d.txt(330, y, sz, 9, TXT)
        d.txt(430, y, mx, 9, c, weight=600)
        d.txt(550, y, ok, 9, c, weight=600)
        d.txt(690, y, note, 8.5, DIM)
        d.add('<line x1="60" y1="%d" x2="1440" y2="%d" stroke="%s" '
              'stroke-width="0.4"/>' % (y + 12, y + 12, MUTED))
    d.txt(70, 894, "WFA 只保证第 2 行这种“极大”性质；第 1 行的最大性不是目标。",
          8.5, DIM)

    d.render(path, 2.0)


# ===========================================================================
# 05 - depth / area
# ===========================================================================
def d05(path):
    d = SVG(1500, 900)
    d.txt(30, 38, "深度 / 面积指标与优化方向", 20, TXT, weight=700)
    d.txt(30, 58, "指标：Yosys generic gate levels（ltp -noff），目标 ≤ 40；"
                  "本变体目标 8x8..11x9", 10.5, DIM)

    # bar chart
    d.region(40, 100, 800, 500, "逻辑级数（越低越好）")
    rows = [
        ("旧 iSLIP+fill 10x10", 300, ROSE),
        ("默认 11x9", 38, GREEN),
        ("默认 9x11", 37, GREEN),
        ("默认 10x10", 35, GREEN),
        ("默认 8x8", 30, GREEN),
    ]
    maxv = 300
    for k, (name, val, c) in enumerate(rows):
        y = 150 + k * 62
        d.txt(60, y + 14, name, 9, TXT)
        w = 480 * val / maxv
        d.add('<rect x="300" y="%d" width="%.1f" height="24" rx="3" '
              'fill="%s" stroke="%s" opacity="0.85"/>'
              % (y, w, FILLS.get(c, FILLS[MUTED]), c))
        d.txt(310 + w, y + 17, str(val), 9, c, weight=600)
    # target line (40)
    tx = 300 + 480 * 40 / maxv
    d.wire([(tx, 135), (tx, 500)], ROSE, arrow=False, dash="5,4")
    d.txt(tx + 8, 130, "目标 40", 8.5, ROSE)
    d.txt(60, 560, "旧设计 300 级 → 默认 30-38 级；10x10 从 300 降到 35。", 9, GREEN)
    d.txt(60, 580, "8x8/10x10/9x11/11x9 全部达标；16x16 不在本变体目标内。", 9, GREEN)

    # table
    d.region(880, 100, 580, 500, "配置明细")
    heads = ["配置", "P", "cells", "级数", "状态"]
    xs = [900, 1000, 1090, 1230, 1340]
    for x, h in zip(xs, heads):
        d.txt(x, 136, h, 9, CYAN, weight=600)
    data = [
        ("8x8", "8", "5341", "30", GREEN),
        ("10x10", "10", "8902", "35", GREEN),
        ("9x11", "11", "8906", "37", GREEN),
        ("11x9", "11", "9212", "38", GREEN),
    ]
    for k, (cfg, p, cells, lv, c) in enumerate(data):
        y = 170 + k * 48
        d.txt(900, y, cfg, 9.5, TXT, weight=600)
        d.txt(1000, y, p, 9, DIM)
        d.txt(1090, y, cells, 9, DIM)
        d.txt(1230, y, lv, 9.5, c, weight=600)
        d.txt(1340, y, "达标" if c == GREEN else "优化", 9, c)
        d.add('<line x1="890" y1="%d" x2="1440" y2="%d" stroke="%s" '
              'stroke-width="0.4"/>' % (y + 12, y + 12, MUTED))
    d.txt(900, 430, "注：Yosys generic cells；默认 = 4 调度 WFA + 单侧 RR 覆盖。", 8, DIM)
    d.txt(900, 446, "覆盖与 WFA 并行；vld 走 token，指针编码是关键路径。", 8, DIM)
    d.txt(900, 480, "深度 = 波前 P 级 + 旋转 MUX", 8.5, TXT)
    d.txt(900, 496, "+ 输出编码；无 ITER/fill。", 8.5, TXT)

    # optimization
    d.region(40, 640, 1420, 230, "目标与结论")
    cards = [
        ("P ≤ 10（8x8, 10x10）", "已 ≤40，保持单拍", "35 / 30 级", GREEN),
        ("P = 11（9x11, 11x9）", "37 / 38 级；11x9 用转置", "已达标", GREEN),
        ("16x16", "不在本变体目标内", "如需 16x16，改用 2 拍流水 / 分层", MUTED),
    ]
    for k, (t, s1, s2, c) in enumerate(cards):
        x = 60 + k * 460
        d.add('<rect x="%d" y="680" width="430" height="160" rx="8" '
              'fill="%s" stroke="%s"/>' % (x, FILLS.get(c, FILLS[MUTED]), c))
        d.txt(x + 16, 710, t, 10, c, weight=600)
        d.txt(x + 16, 736, s1, 9, TXT)
        d.txt(x + 16, 760, s2, 9, DIM)
        d.txt(x + 16, 796, "取舍：" + ("无" if c == GREEN else
                                      ("latency/面积/连线" if c == ROSE else "少量逻辑重排")),
              8.5, DIM)
    d.txt(60, 856, "本变体聚焦 8x8..11x9；16x16 留作 2 拍流水 / 4x4 分层扩展。", 8.5, TXT)

    d.render(path, 2.0)



# ===========================================================================
# 06 - single-source / single-destination fairness override
# ===========================================================================
def d06(path):
    d = SVG(1500, 920)
    d.txt(30, 38, "单源 / 单目的严格 RR 覆盖（与 WFA 并行）", 20, TXT, weight=700)
    d.txt(30, 58, "一般混合流量走 WFA；只有一个源或一个目的有请求时，RR 覆盖严格轮询",
          10.5, DIM)

    # ---- source side ----
    d.region(40, 100, 690, 330, "单源：只有一个 src 有请求", CYAN)
    d.txt(60, 132, "src_any[i] = |eff_req[i][*]   →   src_onehot = (仅一位为 1)",
          8.5, DIM)
    # per-source selector (one expanded)
    d.txt(60, 168, "每个源一个 RR 选择器（图中展开 src i）", 9, CYAN, weight=600)
    d.chip(60, 190, 120, 50, "a_ptr[i]", "CWM bits", VIOLET, title_size=8.5,
           sub_size=7.5)
    d.txt(200, 210, "row_req[i][M]", 8.5, CYAN)
    d.add('<rect x="200" y="222" width="120" height="34" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[GREEN], GREEN))
    d.txt(260, 243, "j >= a_ptr[i]", 8, TXT, "middle")
    d.txt(335, 243, "mask_hi", 8, GREEN)
    d.andg(430, 240, 2, GREEN)
    d.txt(430, 218, "req_hi / req_lo", 8, DIM, "middle")
    d.add('<rect x="480" y="222" width="120" height="34" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[AMBER], AMBER))
    d.txt(540, 243, "lowest_set", 8, TXT, "middle")
    d.txt(600, 220, "s_pick[i]", 8, AMBER)
    d.andg(660, 320, 2, GREEN)
    d.txt(600, 306, "src_any[i]", 8, CYAN, "middle")
    d.wire([(620, 312), (633, 313)], CYAN, arrow=True)
    d.wire([(180, 215), (200, 215), (200, 232)], CYAN, arrow=True)
    d.wire([(320, 239), (403, 239), (403, 233)], GREEN, arrow=True)
    d.wire([(458, 240), (480, 240)], GREEN, arrow=True)
    d.wire([(600, 240), (620, 240), (620, 327), (633, 327)], AMBER, arrow=True)
    d.wire([(688, 320), (710, 320)], GREEN, arrow=True)
    d.txt(660, 350, "src_ov[i][*]", 8, GREEN, "middle")
    d.txt(60, 300, "无竞争时：src0 请求 even dests", 8.5, DIM)
    d.txt(60, 320, "s_pick = 0,2,4,...（指针跳过未请求）", 8.5, GREEN)
    d.txt(60, 340, "a_ptr ← 匹配目的 +1（仅覆盖生效时）", 8.5, VIOLET)
    d.txt(60, 370, "源序列严格上升循环，例如 0,2,4,6...", 9, TXT)
    d.txt(60, 388, "42 项严格测试全部通过", 8.5, GREEN)

    # ---- destination side ----
    d.region(760, 100, 700, 330, "单目的：只有一个 dst 有请求", AMBER)
    d.txt(780, 132, "dst_any[j] = |eff_req[*][j]   →   dst_onehot = (仅一位为 1)",
          8.5, DIM)
    d.txt(780, 168, "每个目的一个 RR 选择器（图中展开 dst j）", 9, AMBER, weight=600)
    d.chip(780, 190, 120, 50, "g_ptr[j]", "CWN bits", VIOLET, title_size=8.5,
           sub_size=7.5)
    d.txt(920, 210, "col_req[j][N]", 8.5, AMBER)
    d.add('<rect x="920" y="222" width="120" height="34" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[GREEN], GREEN))
    d.txt(980, 243, "i >= g_ptr[j]", 8, TXT, "middle")
    d.txt(1055, 243, "mask_hi", 8, GREEN)
    d.andg(1150, 240, 2, GREEN)
    d.txt(1150, 218, "req_hi / req_lo", 8, DIM, "middle")
    d.add('<rect x="1200" y="222" width="120" height="34" rx="4" fill="%s" '
          'stroke="%s"/>' % (FILLS[AMBER], AMBER))
    d.txt(1260, 243, "lowest_set", 8, TXT, "middle")
    d.txt(1320, 220, "d_pick[j]", 8, AMBER)
    d.andg(1380, 320, 2, GREEN)
    d.txt(1320, 306, "dst_any[j]", 8, AMBER, "middle")
    d.wire([(1340, 312), (1353, 313)], AMBER, arrow=True)
    d.wire([(900, 215), (920, 215), (920, 232)], AMBER, arrow=True)
    d.wire([(1040, 239), (1123, 239), (1123, 233)], GREEN, arrow=True)
    d.wire([(1178, 240), (1200, 240)], GREEN, arrow=True)
    d.wire([(1320, 240), (1340, 240), (1340, 327), (1353, 327)], AMBER, arrow=True)
    d.wire([(1408, 320), (1430, 320)], GREEN, arrow=True)
    d.txt(1380, 350, "dst_ov[*][j]", 8, GREEN, "middle")
    d.txt(780, 300, "无竞争时：全部源请求 dest0", 8.5, DIM)
    d.txt(780, 320, "d_pick = 0,1,2,...（严格上升）", 8.5, GREEN)
    d.txt(780, 340, "g_ptr ← 匹配源 +1（仅覆盖生效时）", 8.5, VIOLET)
    d.txt(780, 370, "目的序列严格上升循环，例如 0,1,2,3...", 9, TXT)
    d.txt(780, 388, "43/42 场景覆盖 all/even/odd", 8.5, GREEN)

    # ---- final mux ----
    d.region(40, 460, 1420, 190, "最终选择：覆盖与 WFA 并行，关键路径不增加", ORANGE)
    d.txt(60, 492, "use_src = src_onehot", 9, CYAN)
    d.txt(60, 512, "use_dst = ~src_onehot & dst_onehot", 9, AMBER)
    d.mux(400, 520, BLUE)
    d.txt(400, 556, "use_src", 8.5, CYAN, "middle")
    d.wire([(70, 512), (368, 512)], CYAN, arrow=True)
    d.txt(220, 502, "src_ov", 8.5, CYAN, "middle")
    d.wire([(70, 528), (368, 528)], AMBER, arrow=True)
    d.txt(220, 546, "dst_ov", 8.5, AMBER, "middle")
    d.wire([(432, 520), (468, 520)], GREEN, arrow=True)
    d.txt(450, 510, "ov_match", 8, GREEN, "middle")
    d.mux(500, 540, BLUE)
    d.txt(500, 576, "use_src|use_dst", 8, CYAN, "middle")
    d.wire([(468, 520), (468, 532), (468, 532)], GREEN, arrow=False)
    d.wire([(468, 532), (468, 532)], GREEN, arrow=False)
    d.wire([(500, 580), (500, 548)], GREEN, arrow=True)
    d.txt(500, 598, "wfa_match", 8, DIM, "middle")
    d.wire([(532, 540), (570, 540)], GREEN, arrow=True)
    d.txt(610, 540, "match_final", 9, GREEN)
    d.txt(60, 600, "final = use_src ? src_ov : (use_dst ? dst_ov : wfa_match)", 9,
          TXT)
    d.txt(60, 620, "单侧覆盖只在 src_onehot / dst_onehot 时生效；其余流量全部走 WFA。",
          8.5, DIM)

    # ---- result table ----
    d.region(40, 680, 1420, 190, "验证结果", GREEN)
    d.txt(60, 712, "严格公平 42/42：单源 all/even/odd + 单目的 all/even/odd × 7 形状",
          9, GREEN)
    d.txt(60, 736, "极大性 18 种 N/M：0 non-max、0 wasted、0 orth", 9, GREEN)
    d.txt(60, 760, "主回归 22 配置：295,797 checks PASS", 9, GREEN)
    d.txt(60, 784, "纯 WFA 的全局 δ 旋转只做计数/覆盖公平；单侧 RR 覆盖负责严格顺序。",
          8.5, DIM)
    d.txt(60, 812, "混合流量仍走 WFA；单源/单目的公平性由覆盖保证。", 8.5, DIM)

    d.render(path, 2.0)



# ===========================================================================
# 07 - fair variant: iSLIP first pass + WFA fill
# ===========================================================================
def d07(path):
    d = SVG(1500, 900)
    d.txt(30, 38, "Fair variant：iSLIP 首轮 + WFA fill", 20, TXT, weight=700)
    d.txt(30, 58, "可选 fair 模式：首轮负责每端口 RR，WFA 只填残差；保证极大/不浪费",
          10.5, DIM)

    # first pass row
    d.chip(40, 120, 150, 56, "eff_req", "N x M", CYAN, title_size=10)
    d.region(220, 100, 560, 160, "iSLIP 首轮：每端口 a_ptr / g_ptr", GREEN)
    d.chip(240, 130, 220, 76, "GRANT  M x RR-N", "g_ptr[j] 轮询源", GREEN,
           title_size=9.5)
    d.chip(510, 130, 220, 76, "ACCEPT  N x RR-M", "a_ptr[i] 轮询目的", GREEN,
           title_size=9.5)
    d.wire([(190, 148), (240, 148)], ORANGE, bus=True, arrow=True)
    d.wire([(460, 168), (510, 168)], GREEN, arrow=True)
    d.txt(488, 158, "grant", 8, DIM, "middle")
    d.chip(820, 130, 170, 56, "first_match", "正交", GREEN, title_size=9.5)
    d.wire([(730, 168), (820, 168)], GREEN, bus=True, arrow=True)
    # register icons
    d.chip(240, 216, 100, 32, "g_ptr", None, VIOLET, title_size=8.5)
    d.chip(510, 216, 100, 32, "a_ptr", None, VIOLET, title_size=8.5)
    d.txt(60, 280, "g_ptr/a_ptr：首轮/最终匹配推进", 8, VIOLET)

    # residual row
    d.chip(40, 350, 190, 70, "src_match / dst_match", "OR 行/列", GREEN,
           title_size=8.5)
    d.chip(280, 350, 190, 70, "res_req", "eff & ~src & ~dst", AMBER,
           title_size=9.5)
    d.chip(520, 330, 300, 110, "WFA fill", "P 级 torus 对角线；只处理残差", GREEN,
           title_size=10)
    d.chip(600, 450, 100, 34, "δ", None, VIOLET, title_size=8.5)
    d.chip(860, 350, 170, 70, "fill_match", "极大 fill", GREEN, title_size=9.5)
    d.wire([(230, 385), (280, 385)], GREEN, arrow=True)
    d.wire([(470, 385), (520, 385)], AMBER, bus=True, arrow=True)
    d.wire([(820, 385), (860, 385)], GREEN, bus=True, arrow=True)
    d.wire([(820, 168), (820, 300)], GREEN, arrow=False)
    d.dot(820, 300, GREEN)
    d.wire([(820, 300), (20, 300), (20, 385), (40, 385)], GREEN, arrow=True)
    d.wire([(820, 300), (820, 615), (300, 615)], GREEN, arrow=True)
    d.tag(500, 292, "first_match", GREEN)

    # merge and pointers
    d.region(220, 560, 700, 150, "合并 / 指针更新", ORANGE)
    d.chip(300, 600, 100, 60, "OR", "first | fill", GREEN, title_size=9)
    d.wire([(945, 385), (945, 655), (300, 655)], GREEN, arrow=True)
    d.chip(440, 610, 160, 54, "match_final", None, GREEN, title_size=9.5)
    d.wire([(400, 640), (440, 640)], GREEN, arrow=True)
    d.chip(620, 600, 260, 74, "a_ptr / g_ptr 更新", "final match -> +1", VIOLET,
           title_size=9)
    d.wire([(600, 640), (620, 640)], GREEN, arrow=True)

    # table / notes
    d.region(980, 100, 480, 610, "对比与验证", CYAN)
    d.txt(1000, 140, "严格单源/单目的 42/42 PASS", 9, GREEN)
    d.txt(1000, 164, "fair 主回归 295,848 checks PASS", 9, GREEN)
    d.txt(1000, 188, "极大性 18/18；4 形状+20k soak PASS", 9, GREEN)
    d.txt(1000, 220, "多源 Jain 平均（10x10）", 9, CYAN, weight=600)
    d.txt(1000, 244, "纯WFA   src 0.819-0.834  dst 0.804-0.891", 8, TXT)
    d.txt(1000, 264, "4调度   src 0.890-0.929  dst 0.918-0.952", 8, GREEN)
    d.txt(1000, 284, "fair    src 0.866-0.895  dst 0.912-0.934", 8, TXT)
    d.txt(1000, 314, "PPA（flatten，generic）", 9, CYAN, weight=600)
    d.txt(1000, 338, "8x8   2790 / 56", 8.5, TXT)
    d.txt(1000, 358, "10x10 4769 / 72", 8.5, TXT)
    d.txt(1000, 378, "9x11  4707 / 72", 8.5, TXT)
    d.txt(1000, 398, "11x9  5071 / 73", 8.5, TXT)
    d.txt(1000, 430, "对比：fast 4调度WFA 8902 / 35", 8.5, DIM)
    d.txt(1000, 450, "旧 iSLIP+fill 11821 / 300", 8.5, DIM)
    d.txt(1000, 482, "fair 不是全流量严格 RR：", 8.5, AMBER)
    d.txt(1000, 500, "首轮 per-port RR + fill-only 端口近似；", 8.5, DIM)
    d.txt(1000, 518, "混合流量比纯 WFA 更公平，但非数学保证。", 8.5, DIM)
    d.txt(1000, 550, "默认仍是 fast WFA+override；", 8.5, TXT)
    d.txt(1000, 568, "fair 通过 -DFAIR_DUT 选择。", 8.5, TXT)
    d.txt(1000, 600, "16x16 不在本变体目标内。", 8.5, MUTED)

    d.render(path, 2.0)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    d00(os.path.join(OUT, "wfa_00_overview.png"))
    d01(os.path.join(OUT, "wfa_01_cell.png"))
    d02(os.path.join(OUT, "wfa_02_diagonal.png"))
    d03(os.path.join(OUT, "wfa_03_rotation.png"))
    d04(os.path.join(OUT, "wfa_04_nowaste.png"))
    d05(os.path.join(OUT, "wfa_05_depth.png"))
    d06(os.path.join(OUT, "wfa_06_fairness.png"))
    d07(os.path.join(OUT, "wfa_07_fair_hybrid.png"))
    print("done")
