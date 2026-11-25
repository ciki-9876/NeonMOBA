#!/usr/bin/env python3
"""NEON DRIFT v6 — 霜铠 / 烬星 / 潮歌: hero sprites (18x18 x2 frames) + 12 skill icons (32x32).
Writes art/heroes3.png (64px wide atlas, rows packed top-to-bottom with 1px gap).
Row order MUST match HERO_ROWS3 in main.gd.   Usage: python3 tools/gen_heroes3.py [out.png]
Same drawing vocabulary as tools/neondrift_heroes2.lua (a Python port, so it runs without Aseprite)."""
import math, sys
from PIL import Image

def hexc(h, a=255):
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)
OUTLINE = hexc("0b0d1a"); WHITE = hexc("ffffff")
ROWS = []

def px(img, x, y, c):
    x, y = int(math.floor(x)), int(math.floor(y))
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c)
def line(img, x0, y0, x1, y1, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0)))
    for i in range(n + 1):
        t = 0 if n == 0 else i / n
        px(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)
def disc(img, cx, cy, r, c):
    for y in range(int(math.floor(cy - r)), int(math.ceil(cy + r)) + 1):
        for x in range(int(math.floor(cx - r)), int(math.ceil(cx + r)) + 1):
            dx, dy = x + .5 - cx, y + .5 - cy
            if dx * dx + dy * dy <= r * r: px(img, x, y, c)
def ring(img, cx, cy, r, c, steps=64):
    for a in range(steps + 1):
        t = a / steps * 2 * math.pi
        px(img, cx + math.cos(t) * r, cy + math.sin(t) * r, c)
def arc(img, cx, cy, rx, ry, a0, a1, c, steps=48):
    for a in range(steps + 1):
        t = a0 + (a1 - a0) * a / steps
        px(img, cx + math.cos(t) * rx, cy + math.sin(t) * ry, c)
def polygon(n, r, rot=0.0, sx=1.0, sy=1.0):
    return [(math.cos(rot + i * 2 * math.pi / n) * r * sx, math.sin(rot + i * 2 * math.pi / n) * r * sy) for i in range(n)]
def fix(v):
    s = sum(v[i][0] * v[(i + 1) % len(v)][1] - v[(i + 1) % len(v)][0] * v[i][1] for i in range(len(v)))
    return v[::-1] if s < 0 else v
def sdf(v, x, y):
    d = -1e9
    for i in range(len(v)):
        a, b = v[i], v[(i + 1) % len(v)]
        ex, ey = b[0] - a[0], b[1] - a[1]
        l = math.hypot(ex, ey)
        d = max(d, (x - a[0]) * (ey / l) + (y - a[1]) * (-ex / l))
    return d
def body(img, verts, ox, oy, bright, dark):
    verts = fix(verts)
    for y in range(img.height):
        for x in range(img.width):
            d = sdf(verts, x + .5 - ox, y + .5 - oy)
            if d < -1.6: px(img, x, y, bright if (x + y < img.width * .8) else dark)
            elif d < -.5: px(img, x, y, bright)
            elif d < .5: px(img, x, y, OUTLINE)
def cross(img, cx, cy, s, t, c):
    for i in range(-s, s + 1):
        for k in range(-t, t + 1): px(img, cx + i, cy + k, c); px(img, cx + k, cy + i, c)
def star(img, cx, cy, r, c):
    for a in range(5):
        t = a / 5 * 2 * math.pi - math.pi / 2
        line(img, cx, cy, cx + math.cos(t) * r, cy + math.sin(t) * r, c)
    disc(img, cx, cy, r * .35, c)
def new(w, h): return Image.new("RGBA", (w, h), (0, 0, 0, 0))
def save(name, frames, w, h):
    s = new(w * len(frames), h)
    for i, f in enumerate(frames): s.paste(f, (i * w, 0))
    ROWS.append((name, s, h))

