#!/usr/bin/env python3
"""NEON DRIFT v7 — 磁轨 / 鹰隼 / 回响: hero sprites (18x18 x2 frames) + 12 skill icons (32x32).
Writes art/heroes4.png (64px wide atlas, rows packed top-to-bottom with 1px gap).
Row order MUST match HERO_ROWS4 in game/consts.gd.   Usage: python3 tools/gen_heroes4.py [out.png]
Reuses the drawing helpers of tools/gen_heroes3.py (pixel, line, disc, ring, arc, body, icon ...)."""
import math, os, sys
from PIL import Image

_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen_heroes3.py"), encoding="utf-8").read()
exec(_src[:_src.index("# ---------- sprites")])                     # helpers + ROWS + save()
exec(_src[_src.index("def icon("):_src.index("ICE = ")])            # icon frame painter

# ---------- sprites (facing right) ----------
def rail(f):
    img = new(18, 18)
    body(img, polygon(6, 6.6, 0.0), 7.5, 9, hexc("a8c8ff"), hexc("2a4a9a"))
    # twin rails on the shoulders, crackling
    for y in (4, 14):
        line(img, 4, y, 15, y, OUTLINE); line(img, 5, y, 14, y, hexc("6ab0ff"))
    spark = [(16, 4), (16, 14)] if f == 0 else [(17, 5), (16, 13)]
    for (x, y) in spark: px(img, x, y, WHITE)
    disc(img, 8, 9, 2.2, hexc("e8f0ff")); disc(img, 8, 9, 1.0, hexc("4aa8ff"))
    if f == 1: px(img, 3, 9, hexc("8ad8ff"))
    return img
def falcon(f):
    img = new(18, 18)
    # swept wings
    wing = [(2, 3), (9, 8), (2, 15)]
    for (x, y) in wing: line(img, x, y, 9, 9, hexc("c89a2a"))
    disc(img, 8, 9, 4.8, OUTLINE); disc(img, 8, 9, 4.0, hexc("e0b040")); disc(img, 7, 8, 2.2, hexc("fff0a0"))
    # long rifle to the front
    line(img, 10, 10, 17, 10, OUTLINE); line(img, 10, 9, 16, 9, hexc("4a4a5a"))
    px(img, 17, 9, hexc("ffd23f") if f == 0 else WHITE)
    px(img, 9, 7, OUTLINE)   # eye
    return img
def echo(f):
    img = new(18, 18)
    disc(img, 8, 9, 5.8, OUTLINE); disc(img, 8, 9, 4.9, hexc("a83ab0")); disc(img, 7, 8, 3.0, hexc("f08af8")); disc(img, 6.5, 7.5, 1.3, WHITE)
    # sound waves at the front
    for k in range(2 + f):
        arc(img, 12, 9, 2.0 + k * 1.8, 3.0 + k * 1.8, -1.0, 1.0, hexc("ffc8ff") if k % 2 == 0 else hexc("d860e0"), 16)
    for (x, y) in ([(2, 4), (3, 14)] if f == 0 else [(2, 5), (3, 13)]): px(img, x, y, hexc("f08af8"))
    return img
save("rail", [rail(0), rail(1)], 18, 18)
save("falcon", [falcon(0), falcon(1)], 18, 18)
save("echo", [echo(0), echo(1)], 18, 18)

# ---------- icons ----------
VOLT = ((6, 12, 40), (24, 60, 130)); GOLD = ((40, 28, 6), (120, 84, 16)); SONG = ((30, 6, 34), (100, 24, 110))
# 磁轨: right-click 磁暴冲锋, Q 电磁牵引, E 感应装甲, R 磁极领域
def r_q(img):
    for i in range(5): line(img, 4 + i, 26 - i * 2, 20 + i, 12 - i * 2, hexc("4a8aff") if i % 2 else hexc("8ad8ff"))
    disc(img, 23, 9, 5, OUTLINE); disc(img, 23, 9, 4, hexc("c8e8ff")); disc(img, 23, 9, 2, WHITE)
    for (x, y) in [(28, 4), (29, 13), (18, 3)]: line(img, x, y, x + 2, y - 2, hexc("ffffff"))
save("rail_q", [icon(*VOLT, r_q)], 32, 32)
def r_w(img):
    ring(img, 16, 16, 12, hexc("4a8aff")); ring(img, 16, 16, 8, hexc("8ad8ff"))
    for a in range(6):
        t = a / 6 * 2 * math.pi
        line(img, 16 + math.cos(t) * 13, 16 + math.sin(t) * 13, 16 + math.cos(t) * 5, 16 + math.sin(t) * 5, hexc("c8e8ff"))
    disc(img, 16, 16, 3, WHITE)
save("rail_w", [icon(*VOLT, r_w)], 32, 32)
def r_e(img):
    body(img, polygon(6, 10, 0.0), 16, 16, hexc("8ab0e8"), hexc("2a4a9a"))
    line(img, 10, 16, 22, 16, hexc("e8f0ff")); line(img, 16, 10, 16, 22, hexc("e8f0ff"))
    disc(img, 16, 16, 2, hexc("4aa8ff"))
