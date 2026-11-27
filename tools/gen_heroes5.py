#!/usr/bin/env python3
"""v8 — 岸垒 / 焰缆 / 归灯 sprites and skill icons.

Writes art/heroes5.png. Keep ROWS in sync with HERO_ROWS5 in game/consts.gd.
"""
import math
import os
import sys

from PIL import Image

_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen_heroes3.py"), encoding="utf-8").read()
exec(_src[:_src.index("# ---------- sprites")])
exec(_src[_src.index("def icon("): _src.index("ICE = ")])


def breakwater(frame):
    img = new(18, 18)
    body(img, polygon(6, 6.8, math.pi / 6), 8, 9, hexc("8de6e9"), hexc("286b80"))
    # Heavy seawall shoulders and a luminous forward-facing shield.
    for y in (4, 13):
        line(img, 3, y, 11, y, OUTLINE)
        line(img, 4, y - 1, 10, y - 1, hexc("4ca8b7"))
    shield = [(11, 5), (16, 6), (16, 12), (13, 15), (10, 12), (10, 7)]
    for i, (x, y) in enumerate(shield):
        nx, ny = shield[(i + 1) % len(shield)]
        line(img, x, y, nx, ny, OUTLINE)
    for y in range(7, 13):
        px(img, 12, y, hexc("b8ffff"))
        px(img, 13, y, hexc("5ad5df") if frame == 0 else hexc("8de6e9"))
    px(img, 7, 8, WHITE)
    px(img, 7, 9, hexc("1c475d"))
    if frame:
        px(img, 15, 4, WHITE)
        px(img, 4, 15, hexc("b8ffff"))
    return img


def cinderline(frame):
    img = new(18, 18)
    # A compact ember core with a cable harpoon extending right.
    body(img, polygon(7, 5.5, math.pi / 7), 7, 9, hexc("ffb24d"), hexc("a53d20"))
    for j in range(3):
        y = 5 + j * 4
        line(img, 3, y, 0, y - 2 + frame, hexc("ff6638"))
        px(img, 0, y - 2 + frame, hexc("ffe29a"))
    line(img, 10, 9, 17, 9, OUTLINE)
    line(img, 10, 8, 16, 8, hexc("ffdf8a"))
    line(img, 16, 8, 14, 6, hexc("ffe29a"))
    line(img, 16, 8, 14, 10, hexc("ffe29a"))
    disc(img, 7, 8, 1.5, WHITE)
    if frame:
        px(img, 12, 6, hexc("fff2c2"))
        px(img, 15, 11, hexc("ff6638"))
    return img


def harborlight(frame):
    img = new(18, 18)
    disc(img, 8, 10, 6.2, OUTLINE)
    disc(img, 8, 10, 5.2, hexc("328f85"))
    disc(img, 7, 9, 3.3, hexc("91f4ce"))
    disc(img, 6.5, 8.5, 1.4, WHITE)
    # Beacon lens and sweeping light.
    line(img, 10, 6, 15, 3, OUTLINE)
    line(img, 11, 7, 17, 5, hexc("c8ffe8"))
    line(img, 11, 9, 17, 9, hexc("71e4bd"))
    disc(img, 14, 4, 2.0, OUTLINE)
    disc(img, 14, 4, 1.2, hexc("fff1a8") if frame == 0 else WHITE)
    for x, y in ([(3, 4), (3, 15)] if frame == 0 else [(2, 5), (4, 14)]):
        px(img, x, y, hexc("a9ffe0"))
    return img


save("breakwater", [breakwater(0), breakwater(1)], 18, 18)
save("cinderline", [cinderline(0), cinderline(1)], 18, 18)
save("harborlight", [harborlight(0), harborlight(1)], 18, 18)

SEA = ((5, 26, 36), (18, 93, 108))
EMBER = ((42, 12, 5), (126, 38, 12))
MINT = ((8, 34, 30), (30, 105, 79))


def bw_w(img):
    # Shield dome and three allied pips.
    for r in (12, 9):
        arc(img, 16, 20, r, r, math.pi, 2 * math.pi, hexc("b8ffff") if r == 9 else hexc("4ec6d4"), 48)
    for x in (8, 16, 24):
        disc(img, x, 22, 2.2, hexc("b8ffff"))
    line(img, 16, 5, 16, 17, WHITE)


def bw_q(img):
    for k in range(4):
        y = 10 + k * 4
        line(img, 3, y + 5, 10, y + 1, hexc("2f8090"))
        line(img, 10, y + 1, 17, y + 5, hexc("7ce5e7"))
        line(img, 17, y + 5, 28, y - 1, hexc("b8ffff"))
    disc(img, 16, 16, 2.5, WHITE)


def bw_e(img):
    body(img, polygon(6, 10, math.pi / 6), 16, 16, hexc("8de6e9"), hexc("286b80"))
    line(img, 16, 7, 16, 25, WHITE)
    line(img, 8, 12, 24, 20, hexc("c8ffff"))
    line(img, 24, 12, 8, 20, hexc("4ec6d4"))