# ---------- sprites (facing right) ----------
def frost(f):
    img = new(18, 18)
    body(img, polygon(8, 6.8, math.pi / 8), 7.5, 9, hexc("bfeaff"), hexc("3a6fa8"))
    # icicle crown + shoulder spikes
    for (x0, y0, x1, y1) in [(5, 3, 4, 0), (8, 2, 8, -1), (11, 3, 13, 0), (11, 14, 13, 17), (5, 15, 4, 17)]:
        line(img, x0, y0, x1, y1, hexc("e8f8ff"))
    # front ice pauldron
    for y in range(5, 13): px(img, 13, y, OUTLINE); px(img, 14, y, hexc("8adfff") if f == 0 else hexc("b8f0ff")); px(img, 15, y, OUTLINE)
    px(img, 14, 8, WHITE); px(img, 14, 9, WHITE)
    disc(img, 7, 9, 1.5, hexc("ffffff"))
    if f == 1: px(img, 4, 6, WHITE); px(img, 9, 12, WHITE)
    return img
def ember(f):
    img = new(18, 18)
    # flame crest
    flame = [(5, 3), (6, 2), (7, 0), (8, 2), (9, 1), (10, 3)] if f == 0 else [(5, 3), (6, 1), (7, 2), (8, 0), (9, 2), (10, 3)]
    for (x, y) in flame: line(img, x, 5, x, y, hexc("ff9a2b")); px(img, x, y, hexc("ffe680"))
    disc(img, 8, 10, 5.4, OUTLINE); disc(img, 8, 10, 4.5, hexc("d8381e")); disc(img, 7, 9, 2.8, hexc("ff8a2b")); disc(img, 6.5, 8.5, 1.4, hexc("ffe680"))
    # staff + orb at front
    line(img, 11, 12, 15, 6, hexc("5a3a2a"))
    disc(img, 15.5, 5.5, 2.2, OUTLINE); disc(img, 15.5, 5.5, 1.5, hexc("ffd23f") if f == 0 else hexc("fff2a0")); px(img, 15, 5, WHITE)
    for (x, y) in ([(3, 13), (13, 14)] if f == 0 else [(4, 14), (12, 15)]): px(img, x, y, hexc("ff8a2b"))
    return img
def tide(f):
    img = new(18, 18)
    off = 0 if f == 0 else 1
    # teal shell body
    disc(img, 8, 9, 6.2, OUTLINE); disc(img, 8, 9, 5.3, hexc("2a8fa8")); disc(img, 7, 8, 3.4, hexc("5fe0d0")); disc(img, 6.5, 7.5, 1.6, hexc("d8fff8"))
    # wave crest on the front
    arc(img, 13 + off * .5, 9, 3.2, 4.5, -math.pi / 2, math.pi / 2, hexc("c8fff4"), 24)
    arc(img, 13 + off * .5, 9, 2.2, 3.2, -math.pi / 2, math.pi / 2, hexc("5fe0d0"), 20)
    # droplets
    for (x, y) in ([(2, 5), (3, 14)] if f == 0 else [(2, 6), (3, 13)]): px(img, x, y, hexc("8adfff"))
    px(img, 15, 5 - off, WHITE)
    return img
save("frost", [frost(0), frost(1)], 18, 18)
save("ember", [ember(0), ember(1)], 18, 18)
save("tide", [tide(0), tide(1)], 18, 18)

# ---------- icons ----------
def icon(b1, b2, painter):
    img = new(32, 32)
    for y in range(32):
        for x in range(32):
            t = (x + y) / 62
            img.putpixel((x, y), (int(b1[0] + (b2[0] - b1[0]) * t), int(b1[1] + (b2[1] - b1[1]) * t), int(b1[2] + (b2[2] - b1[2]) * t), 255))
    painter(img)
    for i in range(32): px(img, i, 0, OUTLINE); px(img, i, 31, OUTLINE); px(img, 0, i, OUTLINE); px(img, 31, i, OUTLINE)
    for i in range(1, 31): px(img, i, 1, hexc("9aa0c0")); px(img, 1, i, hexc("9aa0c0"))
    return img
