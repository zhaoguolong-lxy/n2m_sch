#!/usr/bin/env python3
"""Generate circuit-level PNG diagrams for the fair_arbiter design.

Output: diagram/circuit/*.png  (rendered directly from an internal SVG model,
so no SVG file is produced).  Run:  python scripts/gen_circuit_diagrams.py
"""
import math
import os

import cairosvg

# ---------------------------------------------------------------------------
# palette / style
# ---------------------------------------------------------------------------
BG      = "#0f172a"
GRID    = "#1e293b"
TXT     = "#e2e8f0"
DIM     = "#94a3b8"
MUTED   = "#64748b"
CYAN    = "#22d3ee"
GREEN   = "#34d399"
VIOLET  = "#a78bfa"
AMBER   = "#fbbf24"
ROSE    = "#fb7185"
BLUE    = "#60a5fa"
ORANGE  = "#fb923c"
WIRE    = "#7c8ba1"
FONT    = "Microsoft YaHei, SimHei, JetBrains Mono, Consolas, monospace"

FILLS = {
    CYAN:   "rgba(8,51,68,0.42)",
    GREEN:  "rgba(6,78,59,0.42)",
    VIOLET: "rgba(76,29,149,0.38)",
    AMBER:  "rgba(120,53,15,0.30)",
    ROSE:   "rgba(136,19,55,0.36)",
    BLUE:   "rgba(30,64,175,0.32)",
    ORANGE: "rgba(124,45,18,0.30)",
    MUTED:  "rgba(30,41,59,0.55)",
}
MARKERS = {
    WIRE: "arw-slate", CYAN: "arw-cyan", GREEN: "arw-green",
    VIOLET: "arw-violet", AMBER: "arw-amber", ROSE: "arw-rose",
    BLUE: "arw-blue", ORANGE: "arw-orange", MUTED: "arw-slate",
}


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def tw(s, size):
    """Rough text width in px (CJK = 1.0 em, latin = 0.58 em)."""
    w = 0.0
    for ch in str(s):
        w += (1.0 if ord(ch) > 0x2e80 else 0.58) * size
    return w