def bw_r(img):
    for k in range(3):
        ring(img, 16, 16, 5 + k * 5, hexc("b8ffff") if k == 1 else hexc("4ec6d4"), 72)
    line(img, 6, 25, 26, 7, WHITE)


def cl_w(img):
    for k in range(4):
        line(img, 4 + k * 2, 27 - k * 3, 24 + k, 8 + k * 2, hexc("ff6438") if k % 2 else hexc("ffd27a"))
    line(img, 22, 7, 28, 4, WHITE)
    line(img, 22, 7, 28, 10, hexc("ffd27a"))
    disc(img, 9, 24, 3, hexc("fff0aa"))


def cl_q(img):
    for r in (4, 8, 12):
        ring(img, 16, 17, r, hexc("ff6a32") if r != 8 else hexc("ffd27a"), 56)
    for a in range(8):
        t = a * math.pi / 4
        line(img, 16 + math.cos(t) * 9, 17 + math.sin(t) * 9, 16 + math.cos(t) * 14, 17 + math.sin(t) * 14, WHITE)
    disc(img, 16, 17, 3, hexc("fff0aa"))


def cl_e(img):
    for i in range(5):
        line(img, 5 + i * 2, 8 + i * 3, 10 + i * 3, 5 + i * 4, hexc("ffd27a") if i % 2 else hexc("ff6a32"))
        line(img, 27 - i * 2, 8 + i * 3, 22 - i * 3, 5 + i * 4, hexc("ff6a32") if i % 2 else hexc("ffd27a"))
    disc(img, 16, 16, 3, WHITE)


def cl_r(img):
    for k in range(3):
        line(img, 3, 8 + k * 3, 28, 8 + k * 3, hexc("ff6a32") if k != 1 else hexc("fff0aa"))
    disc(img, 25, 16, 5, OUTLINE)
    disc(img, 25, 16, 3.5, hexc("ffd27a"))
    for x, y in ((7, 20), (12, 24), (18, 22)):
        px(img, x, y, WHITE)


def hl_w(img):
    # Lighthouse tending a heart.
    for y, w in ((10, 5), (15, 7), (20, 9)):
        line(img, 16 - w // 2, y, 16 + w // 2, y, hexc("9dffe0"))
    line(img, 13, 9, 19, 9, WHITE)
    disc(img, 16, 6, 3, hexc("fff1a8"))
    line(img, 7, 5, 12, 8, hexc("72e1ba"))
    line(img, 25, 5, 20, 8, hexc("72e1ba"))


def hl_q(img):
    for r in (4, 8, 12):
        arc(img, 16, 16, r, r, -0.85, 0.85, hexc("baffdf") if r == 8 else hexc("58cba0"), 40)
        arc(img, 16, 16, r, r, math.pi - .85, math.pi + .85, hexc("baffdf") if r == 8 else hexc("58cba0"), 40)
    line(img, 8, 16, 24, 16, WHITE)
    disc(img, 16, 16, 2, hexc("fff1a8"))


def hl_e(img):
    disc(img, 16, 16, 11, hexc("1d6b57"))
    ring(img, 16, 16, 11, hexc("72e1ba"))
    for x, y in ((10, 14), (22, 14), (16, 22)):
        disc(img, x, y, 2, hexc("baffdf"))
    disc(img, 16, 16, 2, WHITE)


def hl_r(img):
    for k in range(3):
        arc(img, 16, 20, 5 + 5 * k, 4 + 3 * k, math.pi, 2 * math.pi, hexc("baffdf") if k == 1 else hexc("58cba0"), 48)
    disc(img, 16, 11, 5, hexc("fff1a8"))
    disc(img, 16, 11, 2, WHITE)
    for x, y in ((6, 23), (26, 23), (16, 27)):
        px(img, x, y, WHITE)


for name, base, painters in (
    ("breakwater", SEA, (bw_w, bw_q, bw_e, bw_r)),
    ("cinderline", EMBER, (cl_w, cl_q, cl_e, cl_r)),
    ("harborlight", MINT, (hl_w, hl_q, hl_e, hl_r)),
):
    for slot, painter in zip(("w", "q", "e", "r"), painters):
        save(name + "_" + slot, [icon(*base, painter)], 32, 32)

W = 64
H = sum(height + 1 for _, _, height in ROWS)
atlas = new(W, H)
y = 0
for _, sprite, height in ROWS:
    atlas.paste(sprite, (0, y))
    y += height + 1
out = sys.argv[1] if len(sys.argv) > 1 else "art/heroes5.png"
atlas.save(out)
print("HERO_ROWS5 =", [[name, 18 if h == 18 else 32, h, 2 if h == 18 else 1] for name, _, h in ROWS])
print(out, atlas.size)