ICE = ((8, 24, 44), (30, 80, 120)); FIRE = ((44, 12, 6), (120, 36, 10)); SEA = ((6, 30, 36), (20, 90, 100))
def snow(img, cx, cy, r, c):
    for a in range(6):
        t = a / 6 * 2 * math.pi
        line(img, cx, cy, cx + math.cos(t) * r, cy + math.sin(t) * r, c)
        line(img, cx + math.cos(t) * r * .6, cy + math.sin(t) * r * .6, cx + math.cos(t + .6) * r * .85, cy + math.sin(t + .6) * r * .85, c)

# 霜铠
def f_q(img):
    for i in range(4): line(img, 3 + i, 24 - i * 2, 18 + i, 20 - i * 2, hexc("4a8ac8"))
    for k in range(3): line(img, 6 + k * 3, 26 - k, 25 + k * 2, 12 + k * 2, hexc("c8f0ff") if k == 1 else hexc("8adfff"))
    for (x, y) in [(26, 8), (28, 14), (24, 5)]: line(img, x, y, x + 2, y + 2, WHITE)
save("frost_q", [icon(*ICE, f_q)], 32, 32)
def f_w(img):
    disc(img, 16, 16, 11, hexc("1a4a78")); ring(img, 16, 16, 12, hexc("8adfff")); ring(img, 16, 16, 11, hexc("c8f0ff"))
    snow(img, 16, 16, 8, WHITE); disc(img, 16, 16, 2, hexc("8adfff"))
save("frost_w", [icon(*ICE, f_w)], 32, 32)
def f_e(img):
    for y in range(5, 27):
        w = 10 if y < 18 else max(0, 10 - (y - 18) * 1.3)
        for x in range(int(16 - w), int(16 + w) + 1):
            edge = abs(x - 16) >= int(w) or y == 5
            px(img, x, y, OUTLINE if edge else (hexc("8adfff") if x < 16 else hexc("4a8ac8")))
    snow(img, 16, 14, 5, WHITE)
save("frost_e", [icon(*ICE, f_e)], 32, 32)
def f_r(img):
    for k in range(3): ring(img, 16, 16, 5 + k * 4, hexc("c8f0ff") if k == 1 else hexc("4aa8ff"), 80)
    snow(img, 16, 16, 12, WHITE); disc(img, 16, 16, 3, hexc("e8f8ff")); disc(img, 16, 16, 1.5, WHITE)
save("frost_r", [icon((6, 14, 40), (40, 90, 150), f_r)], 32, 32)
# 烬星
def e_q(img):
    for i in range(10): disc(img, 4 + i * 1.6, 27 - i * 1.6, 1 + i * .25, hexc("ff6a1a") if i % 2 else hexc("ffb040"))
    disc(img, 22, 10, 6, OUTLINE); disc(img, 22, 10, 5, hexc("ff8a2b")); disc(img, 22, 10, 3, hexc("ffe680")); disc(img, 21, 9, 1.4, WHITE)
save("ember_q", [icon(*FIRE, e_q)], 32, 32)
def e_w(img):
    ring(img, 16, 16, 12, hexc("ff8a2b")); ring(img, 16, 16, 11, hexc("ffd23f"))
    disc(img, 16, 16, 7, hexc("ff4a1a")); disc(img, 16, 16, 4.5, hexc("ffa030")); disc(img, 16, 16, 2.2, hexc("fff2a0"))
    for a in range(8):
        t = a / 8 * 2 * math.pi; line(img, 16 + math.cos(t) * 8, 16 + math.sin(t) * 8, 16 + math.cos(t) * 13, 16 + math.sin(t) * 13, hexc("ffd23f"))
save("ember_w", [icon(*FIRE, e_w)], 32, 32)
def e_e(img):
    for (cx, cy, r) in [(12, 20, 4), (20, 14, 3), (17, 24, 2), (24, 22, 2)]:
        disc(img, cx, cy, r, hexc("c8381e")); disc(img, cx - 1, cy - 1, max(1, r - 2), hexc("ffb040"))
    for (x, y) in [(8, 8), (14, 5), (25, 8), (6, 15), (27, 28), (10, 28)]: px(img, x, y, hexc("ffe680"))
    line(img, 12, 14, 12, 8, hexc("ff8a2b")); line(img, 20, 9, 20, 5, hexc("ff8a2b"))