save("rail_e", [icon(*VOLT, r_e)], 32, 32)
def r_r(img):
    for k in range(3): ring(img, 16, 16, 5 + k * 4, hexc("8ad8ff") if k == 1 else hexc("4a6aff"), 80)
    line(img, 9, 9, 23, 23, hexc("ff6a6a")); line(img, 23, 9, 9, 23, hexc("6ab0ff"))
    disc(img, 16, 16, 2.5, WHITE)
save("rail_r", [icon((4, 8, 30), (30, 50, 140), r_r)], 32, 32)
# 鹰隼: right-click 蓄力狙击, Q 战术翻滚, E 震爆雷, R 穿云狙击
def f2_q(img):
    ring(img, 16, 16, 10, hexc("ffd23f")); ring(img, 16, 16, 4, hexc("fff0a0"))
    line(img, 16, 2, 16, 12, WHITE); line(img, 16, 20, 16, 30, WHITE); line(img, 2, 16, 12, 16, WHITE); line(img, 20, 16, 30, 16, WHITE)
    disc(img, 16, 16, 1.5, hexc("ff4a3a"))
save("falcon_q", [icon(*GOLD, f2_q)], 32, 32)
def f2_w(img):
    arc(img, 16, 16, 10, 10, math.pi * 0.2, math.pi * 1.6, hexc("ffd23f"), 50)
    arc(img, 16, 16, 7, 7, math.pi * 0.2, math.pi * 1.6, hexc("fff0a0"), 40)
    line(img, 22, 8, 27, 4, WHITE); line(img, 22, 8, 26, 10, WHITE)
    disc(img, 13, 18, 3, hexc("e0b040"))
save("falcon_w", [icon(*GOLD, f2_w)], 32, 32)
def f2_e(img):
    disc(img, 16, 17, 8, OUTLINE); disc(img, 16, 17, 7, hexc("5a5a6a")); disc(img, 14, 15, 3, hexc("9a9aaa"))
    line(img, 16, 9, 19, 4, hexc("e0b040")); px(img, 20, 3, hexc("ffd23f")); px(img, 21, 2, WHITE)
    for (x, y) in [(6, 8), (26, 10), (5, 26), (27, 26)]: px(img, x, y, hexc("ffd23f"))
save("falcon_e", [icon(*GOLD, f2_e)], 32, 32)
def f2_r(img):
    for k in range(3): line(img, 2, 16 - 1 + k, 30, 16 - 1 + k, hexc("fff0a0") if k == 1 else hexc("ffb030"))
    for (x0, y0) in [(6, 8), (12, 24), (20, 6), (26, 25)]: line(img, x0, y0, x0 + 4, y0, hexc("ffd23f"))
    disc(img, 26, 16, 3, WHITE)
save("falcon_r", [icon((30, 18, 4), (130, 90, 10), f2_r)], 32, 32)
# 回响: right-click 谐振链接, Q 静音波, E 合鸣, R 终曲
def e2_q(img):
    disc(img, 8, 22, 4, hexc("f08af8")); disc(img, 24, 10, 4, hexc("f08af8"))
    for k in range(5): px(img, 11 + k * 2.6, 19 - k * 2.2, WHITE); px(img, 12 + k * 2.6, 19 - k * 2.2, hexc("ffc8ff"))
    ring(img, 8, 22, 6, hexc("d860e0")); ring(img, 24, 10, 6, hexc("d860e0"))
save("echo_q", [icon(*SONG, e2_q)], 32, 32)
def e2_w(img):
    for k in range(4): arc(img, 6, 16, 5 + k * 6, 5 + k * 6, -0.6, 0.6, hexc("ffc8ff") if k % 2 == 0 else hexc("d860e0"), 30)
    line(img, 20, 8, 28, 24, hexc("ff4a6a")); line(img, 21, 8, 29, 24, hexc("ff4a6a"))
save("echo_w", [icon(*SONG, e2_w)], 32, 32)
def e2_e(img):
    for (cx, cy) in [(10, 12), (22, 12), (16, 22)]:
        ring(img, cx, cy, 6, hexc("f08af8")); disc(img, cx, cy, 2, hexc("ffc8ff"))
    disc(img, 16, 15, 1.5, WHITE)
save("echo_e", [icon(*SONG, e2_e)], 32, 32)
def e2_r(img):
    line(img, 11, 24, 11, 8, WHITE); line(img, 23, 21, 23, 6, WHITE); line(img, 11, 8, 23, 6, WHITE); line(img, 11, 9, 23, 7, WHITE)
    disc(img, 8, 24, 3.5, hexc("f08af8")); disc(img, 20, 21, 3.5, hexc("f08af8"))
    for k in range(3): ring(img, 16, 16, 12 + k, hexc("d860e0") if k == 1 else hexc("7a2a8a"), 80)
save("echo_r", [icon((26, 4, 30), (110, 30, 120), e2_r)], 32, 32)

# ---------- pack ----------
W = 64; H = sum(h + 1 for (_, _, h) in ROWS)
atlas = new(W, H); y = 0
for (_, s, h) in ROWS: atlas.paste(s, (0, y)); y += h + 1
out = sys.argv[1] if len(sys.argv) > 1 else "art/heroes4.png"
atlas.save(out)
print("HERO_ROWS4 =", [[n, 18 if h == 18 else 32, h, 2 if h == 18 else 1] for (n, s, h) in ROWS])
print(out, atlas.size)