class SVG:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.parts = []

    # -- primitives --------------------------------------------------------
    def add(self, s):
        self.parts.append(s)

    def raw(self):
        defs = ['<defs>',
                '<pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">'
                '<path d="M 40 0 L 0 0 0 40" fill="none" stroke="%s" stroke-width="0.5"/>'
                '</pattern>' % GRID]
        for color, mid in MARKERS.items():
            defs.append(
                '<marker id="%s" markerWidth="10" markerHeight="7" refX="9" '
                'refY="3.5" orient="auto"><polygon points="0 0,10 3.5,0 7" '
                'fill="%s"/></marker>' % (mid, color))
        defs.append('</defs>')
        body = "\n".join(self.parts)
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
            'font-family="%s">\n%s\n'
            '<rect width="100%%" height="100%%" fill="%s"/>\n'
            '<rect width="100%%" height="100%%" fill="url(#grid)"/>\n'
            '%s\n</svg>' % (self.w, self.h, FONT, "\n".join(defs), BG, body))

    def render(self, path, scale=2.0):
        png = cairosvg.svg2png(bytestring=self.raw().encode("utf-8"),
                               output_width=int(self.w * scale),
                               output_height=int(self.h * scale))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(png)

    # -- text --------------------------------------------------------------
    def txt(self, x, y, s, size=11, fill=TXT, anchor="start", weight=400,
            opacity=1.0):
        self.add('<text x="%.1f" y="%.1f" font-size="%s" fill="%s" '
                 'text-anchor="%s" font-weight="%s" opacity="%s">%s</text>'
                 % (x, y, size, fill, anchor, weight, opacity, esc(s)))

    # -- wires -------------------------------------------------------------
    def wire(self, pts, color=WIRE, bus=False, arrow=True, dash=None):
        d = "M " + " L ".join("%.1f,%.1f" % (p[0], p[1]) for p in pts)
        sw = 2.4 if bus else 1.4
        extra = ' stroke-dasharray="%s"' % dash if dash else ""
        mk = (' marker-end="url(#%s)"' % MARKERS.get(color, "arw-slate")
              if arrow else "")
        self.add('<path d="%s" fill="none" stroke="%s" stroke-width="%s"%s%s/>'
                 % (d, color, sw, extra, mk))

    def dot(self, x, y, color=WIRE):
        self.add('<circle cx="%.1f" cy="%.1f" r="2.6" fill="%s"/>'
                 % (x, y, color))

    def tag(self, x, y, s, color=DIM, size=8.5, anchor="middle"):
        w = tw(s, size) + 8
        h = size + 6
        x0 = x - w / 2 if anchor == "middle" else x - 3
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                 'rx="2" fill="%s" opacity="0.92"/>' % (x0, y - h + 3, w, h, BG))
        self.txt(x, y, s, size=size, fill=color, anchor=anchor)

    # -- boxes -------------------------------------------------------------
    def chip(self, x, y, w, h, title, sub=None, color=CYAN, dashed=False,
             title_size=11, sub_size=8.5, fill=None):
        dash = ' stroke-dasharray="5,4"' if dashed else ""
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="5" '
                 'fill="%s"/>' % (x, y, w, h, BG))
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="5" '
                 'fill="%s" stroke="%s" stroke-width="1.4"%s/>'
                 % (x, y, w, h, fill or FILLS.get(color, FILLS[MUTED]),
                    color, dash))
        if sub:
            self.txt(x + w / 2, y + h / 2 - 4, title, title_size, TXT,
                     "middle", 600)
            self.txt(x + w / 2, y + h / 2 + 11, sub, sub_size, DIM,
                     "middle")
        else:
            self.txt(x + w / 2, y + h / 2 + 4, title, title_size, TXT,
                     "middle", 600)

    def region(self, x, y, w, h, label, color=ORANGE):
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" '
                 'rx="8" fill="none" stroke="%s" stroke-width="1" '
                 'stroke-dasharray="7,4"/>' % (x, y, w, h, color))
        self.txt(x + 10, y + 16, label, 9.5, color, weight=600)

    # -- logic symbols -----------------------------------------------------
    def andg(self, cx, cy, n=2, color=GREEN, label="&"):
        self.add('<path d="M %.1f %.1f L %.1f %.1f A 15 15 0 0 1 %.1f %.1f '
                 'L %.1f %.1f Z" fill="%s" stroke="%s" stroke-width="1.4"/>'
                 % (cx - 16, cy - 15, cx + 2, cy - 15, cx + 2, cy + 15,
                    cx - 16, cy + 15, FILLS[GREEN], color))
        ys = self._pin_ys(cy, n)
        for y in ys:
            self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" '
                     'stroke="%s" stroke-width="1.4"/>'
                     % (cx - 27, y, cx - 16, y, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx + 17, cy, cx + 28, cy, color))
        if label:
            self.txt(cx - 3, cy + 3, label, 7, "#d1fae5", "middle")

    def org(self, cx, cy, n=2, color=GREEN, label="≥1"):
        self.add('<path d="M %.1f %.1f Q %.1f %.1f %.1f %.1f Q %.1f %.1f '
                 '%.1f %.1f Q %.1f %.1f %.1f %.1f Z" fill="%s" stroke="%s" '
                 'stroke-width="1.4"/>'
                 % (cx - 20, cy - 15, cx - 4, cy - 15, cx + 16, cy,
                    cx - 4, cy + 15, cx - 20, cy + 15, cx - 10, cy,
                    cx - 20, cy - 15, FILLS[GREEN], color))
        ys = self._pin_ys(cy, n)
        for y in ys:
            self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" '
                     'stroke="%s" stroke-width="1.4"/>'
                     % (cx - 27, y, cx - 13, y, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx + 16, cy, cx + 28, cy, color))
        if label:
            self.txt(cx + 2, cy + 3, label, 7, "#d1fae5", "middle")

    def notg(self, cx, cy, color=GREEN):
        self.add('<path d="M %.1f %.1f L %.1f %.1f L %.1f %.1f Z" '
                 'fill="%s" stroke="%s" stroke-width="1.4"/>'
                 % (cx - 12, cy - 12, cx + 6, cy, cx - 12, cy + 12,
                    FILLS[GREEN], color))
        self.add('<circle cx="%.1f" cy="%.1f" r="3.6" fill="%s" stroke="%s" '
                 'stroke-width="1.2"/>' % (cx + 10, cy, BG, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx - 24, cy, cx - 12, cy, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx + 14, cy, cx + 24, cy, color))

    def mux(self, cx, cy, color=BLUE, label="2:1"):
        self.add('<path d="M %.1f %.1f L %.1f %.1f L %.1f %.1f L %.1f %.1f Z" '
                 'fill="%s" stroke="%s" stroke-width="1.4"/>'
                 % (cx - 22, cy - 19, cx + 20, cy - 11, cx + 20, cy + 11,
                    cx - 22, cy + 19, FILLS[BLUE], color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx - 32, cy - 8, cx - 22, cy - 8, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx - 32, cy + 8, cx - 22, cy + 8, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx, cy + 28, cx, cy + 19, color))
        self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                 'stroke-width="1.4"/>' % (cx + 20, cy, cx + 31, cy, color))
        self.txt(cx - 1, cy + 3, label, 7, "#dbeafe", "middle")

    def dff(self, x, y, w=88, h=84, title="DFF", sub=None):
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3" '
                 'fill="%s" stroke="%s" stroke-width="1.5"/>'
                 % (x, y, w, h, FILLS[VIOLET], VIOLET))
        self.txt(x + w / 2, y + 22, title, 10, TXT, "middle", 600)
        if sub:
            self.txt(x + w / 2, y + 37, sub, 8, DIM, "middle")
        self.txt(x + 8, y + h / 2 + 4, "D", 9, CYAN, "start", 600)
        self.txt(x + w - 8, y + h / 2 + 4, "Q", 9, CYAN, "end", 600)
        # clock triangle
        self.add('<path d="M %.1f %.1f L %.1f %.1f L %.1f %.1f" fill="none" '
                 'stroke="%s" stroke-width="1.3"/>'
                 % (x + 10, y + h - 4, x + 22, y + h - 10, x + 10, y + h - 16,
                    DIM))
        self.txt(x + 26, y + h - 4, "clk", 7, DIM, "start")

    @staticmethod
    def _pin_ys(cy, n):
        if n == 1:
            return [cy]
        return [cy - 7 + (14.0 * k / (n - 1)) for k in range(n)]