save("ember_e", [icon(*FIRE, e_e)], 32, 32)
def e_r(img):
    line(img, 4, 4, 18, 18, hexc("ff4a1a")); line(img, 6, 3, 19, 16, hexc("ff8a2b")); line(img, 3, 6, 16, 19, hexc("ff8a2b"))
    disc(img, 20, 20, 8, OUTLINE); disc(img, 20, 20, 7, hexc("5a2a1a")); disc(img, 19, 19, 4.5, hexc("ff8a2b")); disc(img, 18, 18, 2, hexc("ffe680"))
    for a in range(5): px(img, 8 + a * 4, 27 - (a % 2), hexc("ffb040"))
save("ember_r", [icon((30, 6, 4), (110, 30, 8), e_r)], 32, 32)
# 潮歌
def t_q(img):
    disc(img, 16, 18, 8, hexc("1a6a80")); arc(img, 16, 18, 8, 8, math.pi, 2 * math.pi, hexc("8afff0"), 40)
    for (x, y, r) in [(16, 8, 3), (10, 10, 2), (22, 10, 2)]: disc(img, x, y, r, hexc("5fe0d0"))
    cross(img, 16, 19, 4, 1, WHITE)
    for i in range(5): px(img, 6 + i * 5, 28 - (i % 2), hexc("8afff0"))
save("tide_q", [icon(*SEA, t_q)], 32, 32)
def t_w(img):
    for k in range(4):
        r = 10 - k * 2.4
        arc(img, 16, 16, r, r, k * .9, k * .9 + 4.6, hexc("c8fff4") if k % 2 == 0 else hexc("2ab0b8"), 60)
    disc(img, 16, 16, 2, WHITE)
    for (x, y) in [(5, 6), (27, 9), (26, 26)]: px(img, x, y, hexc("8afff0"))
save("tide_w", [icon(*SEA, t_w)], 32, 32)
def t_e(img):
    for k in range(3):
        for a in range(33):
            t = a / 32 * 2 * math.pi
            px(img, 4 + a * .78, 10 + k * 7 + math.sin(t * 1.5 + k) * 3, hexc("c8fff4") if k == 1 else hexc("5fe0d0"))
    for (x, y) in [(27, 6), (4, 27)]: px(img, x, y, WHITE)
    line(img, 22, 22, 28, 22, hexc("8adfff")); line(img, 24, 25, 28, 25, hexc("8adfff"))
save("tide_e", [icon(*SEA, t_e)], 32, 32)
def t_r(img):
    for k in range(3):
        for a in range(61):
            x = 2 + a * .45
            y = 24 - k * 7 + math.sin(a / 60 * 2 * math.pi * 1.6 + k) * 3
            px(img, x, y, hexc("c8fff4") if k == 0 else hexc("5fe0d0")); px(img, x, y + 1, hexc("1a8a9a"))
    arc(img, 16, 12, 9, 9, math.pi * 1.1, math.pi * 1.9, WHITE, 30)
    star(img, 16, 8, 3, WHITE)
save("tide_r", [icon((4, 20, 40), (20, 80, 130), t_r)], 32, 32)

# ---------- pack ----------
W = 64; H = sum(h + 1 for (_, _, h) in ROWS)
atlas = new(W, H); y = 0
for (_, s, h) in ROWS: atlas.paste(s, (0, y)); y += h + 1
out = sys.argv[1] if len(sys.argv) > 1 else "art/heroes3.png"
atlas.save(out)
print("rows:", [(n, s.width // 18 if n in ("frost", "ember", "tide") else 1) for (n, s, _) in ROWS])
print("HERO_ROWS3 =", [[n, s.width // (1 if h == 32 else 2) if False else (18 if h == 18 else 32), h, 2 if h == 18 else 1] for (n, s, h) in ROWS])
print(out, atlas.size)
