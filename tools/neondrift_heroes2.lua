-- NEON DRIFT v5 — 铁壁 / 重锚 / 圣光 / 星语: hero sprites + 16 skill icons (Aseprite script)
-- Packs rows top-to-bottom (1px gap) into a 64px-wide atlas and opens it as a sprite.
-- Row order must match HERO_ROWS2 in main.gd.

local function rgba(r, g, b, a) return app.pixelColor.rgba(r, g, b, a or 255) end
local function hex(h, a) return rgba(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16), a) end
local OUTLINE = hex("0b0d1a")
local WHITE = hex("ffffff")

local strips = {}
local function save(name, frames, w, h)
  local img = Image(w * #frames, h, ColorMode.RGB)
  for i, f in ipairs(frames) do img:drawImage(f, Point((i - 1) * w, 0)) end
  strips[#strips + 1] = { name = name, img = img, h = h }
end

local function px(img, x, y, col)
  x, y = math.floor(x), math.floor(y)
  if x >= 0 and y >= 0 and x < img.width and y < img.height then img:drawPixel(x, y, col) end
end
local function line(img, x0, y0, x1, y1, col)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, n do local t = n == 0 and 0 or i / n; px(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, col) end
end
local function disc(img, cx, cy, r, col)
  for y = math.floor(cy - r), math.ceil(cy + r) do for x = math.floor(cx - r), math.ceil(cx + r) do
    local dx, dy = x + 0.5 - cx, y + 0.5 - cy
    if dx * dx + dy * dy <= r * r then px(img, x, y, col) end
  end end
end
local function ring(img, cx, cy, r, col, steps)
  steps = steps or 64
  for a = 0, steps do local t = a / steps * 2 * math.pi; px(img, cx + math.cos(t) * r, cy + math.sin(t) * r, col) end
end

-- signed distance to a convex polygon (for chunky outlined bodies)
local function polygon(n, r, rot, sx, sy)
  local v = {}
  for i = 0, n - 1 do
    local a = rot + i * 2 * math.pi / n
    v[#v + 1] = { math.cos(a) * r * (sx or 1), math.sin(a) * r * (sy or 1) }
  end
  return v
end
local function fixWinding(v)
  local s = 0
  for i = 1, #v do local a, b = v[i], v[i % #v + 1]; s = s + (a[1] * b[2] - b[1] * a[2]) end
  if s < 0 then local r = {}; for i = #v, 1, -1 do r[#r + 1] = v[i] end; return r end
  return v
end
local function sdf(v, x, y)
  local d = -1e9
  for i = 1, #v do
    local a, b = v[i], v[i % #v + 1]
    local ex, ey = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(ex * ex + ey * ey)
    local dd = (x - a[1]) * (ey / len) + (y - a[2]) * (-ex / len)
    if dd > d then d = dd end
  end
  return d
end
local function body(img, verts, ox, oy, bright, dark)
  verts = fixWinding(verts)
  for y = 0, img.height - 1 do for x = 0, img.width - 1 do
    local d = sdf(verts, x + 0.5 - ox, y + 0.5 - oy)
    if d < -1.6 then px(img, x, y, (x + y < img.width * 0.8) and bright or dark)
    elseif d < -0.5 then px(img, x, y, bright)
    elseif d < 0.5 then px(img, x, y, OUTLINE) end
  end end
end

-- ---------- hero sprites (18x18, facing right, 2 frames) ----------
local function aegis(f)
  local img = Image(18, 18, ColorMode.RGB)
  body(img, polygon(6, 6.6, 0, 1.0, 1.1), 7.5, 9, hex("6a8ab8"), hex("2a3a5a"))
  -- tower shield on the front
  for y = 2, 15 do
    local x0 = 12 + math.floor(math.abs(y - 8.5) * 0.25)
    px(img, x0 - 1, y, OUTLINE); px(img, x0, y, hex("8adfff")); px(img, x0 + 1, y, (f == 1 and y == 8) and WHITE or hex("4aa8ff")); px(img, x0 + 2, y, OUTLINE)
  end
  px(img, 13, 8, WHITE); px(img, 13, 9, WHITE)
  disc(img, 7, 9, 1.6, hex("cfe8ff"))
  return img
end
local function anchor(f)
  local img = Image(18, 18, ColorMode.RGB)
  body(img, polygon(8, 6.8, math.pi / 8), 7.5, 9, hex("d07a2a"), hex("5a2a0a"))
  -- hook arm reaching forward
  line(img, 11, 9, 16, 9, OUTLINE); line(img, 11, 8, 15, 8, hex("b0c0c8"))
  line(img, 16, 6, 16, 12, hex("e0f0ff")); px(img, 15, 5, hex("e0f0ff")); px(img, 15, 13, hex("e0f0ff"))
  px(img, 17, 6, OUTLINE); px(img, 17, 12, OUTLINE)
  -- chain links behind
  for i = 0, 2 do px(img, 2 - i + f, 9 + ((i + f) % 2), hex("8a9aa8")) end
  disc(img, 7, 9, 1.4, hex("ffd08a"))
  return img
end
local function lumen(f)
  local img = Image(18, 18, ColorMode.RGB)
  -- wings
  for i = 0, 3 do
    line(img, 7 - i, 4 + i - f, 3 - i, 2 + i - f, hex("fff2c0"))
    line(img, 7 - i, 14 - i + f, 3 - i, 16 - i + f, hex("fff2c0"))
  end
  disc(img, 9, 9, 5.5, OUTLINE); disc(img, 9, 9, 4.6, hex("ffd23f")); disc(img, 8, 8, 2.6, hex("fff6d0"))
  ring(img, 9, 9, 7.6, (f == 0) and hex("fff2a0") or hex("ffe680"), 48)
  px(img, 14, 9, WHITE); px(img, 15, 9, WHITE)
  return img
end
local function seer(f)
  local img = Image(18, 18, ColorMode.RGB)
  body(img, polygon(4, 7.4, 0, 1.15, 0.8), 8, 9, hex("a070ff"), hex("3a1a6a"))
  -- star at the front
  local sx, sy = 15, 9
  local c = (f == 0) and hex("fff2ff") or hex("ffd0ff")
  px(img, sx, sy, WHITE); px(img, sx - 1, sy, c); px(img, sx + 1, sy, c); px(img, sx, sy - 1, c); px(img, sx, sy + 1, c)
  if f == 1 then px(img, sx - 2, sy, hex("c080ff")); px(img, sx, sy - 2, hex("c080ff")); px(img, sx, sy + 2, hex("c080ff")) end
  disc(img, 7, 9, 1.4, hex("e0c0ff"))
  return img
end
save("aegis", { aegis(0), aegis(1) }, 18, 18)
save("anchor", { anchor(0), anchor(1) }, 18, 18)
save("lumen", { lumen(0), lumen(1) }, 18, 18)
save("seer", { seer(0), seer(1) }, 18, 18)

-- ---------- 32x32 skill icons ----------
local function icon(bg1, bg2, painter)
  local img = Image(32, 32, ColorMode.RGB)
  for y = 0, 31 do for x = 0, 31 do
    local t = (x + y) / 62
    img:drawPixel(x, y, rgba(math.floor(bg1[1] + (bg2[1] - bg1[1]) * t), math.floor(bg1[2] + (bg2[2] - bg1[2]) * t), math.floor(bg1[3] + (bg2[3] - bg1[3]) * t)))
  end end
  painter(img)
  for i = 0, 31 do px(img, i, 0, OUTLINE); px(img, i, 31, OUTLINE); px(img, 0, i, OUTLINE); px(img, 31, i, OUTLINE) end
  for i = 1, 30 do px(img, i, 1, hex("9aa0c0")); px(img, 1, i, hex("9aa0c0")) end
  return img
end
local function shield_shape(img, cx, cy, w, h, c1, c2)
  for y = 0, h do
    local ww = (y < h * 0.55) and w or math.floor(w * (1 - (y - h * 0.55) / (h * 0.45)))
    for x = -ww, ww do px(img, cx + x, cy + y, (math.abs(x) == ww or y == 0) and OUTLINE or ((x < 0) and c1 or c2)) end
  end
end
local function cross(img, cx, cy, s, t, col)
  for i = -s, s do for k = -t, t do px(img, cx + i, cy + k, col); px(img, cx + k, cy + i, col) end end
end
local function star(img, cx, cy, r, col)
  for a = 0, 4 do
    local t = a / 5 * 2 * math.pi - math.pi / 2
    line(img, cx, cy, cx + math.cos(t) * r, cy + math.sin(t) * r, col)
  end
  disc(img, cx, cy, r * 0.35, col)
end

local BLUE = { { 10, 20, 50 }, { 30, 60, 110 } }
local RUST = { { 40, 18, 6 }, { 100, 50, 14 } }
local GOLD = { { 50, 40, 8 }, { 110, 90, 30 } }
local VIOL = { { 24, 8, 50 }, { 70, 30, 120 } }

-- 铁壁
save("aegis_q", { icon(BLUE[1], BLUE[2], function(img)
  for i = 0, 3 do line(img, 3 + i * 2, 24 - i, 14 + i * 2, 24 - i, hex("4a6a9a")) end
  shield_shape(img, 20, 6, 6, 18, hex("8adfff"), hex("4aa8ff"))
  for _, p in ipairs({ { 28, 8 }, { 29, 14 }, { 27, 20 } }) do line(img, p[1], p[2], p[1] + 2, p[2], hex("ffe680")) end
end) }, 32, 32)
save("aegis_w", { icon(BLUE[1], BLUE[2], function(img)
  ring(img, 16, 16, 12, hex("8adfff")); ring(img, 16, 16, 11, hex("4aa8ff"))
  shield_shape(img, 16, 8, 6, 15, hex("cfe8ff"), hex("8adfff"))
  cross(img, 16, 14, 2, 0, hex("2a5a9a"))
end) }, 32, 32)
save("aegis_e", { icon(BLUE[1], BLUE[2], function(img)
  for y = 6, 26 do for x = 6, 26 do
    if (x == 6 or x == 26 or y == 6 or y == 26) then px(img, x, y, OUTLINE)
    elseif ((x + y) % 6 < 3) then px(img, x, y, hex("6a8ab8")) else px(img, x, y, hex("4a6a9a")) end
  end end
  for x = 6, 26, 5 do px(img, x, 4, hex("6a8ab8")); px(img, x, 5, hex("6a8ab8")) end
  disc(img, 16, 16, 3, hex("cfe8ff"))
end) }, 32, 32)
save("aegis_r", { icon({ 50, 14, 6 }, { 120, 40, 10 }, function(img)
  for k = 0, 2 do ring(img, 16, 16, 6 + k * 4.5, (k == 1) and hex("ffd23f") or hex("ff8a2b"), 80) end
  disc(img, 16, 16, 4, hex("fff2c0"))
  px(img, 16, 13, OUTLINE); px(img, 16, 14, OUTLINE); px(img, 16, 15, OUTLINE); px(img, 16, 17, OUTLINE)
end) }, 32, 32)

-- 重锚
save("anchor_q", { icon(RUST[1], RUST[2], function(img)
  for i = 0, 9 do disc(img, 4 + i * 1.8, 27 - i * 1.8, 1.1, (i % 2 == 0) and hex("8a9aa8") or hex("c8d4dc")) end
  line(img, 22, 4, 22, 18, hex("e0f0ff")); line(img, 23, 4, 23, 18, hex("b0c0c8"))
  for a = 0, 20 do local t = a / 20 * math.pi; px(img, 22.5 + math.cos(t) * 6, 18 + math.sin(t) * 5, hex("e0f0ff")) end
  line(img, 16, 14, 17, 18, hex("e0f0ff")); line(img, 29, 14, 28, 18, hex("e0f0ff"))
  line(img, 19, 7, 26, 7, hex("e0f0ff"))
end) }, 32, 32)
save("anchor_w", { icon(RUST[1], RUST[2], function(img)
  for k = 0, 2 do for a = 0, 40 do local t = a / 40 * math.pi; px(img, 16 + math.cos(t) * (5 + k * 5), 24 - math.sin(t) * (3 + k * 3), hex("ffb060")) end end
  for x = 3, 28 do px(img, x, 25, hex("5a2a0a")); px(img, x, 26, hex("3a1a06")) end
  line(img, 10, 24, 13, 20, hex("ffd08a")); line(img, 13, 20, 16, 24, hex("ffd08a")); line(img, 18, 24, 21, 19, hex("ffd08a")); line(img, 21, 19, 24, 24, hex("ffd08a"))
end) }, 32, 32)
save("anchor_e", { icon(RUST[1], RUST[2], function(img)
  disc(img, 16, 16, 10, OUTLINE); disc(img, 16, 16, 9, hex("a0602a")); disc(img, 16, 16, 4, hex("3a1a06"))
  for a = 0, 7 do local t = a / 8 * 2 * math.pi; disc(img, 16 + math.cos(t) * 10, 16 + math.sin(t) * 10, 2, hex("c07a3a")) end
  for _, p in ipairs({ { 11, 12 }, { 20, 21 }, { 13, 22 }, { 22, 11 } }) do px(img, p[1], p[2], hex("5a8a7a")) end
end) }, 32, 32)
save("anchor_r", { icon({ 20, 8, 4 }, { 60, 24, 8 }, function(img)
  for k = 0, 2 do for a = 0, 100 do
    local t = a / 100 * 2 * math.pi
    local r = 13 - k * 3.5 - a / 100 * 3
    px(img, 16 + math.cos(t + k * 2) * r, 16 + math.sin(t + k * 2) * r, (k == 1) and hex("ffd08a") or hex("ff8a2b"))
  end end
  disc(img, 16, 16, 3.5, OUTLINE); disc(img, 16, 16, 2, hex("ffd23f"))
end) }, 32, 32)

-- 圣光
save("lumen_q", { icon(GOLD[1], GOLD[2], function(img)
  disc(img, 16, 16, 11, hex("6a5a1a"))
  cross(img, 16, 16, 9, 3, OUTLINE); cross(img, 16, 16, 8, 2, hex("6aff8a")); cross(img, 16, 16, 7, 0, WHITE)
end) }, 32, 32)
save("lumen_w", { icon(GOLD[1], GOLD[2], function(img)
  for i = 0, 6 do line(img, 16 + (i - 3) * 2, 2, 16 + (i - 3) * 3, 22, (i == 3) and WHITE or hex("ffe680")) end
  for k = 0, 1 do for a = 0, 40 do local t = a / 40 * 2 * math.pi; px(img, 16 + math.cos(t) * (10 - k * 3), 24 + math.sin(t) * (3 - k), hex("fff2a0")) end end
end) }, 32, 32)
save("lumen_e", { icon(GOLD[1], GOLD[2], function(img)
  ring(img, 16, 10, 7, hex("fff2a0")); ring(img, 16, 10, 6, hex("ffd23f"))
  disc(img, 16, 21, 5, hex("ffd23f")); disc(img, 15, 20, 2, WHITE)
  for i = 0, 5 do px(img, 6 + i * 4, 28 - (i % 2) * 2, hex("6aff8a")) end
end) }, 32, 32)
save("lumen_r", { icon({ 60, 50, 20 }, { 140, 120, 50 }, function(img)
  for a = 0, 11 do local t = a / 12 * 2 * math.pi; line(img, 16, 16, 16 + math.cos(t) * 14, 16 + math.sin(t) * 14, hex("fff2a0")) end
  disc(img, 16, 16, 6, hex("ffffff")); cross(img, 16, 16, 4, 1, hex("6aff8a"))
  for i = 0, 3 do line(img, 9 - i, 22 + i, 3 - i, 28 + i, hex("fff6d0")); line(img, 23 + i, 22 + i, 29 + i, 28 + i, hex("fff6d0")) end
end) }, 32, 32)

-- 星语
save("seer_q", { icon(VIOL[1], VIOL[2], function(img)
  star(img, 16, 16, 7, hex("fff2ff"))
  for k = 0, 1 do for a = 0, 60 do local t = a / 60 * 2 * math.pi; px(img, 16 + math.cos(t) * (11 + k), 16 + math.sin(t) * (6 + k * 3), hex("b080ff")) end end
end) }, 32, 32)
save("seer_w", { icon(VIOL[1], VIOL[2], function(img)
  disc(img, 16, 16, 11, hex("2a1a5a")); ring(img, 16, 16, 11, hex("c0a0ff")); ring(img, 16, 16, 10, hex("8adfff"))
  star(img, 16, 16, 5, WHITE)
  line(img, 22, 24, 29, 24, hex("8adfff")); line(img, 24, 27, 29, 27, hex("8adfff"))
end) }, 32, 32)
save("seer_e", { icon(VIOL[1], VIOL[2], function(img)
  for k = 0, 2 do for a = 0, 30 do local t = a / 30 * math.pi; px(img, 16 + math.cos(t + math.pi) * (5 + k * 4), 20 + math.sin(t + math.pi) * (5 + k * 4), hex("c080ff")) end end
  star(img, 16, 20, 3, hex("fff2ff"))
  for _, p in ipairs({ { 6, 6 }, { 25, 5 }, { 28, 14 }, { 4, 15 } }) do px(img, p[1], p[2], WHITE) end
end) }, 32, 32)
save("seer_r", { icon({ 10, 4, 30 }, { 50, 20, 100 }, function(img)
  for k = 0, 3 do ring(img, 16, 16, 4 + k * 3, (k % 2 == 0) and hex("c0a0ff") or hex("6a4aff"), 70) end
  star(img, 16, 16, 4, WHITE)
  for _, p in ipairs({ { 5, 5 }, { 27, 6 }, { 26, 26 }, { 6, 26 } }) do px(img, p[1], p[2], hex("fff2ff")) end
end) }, 32, 32)

-- ---------- pack ----------
local W, H = 64, 0
for _, s in ipairs(strips) do H = H + s.h + 1 end
local atlas = Image(W, H, ColorMode.RGB)
local yy = 0
for _, s in ipairs(strips) do atlas:drawImage(s.img, Point(0, yy)); yy = yy + s.h + 1 end
local spr = Sprite(W, H, ColorMode.RGB)
spr:newCel(spr.layers[1], spr.frames[1], atlas, Point(0, 0))
app.refresh()