# ===========================================================================
# 00 - overview
# ===========================================================================
def diagram_overview(path):
    d = SVG(1560, 1040)

    d.txt(30, 38, "公平仲裁器 — 总图：从端口到匹配输出的完整数据通路", 20,
          TXT, weight=700)
    d.txt(30, 58, "N 源 × M 目的 · 全部匹配逻辑为组合电路 · g_ptr / a_ptr 是唯一的时序元件 · 每拍输出极大匹配",
          10.5, DIM)

    # ---- input ports ----
    d.chip(30, 92, 150, 36, "clk", None, CYAN)
    d.chip(30, 140, 150, 36, "rst_n  (async, low)", None, CYAN)
    d.chip(30, 196, 215, 70, "i_src_dest_req", "[N-1:0][M-1:0]  N·M 位", CYAN)
    d.chip(30, 286, 215, 52, "i_src_bp [N]", "源反压", CYAN)
    d.chip(30, 352, 215, 52, "i_dest_bp [M]", "目的反压", CYAN)

    # ---- eff_req ----
    d.region(272, 190, 196, 232, "① eff_req 生成")
    d.andg(390, 292, 4)
    for y, lab in ((280, "req[i][j]"), (288, "~src_bp[i]"),
                   (296, "~dst_bp[j]"), (304, "rst_n")):
        pass
    labels = [(266, "req[i][j]"), (282, "~src_bp[i]"),
              (298, "~dst_bp[j]"), (314, "rst_n")]
    ys = SVG._pin_ys(292, 4)
    for (ly, lab), py in zip(labels, ys):
        d.wire([(300, ly), (363, ly), (363, py), (363, py)], CYAN, arrow=False)
        d.txt(304, ly - 3, lab, 7, DIM)
    # simpler straight stubs (the dog-leg above is only visual)
    d.wire([(363, 292), (500, 292)], ORANGE, bus=True)
    d.tag(432, 282, "eff_req  [N·M]", ORANGE)
    d.txt(282, 372, "N·M 个并行 AND4；复位期间恒 0", 8, DIM)
    d.txt(282, 388, "eff_req = req & ~src_bp & ~dst_bp & rst_n", 8, DIM)

    # ---- iSLIP engine ----
    d.region(492, 108, 398, 440, "② iSLIP 引擎 — ITER 轮组合展开", CYAN)
    passes = [
        (150, 100, "Pass 0", "全 1 可用", True),
        (292, 92, "Pass t  (t = 1..ITER-2)", "avail = prev_avail & ~prev_match", False),
        (438, 82, "Pass ITER-1", "最后一轮", False),
    ]
    for (py, ph, title, note, first) in passes:
        d.add('<rect x="506" y="%.1f" width="370" height="%.1f" rx="5" '
              'fill="rgba(8,51,68,0.25)" stroke="%s" stroke-width="1"/>'
              % (py, ph, CYAN))
        d.txt(516, py + 16, title, 9.5, CYAN, weight=600)
        if first:
            d.chip(514, py + 24, 158, 52, "GRANT", "M × RR-N", GREEN)
            d.chip(698, py + 24, 158, 52, "ACCEPT", "N × RR-M", GREEN)
        else:
            d.chip(514, py + 24, 158, 42, "GRANT  M×RR-N", None, GREEN, title_size=9)
            d.chip(698, py + 24, 158, 42, "ACCEPT  N×RR-M", None, GREEN, title_size=9)
        d.wire([(672, py + 50), (698, py + 50)], GREEN, arrow=True)
        d.txt(514, py + ph - 6, note, 7.5, DIM)
    # vertical pass arrows
    d.wire([(690, 250), (690, 292)], ORANGE, arrow=True)
    d.txt(700, 276, "src_match / dst_match → avail", 7, ORANGE)
    d.wire([(690, 384), (690, 438)], ORANGE, arrow=True)
    d.txt(700, 414, "avail 继续收缩", 7, ORANGE)
    # effect req trunk into engine
    d.wire([(468, 292)], MUTED, arrow=False)
    d.wire([(468, 200), (468, 480)], ORANGE, bus=True, arrow=False)
    for py in (200, 318, 462):
        d.wire([(468, py), (506, py)], ORANGE, arrow=True)
    d.wire([(440, 292), (468, 292)], ORANGE, bus=True, arrow=False)
    d.tag(470, 180, "eff_req", ORANGE, anchor="middle")
    # pointer bus into engine bottom
    d.wire([(620, 548), (620, 512)], VIOLET, bus=True, arrow=True)
    d.tag(650, 548, "g_ptr / a_ptr", VIOLET)
    # accept outputs
    d.wire([(876, 200), (876, 470)], ORANGE, bus=True, arrow=False)
    for py in (200, 318, 462):
        d.wire([(876, py), (876, py)], ORANGE, arrow=False)
    d.wire([(876, 335), (905, 335)], ORANGE, bus=True, arrow=True)

    # ---- union ----
    d.chip(905, 292, 128, 86, "OR 归约", "ITER 份 → 1 份", ORANGE)
    d.txt(969, 396, "final_accept", 8, ORANGE, "middle")
    d.wire([(1033, 335), (1075, 335)], ORANGE, bus=True, arrow=True)

    # ---- augment ----
    d.chip(905, 440, 180, 150, "AUGMENT = 1（可选）",
           "长度 3 交换：空闲源借用已匹配", ROSE, dashed=True, title_size=10)
    d.txt(995, 500, "目的；被挤源改投空闲目的", 8, DIM, "middle")
    d.txt(995, 516, "只提升匹配“规模”", 8, DIM, "middle")
    d.txt(995, 532, "极大性由 ⑤ 保证", 8, ROSE, "middle")
    # input eff_req stub
    d.wire([(860, 470), (905, 470)], ORANGE, bus=True, arrow=True)
    d.tag(880, 460, "eff_req", ORANGE)
    # augment output branch down to fill and right to merge
    d.wire([(1085, 515), (1112, 515)], ROSE, bus=True, arrow=False)
    d.dot(1112, 515, ROSE)
    d.wire([(1112, 515), (1132, 515)], ROSE, bus=True, arrow=False)
    d.wire([(1112, 515), (1112, 620)], ROSE, bus=True, arrow=True)

    # ---- fill ----
    d.chip(905, 620, 210, 176, "⑤ 残余填充（始终开启）", None, GREEN, title_size=10)
    xs = [918, 964, 1010, 1056]
    labs = ["i=0", "i=1", "...", "i=N-1"]
    for x, lab in zip(xs, labs):
        d.add('<rect x="%d" y="656" width="40" height="30" rx="3" '
              'fill="rgba(6,78,59,0.5)" stroke="%s" stroke-width="1"/>'
              % (x, GREEN))
        d.txt(x + 20, 676, lab, 7.5, TXT, "middle")
        if x != xs[-1]:
            d.wire([(x + 40, 671), (x + 46, 671)], GREEN, arrow=True)
    d.txt(918, 712, "串行链：free bitmap 逐级收缩", 8, DIM)
    d.txt(918, 728, "cand = ~matched & req & free", 7.5, DIM)
    d.txt(918, 744, "RR-M(a_ptr) → pick；free ^= pick", 7.5, DIM)
    d.txt(918, 766, "只增不减 → 不破坏正交性", 7.5, GREEN)

    # ---- merge ----
    d.chip(1150, 430, 118, 105, "OR 合并", "augment | fill", ORANGE)
    d.org(1209, 492, 2, ORANGE)
    d.wire([(1112, 515), (1132, 515), (1132, 500), (1150, 500)], ROSE, bus=True,
           arrow=True)
    d.wire([(1112, 620), (1112, 620)], GREEN, bus=True, arrow=False)
    d.wire([(1112, 620), (1132, 620), (1132, 515), (1150, 515)], GREEN, bus=True,
           arrow=True)
    d.wire([(1268, 492), (1310, 492), (1310, 560)], ORANGE, bus=True, arrow=True)
    d.tag(1290, 520, "match_accept", ORANGE)

    # ---- output logic ----
    d.chip(1150, 560, 240, 208, "⑥ 输出逻辑", None, ORANGE, title_size=10)
    d.txt(1162, 594, "行 OR  →  o_grant_src_vld[N]", 8, DIM)
    d.txt(1162, 614, "列 OR  →  o_grant_dest_vld[M]", 8, DIM)
    d.txt(1162, 640, "one-hot → binary", 8, DIM)
    d.txt(1162, 656, "  →  o_grant_src_ptr[N][CWM]", 8, DIM)
    d.txt(1162, 676, "  →  o_grant_dest_ptr[M][CWN]", 8, DIM)
    d.txt(1162, 702, "o_grant_rand_vld = match_accept", 7.5, DIM)
    d.txt(1162, 718, "（直接展开为 N×M 位）", 7.5, DIM)

    # ---- output ports ----
    out = [
        (540, 64, "o_grant_rand_vld", "[N·M] 匹配矩阵"),
        (616, 40, "o_grant_src_vld [N]", None),
        (664, 48, "o_grant_src_ptr", "[N][CWM]"),
        (724, 40, "o_grant_dest_vld [M]", None),
        (772, 48, "o_grant_dest_ptr", "[M][CWN]"),
    ]
    for (oy, oh, t, s) in out:
        d.chip(1420, oy, 134, oh, t, s, CYAN, title_size=8.6, sub_size=7.5)
    d.wire([(1390, 620), (1405, 620)], ORANGE, bus=True, arrow=False)
    for oy in (560, 636, 688, 744, 796):
        d.wire([(1405, 620), (1405, oy), (1420, oy)], ORANGE, arrow=True)

    # ---- pointers ----
    d.chip(500, 720, 400, 158, "指针寄存器 — 唯一的时序元件", None, VIOLET,
           title_size=10)
    d.chip(514, 752, 176, 110, "g_ptr [M][CWN]", None, VIOLET, title_size=9)
    d.txt(602, 792, "目的 j 的授权指针", 8, DIM, "middle")
    d.txt(602, 808, "异步复位 → j mod N", 8, DIM, "middle")
    d.txt(602, 824, "仅 Pass 0 命中时推进", 8, VIOLET, "middle")
    d.chip(704, 752, 182, 110, "a_ptr [N][CWM]", None, VIOLET, title_size=9)
    d.txt(795, 792, "源 i 的接受指针", 8, DIM, "middle")
    d.txt(795, 808, "异步复位 → i mod M", 8, DIM, "middle")
    d.txt(795, 824, "填充阶段也用它选目的", 8, VIOLET, "middle")
    d.txt(560, 890, "clk / rst_n", 8, DIM)
    d.wire([(560, 902), (560, 878)], VIOLET, arrow=True)
    # pointer feedback to engine
    d.wire([(560, 720), (560, 548)], VIOLET, bus=True, arrow=True)
    d.tag(560, 700, "g_ptr / a_ptr", VIOLET)
    # pass-0 match index into pointer update
    d.wire([(800, 548), (800, 720)], ROSE, bus=True, arrow=True)
    d.tag(800, 690, "pass0 accept / dst_col", ROSE)
    # a_ptr to fill
    d.wire([(886, 800), (1030, 800), (1030, 796)], VIOLET, bus=True, arrow=False)
    d.wire([(1030, 796), (1030, 796), (1030, 700)], VIOLET, bus=True, arrow=False)
    d.wire([(1030, 700), (1030, 796)], VIOLET, bus=True, arrow=False)
    d.wire([(1030, 796), (1030, 700)], VIOLET, bus=True, arrow=True)
    d.tag(1030, 760, "a_ptr", VIOLET)

    # ---- legend ----
    d.region(30, 720, 430, 210, "图例")
    d.andg(80, 780, 2)
    d.txt(80, 812, "AND", 9, DIM, "middle")
    d.org(180, 780, 2)
    d.txt(180, 812, "OR", 9, DIM, "middle")
    d.mux(290, 780)
    d.txt(290, 812, "2:1 MUX", 9, DIM, "middle")
    d.notg(390, 780)
    d.txt(390, 812, "NOT", 9, DIM, "middle")
    d.dff(58, 835, 84, 64, "DFF", "寄存器")
    d.add('<rect x="205" y="840" width="105" height="52" rx="5" fill="none" '
          'stroke="%s" stroke-width="1" stroke-dasharray="5,4"/>' % ROSE)
    d.txt(257, 870, "可选 / 始终开启", 8, DIM, "middle")
    d.wire([(345, 860), (420, 860)], ORANGE, bus=True, arrow=True)
    d.txt(382, 878, "总线 [W]", 8, DIM, "middle")
    d.txt(50, 918, "深色同色系 = 组合逻辑；紫 = 寄存器", 8, DIM)

    # ---- timing strip ----
    d.region(500, 892, 1035, 124, "单拍时序", AMBER)
    boxes = [
        (516, 914, 320, 76, "T 拍（组合路径）",
         "eff_req → iSLIP×ITER → AUGMENT", "→ 残余填充 → 输出逻辑", GREEN),
        (876, 914, 280, 76, "posedge clk（状态更新）",
         "仅 g_ptr / a_ptr 写入", "匹配结果当拍已有效", VIOLET),
        (1196, 914, 320, 76, "T+1 拍",
         "新指针参与下一轮 grant/accept", "组合逻辑无流水线延迟", CYAN),
    ]
    for (x, y, w, h, t1, t2, t3, c) in boxes:
        d.chip(x, y, w, h, t1, None, c, title_size=9.5)
        d.txt(x + w / 2, y + 46, t2, 7.8, DIM, "middle")
        d.txt(x + w / 2, y + 60, t3, 7.8, DIM, "middle")
    d.wire([(836, 952), (876, 952)], AMBER, arrow=True)
    d.wire([(1156, 952), (1196, 952)], AMBER, arrow=True)

    d.render(path, 2.0)


if __name__ == "__main__":
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "diagram", "circuit")
    diagram_overview(os.path.join(out, "00_overview.png"))
    print("done")
