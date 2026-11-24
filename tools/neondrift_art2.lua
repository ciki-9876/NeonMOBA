-- NEON DRIFT v2 — new enemy archetypes + DOTA-style skill icons (Aseprite script)
-- Packs rows top-to-bottom (1px gap) into a 64px-wide atlas and opens it as a sprite.
-- Row order must match ATLAS2_ROWS in main.gd.

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

-- ---------- convex polygon SDF shapes (same look as v1 enemies) ----------
local function polygon(n, r, rot)
  local v = {}
  for i = 0, n - 1 do
    local a = rot + i * 2 * math.pi / n
    v[#v + 1] = { math.cos(a) * r, math.sin(a) * r }
  end
  return v
end
local function fixWinding(v)
  local s = 0
  for i = 1, #v do local a, b = v[i], v[i % #v + 1]; s = s + (a[1] * b[2] - b[1] * a[2]) end
  if s < 0 then local r = {}; for i = #v, 1, -1 do r[#r + 1] = v[i] end; return r end
  return v
end
local function sdfPoly(v, px, py)
  local d = -1e9
  for i = 1, #v do
    local a, b = v[i], v[i % #v + 1]
    local ex, ey = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(ex * ex + ey * ey)
    local dd = (px - a[1]) * (ey / len) + (py - a[2]) * (-ex / len)
    if dd > d then d = dd end
  end
  return d
end
-- glyph(img, cx, cy, frame) draws the unique inner mark
local function shape(size, verts, bright, dark, coreR, frame, glyph)
  verts = fixWinding(verts)
  local img = Image(size, size, ColorMode.RGB)
  local c = size / 2
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local px, py = x + 0.5 - c, y + 0.5 - c
      local d = sdfPoly(verts, px, py)
      local col = nil
      if d < -1.6 then
        col = dark
        if px + py < -c * 0.55 and d < -2.6 then col = bright end
      elseif d < -0.6 then col = bright
      elseif d < 0.4 then col = OUTLINE end
      local rr = math.sqrt(px * px + py * py)
      if col and d < -1.6 and rr < coreR + frame * 1.1 then col = WHITE end
      if col then img:drawPixel(x, y, col) end
    end
  end
  if glyph then glyph(img, c, frame) end
  return img
end
local function px(img, x, y, col)
  x, y = math.floor(x), math.floor(y)
  if x >= 0 and y >= 0 and x < img.width and y < img.height then img:drawPixel(x, y, col) end
end
local function line(img, x0, y0, x1, y1, col)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, n do local t = n == 0 and 0 or i / n; px(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, col) end
end
local function enemy(name, size, verts, bright, dark, core, glyph)
  save(name, { shape(size, verts, bright, dark, core, 0, glyph), shape(size, verts, bright, dark, core, 1, glyph) }, size, size)
end

-- sentry: octagon with a barrel pointing right
enemy("sentry", 18, polygon(8, 8.4, math.pi / 8), hex("ff8a2b"), hex("7a3a0e"), 1.6, function(img, c, f)
  for x = 9, 17 do px(img, x, 8, OUTLINE); px(img, x, 9, hex("ffd0a0")) end
  px(img, 17, 8, hex("fff2c0")); px(img, 17, 9, hex("fff2c0"))
end)
-- colossus: big armored hexagon with plates
enemy("colossus", 32, polygon(6, 15.2, 0), hex("d0583e"), hex("5a1e14"), 3.2, function(img, c, f)
  for k = 0, 5 do
    local a = k * math.pi / 3 + math.pi / 6
    line(img, c + math.cos(a) * 5, c + math.sin(a) * 5, c + math.cos(a) * 12, c + math.sin(a) * 12, hex("2a0c08"))
  end
end)
-- frenzy beacon: red triangle with inner chevron
enemy("frenzy", 20, polygon(3, 9.6, -math.pi / 2), hex("ff3355"), hex("6a0e1e"), 1.4, function(img, c, f)
  line(img, c - 4, c + 3, c, c - 2 - f, hex("ffd0d8")); line(img, c, c - 2 - f, c + 4, c + 3, hex("ffd0d8"))
end)
-- aegis beacon: blue pentagon with inner shield
enemy("aegis", 20, polygon(5, 9.4, -math.pi / 2), hex("4aa8ff"), hex("0e2e6a"), 0, function(img, c, f)
  for y = -3, 3 do
    local w = (y < 1) and 3 or (3 - (y - 0))
    for x = -w, w do px(img, c + x, c + y, (math.abs(x) == w or y == -3) and WHITE or hex("a8d8ff")) end
  end
end)
-- mender: green octagon with a plus
enemy("mender", 18, polygon(8, 8.2, 0), hex("5dffa0"), hex("10602e"), 0, function(img, c, f)
  local s = 3 + f
  for i = -s, s do px(img, c + i, c, WHITE); px(img, c, c + i, WHITE); px(img, c + i, c - 1, WHITE); px(img, c - 1, c + i, WHITE) end
end)
-- bomber: small yellow diamond with a fuse spark
enemy("bomber", 12, polygon(4, 5.6, 0), hex("ffcc33"), hex("8a5a08"), 1.2 , function(img, c, f)
  px(img, c - 1, 0 + f, hex("ff5a2a")); px(img, c, 0, hex("fff2a0"))
end)
-- hexer: purple pentagon with an X
enemy("hexer", 18, polygon(5, 8.4, math.pi / 2), hex("c060ff"), hex("3a1060"), 0, function(img, c, f)
  line(img, c - 3, c - 3, c + 3, c + 3, WHITE); line(img, c + 3, c - 3, c - 3, c + 3, WHITE)
  if f == 1 then px(img, c, c, hex("ff60ff")) end
end)

-- ---------- 32x32 skill icons ----------
local function icon(bg1, bg2, painter)
  local img = Image(32, 32, ColorMode.RGB)
  for y = 0, 31 do for x = 0, 31 do
    local t = (x + y) / 62
    local r1, g1, b1 = bg1[1], bg1[2], bg1[3]
    local r2, g2, b2 = bg2[1], bg2[2], bg2[3]
    img:drawPixel(x, y, rgba(math.floor(r1 + (r2 - r1) * t), math.floor(g1 + (g2 - g1) * t), math.floor(b1 + (b2 - b1) * t)))
  end end
  painter(img)
  for i = 0, 31 do px(img, i, 0, hex("0b0d1a")); px(img, i, 31, hex("0b0d1a")); px(img, 0, i, hex("0b0d1a")); px(img, 31, i, hex("0b0d1a")) end
  for i = 1, 30 do px(img, i, 1, hex("8a92b8")); px(img, 1, i, hex("8a92b8")) end
  return img
end
local function disc(img, cx, cy, r, col)
  for y = math.floor(cy - r), math.ceil(cy + r) do for x = math.floor(cx - r), math.ceil(cx + r) do
    local dx, dy = x + 0.5 - cx, y + 0.5 - cy
    if dx * dx + dy * dy <= r * r then px(img, x, y, col) end
  end end
end

-- Q: pulse lance — diagonal cyan beam
save("icon_q", { icon({ 10, 18, 46 }, { 20, 60, 90 }, function(img)
  for k = -3, 3 do
    local col = (math.abs(k) <= 1) and WHITE or ((math.abs(k) == 2) and hex("29f3ff") or hex("138a9e"))
    line(img, 3 + k, 28 + k, 28 + k, 3 + k, col)
  end
  disc(img, 7, 25, 3.5, hex("29f3ff")); disc(img, 7, 25, 2, WHITE)
  for _, p in ipairs({ { 20, 8 }, { 24, 15 }, { 14, 6 }, { 27, 20 } }) do px(img, p[1], p[2], hex("c8ffff")) end
end) }, 32, 32)
-- W: phase blink — magenta afterimage + arrow + burst ring
save("icon_w", { icon({ 40, 8, 40 }, { 90, 20, 80 }, function(img)
  for a = 0, 40 do
    local t = a / 40 * 2 * math.pi
    px(img, 21 + math.cos(t) * 8, 11 + math.sin(t) * 8, hex("ff2fd0"))
    px(img, 21 + math.cos(t) * 6, 11 + math.sin(t) * 6, hex("ff9aea"))
  end
  disc(img, 21, 11, 3, WHITE)
  for i = 0, 3 do disc(img, 6 + i * 3, 26 - i * 3, 2.5 - i * 0.4, hex("8a1677")) end
  line(img, 7, 25, 16, 16, hex("ffd0f4")); line(img, 16, 16, 12, 16, hex("ffd0f4")); line(img, 16, 16, 16, 20, hex("ffd0f4"))
end) }, 32, 32)
-- E: overload — yellow lightning bolt on purple
save("icon_e", { icon({ 30, 14, 60 }, { 70, 30, 110 }, function(img)
  local bolt = { { 19, 2 }, { 10, 16 }, { 16, 16 }, { 11, 29 }, { 24, 12 }, { 17, 12 }, { 22, 2 } }
  for i = 1, #bolt - 1 do
    local a, b = bolt[i], bolt[i + 1]
    line(img, a[1], a[2], b[1], b[2], hex("ffd23f")); line(img, a[1] + 1, a[2], b[1] + 1, b[2], hex("fff2a0"))
  end
  for y = 3, 28 do for x = 2, 29 do
    if ((x * 7 + y * 13) % 29 == 0) then px(img, x, y, hex("ffe680")) end
  end end
end) }, 32, 32)
-- R: singularity — black hole with swirling rings
save("icon_r", { icon({ 8, 4, 20 }, { 30, 8, 50 }, function(img)
  for k = 0, 2 do
    for a = 0, 120 do
      local t = a / 120 * 2 * math.pi
      local r = 12 - k * 3 + math.sin(t * 3 + k) * 1.2
      local col = (k == 0) and hex("ff2fd0") or ((k == 1) and hex("29f3ff") or hex("b080ff"))
      px(img, 16 + math.cos(t + k) * r, 16 + math.sin(t + k) * r * 0.8, col)
    end
  end
  disc(img, 16, 16, 4.5, hex("000000")); disc(img, 15, 15, 1.2, hex("40206a"))
end) }, 32, 32)
-- attribute bonus: gold plus
save("icon_attr", { icon({ 40, 30, 10 }, { 90, 70, 20 }, function(img)
  for i = 7, 24 do for w = -2, 2 do px(img, i, 16 + w, hex("ffd23f")); px(img, 16 + w, i, hex("ffd23f")) end end
  for i = 8, 23 do px(img, i, 16, hex("fff2a0")); px(img, 16, i, hex("fff2a0")) end
end) }, 32, 32)

-- ---------- small FX sprites ----------
do -- artillery shell
  local img = Image(8, 8, ColorMode.RGB)
  disc(img, 4, 4, 3.5, OUTLINE); disc(img, 4, 4, 2.6, hex("ff8a2b")); disc(img, 3, 3, 1, hex("fff2c0"))
  save("shell", { img }, 8, 8)
end
do -- stun star
  local img = Image(9, 9, ColorMode.RGB)
  for i = 0, 8 do px(img, i, 4, hex("ffe680")); px(img, 4, i, hex("ffe680")) end
  line(img, 2, 2, 6, 6, hex("fff2a0")); line(img, 6, 2, 2, 6, hex("fff2a0")); px(img, 4, 4, WHITE)
  save("stun", { img }, 9, 9)
end
do -- charged mark (cyan diamond)
  local img = Image(7, 7, ColorMode.RGB)
  for y = 0, 6 do for x = 0, 6 do
    local d = math.abs(x - 3) + math.abs(y - 3)
    if d <= 3 then px(img, x, y, d == 3 and OUTLINE or (d <= 1 and WHITE or hex("29f3ff"))) end
  end end
  save("charge", { img }, 7, 7)
end
do -- silence icon (crossed circle)
  local img = Image(16, 16, ColorMode.RGB)
  for a = 0, 60 do local t = a / 60 * 2 * math.pi; px(img, 8 + math.cos(t) * 6.5, 8 + math.sin(t) * 6.5, hex("c060ff")); px(img, 8 + math.cos(t) * 5.5, 8 + math.sin(t) * 5.5, hex("c060ff")) end
  line(img, 3, 3, 12, 12, WHITE); line(img, 4, 3, 13, 12, WHITE)
  save("silence", { img }, 16, 16)
end

-- ---------- pack ----------
local W, H = 64, 0
for _, s in ipairs(strips) do H = H + s.h + 1 end
local atlas = Image(W, H, ColorMode.RGB)
local yy = 0
for _, s in ipairs(strips) do atlas:drawImage(s.img, Point(0, yy)); yy = yy + s.h + 1 end
local spr = Sprite(W, H, ColorMode.RGB)
spr:newCel(spr.layers[1], spr.frames[1], atlas, Point(0, 0))
app.refresh()
