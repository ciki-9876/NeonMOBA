-- NEON DRIFT v4 — 绯刃 (Crimson Edge) hero sprite, skill icons and the 血印 status mark (Aseprite script)
-- Packs rows top-to-bottom (1px gap) into a 64px-wide atlas and opens it as a sprite.
-- Row order must match HERO_ROWS in main.gd.

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

local PAL = {
  K = OUTLINE, W = WHITE,
  R = hex("ff3b4e"), r = hex("8c1830"), D = hex("3a0a18"), P = hex("ffb0c0"), G = hex("ff8a9a"), Y = hex("ffd23f"),
}
local function fromMap(rows)
  local h, w = #rows, #rows[1]
  local img = Image(w, h, ColorMode.RGB)
  for y = 1, h do for x = 1, w do
    local col = PAL[rows[y]:sub(x, x)]
    if col then img:drawPixel(x - 1, y - 1, col) end
  end end
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
local function disc(img, cx, cy, r, col)
  for y = math.floor(cy - r), math.ceil(cy + r) do for x = math.floor(cx - r), math.ceil(cx + r) do
    local dx, dy = x + 0.5 - cx, y + 0.5 - cy
    if dx * dx + dy * dy <= r * r then px(img, x, y, col) end
  end end
end

-- ---------- hero: crimson arrowhead with a white-hot katana, cape trailing (faces right) ----------
local blade1 = {
  "..................",
  "..................",
  "....KK............",
  "....KRK...........",
  ".....KRRK.........",
  ".....KrRRKK.......",
  "....KDKrRRRK......",
  "...KDDKrRRGRK.....",
  "...KDDKrrRRRKKKKKK",
  "..KDDDKrrRRWKWWWWP",
  "...KDDKrrRRRKKKKKK",
  "...KDDKrRRGRK.....",
  "....KDKrRRRK......",
  ".....KrRRKK.......",
  ".....KRRK.........",
  "....KRK...........",
  "....KK............",
  "..................",
}
local blade2 = {
  "..................",
  "..................",
  "....KK............",
  "....KRK...........",
  ".....KRRK.........",
  "....KKrRRKK.......",
  "...KDDKrRRRK......",
  "..KDDDKrRRGRK.....",
  "..KDDDKrrRRRKKKKKK",
  ".KDDDDKrrRRWKWWWWW",
  "..KDDDKrrRRRKKKKKK",
  "..KDDDKrRRGRK.....",
  "...KDDKrRRRK......",
  "....KKrRRKK.......",
  ".....KRRK.........",
  "....KRK...........",
  "....KK............",
  "..................",
}
save("blade", { fromMap(blade1), fromMap(blade2) }, 18, 18)

-- ---------- 32x32 skill icons ----------
local function icon(bg1, bg2, painter)
  local img = Image(32, 32, ColorMode.RGB)
  for y = 0, 31 do for x = 0, 31 do
    local t = (x + y) / 62
    img:drawPixel(x, y, rgba(math.floor(bg1[1] + (bg2[1] - bg1[1]) * t), math.floor(bg1[2] + (bg2[2] - bg1[2]) * t), math.floor(bg1[3] + (bg2[3] - bg1[3]) * t)))
  end end
  painter(img)
  for i = 0, 31 do px(img, i, 0, OUTLINE); px(img, i, 31, OUTLINE); px(img, 0, i, OUTLINE); px(img, 31, i, OUTLINE) end
  for i = 1, 30 do px(img, i, 1, hex("b88a92")); px(img, 1, i, hex("b88a92")) end
  return img
end

-- Q 瞬影斩: afterimages streaking right + a long slash
save("b_icon_q", { icon({ 30, 6, 14 }, { 80, 14, 30 }, function(img)
  for i = 0, 2 do
    local x0 = 4 + i * 5
    disc(img, x0 + 2, 22 - i * 2, 3 - i * 0.5, ({ hex("3a0a18"), hex("8c1830"), hex("ff3b4e") })[i + 1])
  end
  for k = -1, 1 do line(img, 6, 26 + k, 28, 6 + k, (k == 0) and WHITE or hex("ff8a9a")) end
  line(img, 9, 27, 28, 9, hex("ff3b4e"))
  for _, p in ipairs({ { 24, 4 }, { 27, 12 }, { 20, 6 }, { 29, 8 } }) do px(img, p[1], p[2], hex("ffd0d8")) end
end) }, 32, 32)

-- W 血誓: blood drop with three orbiting charges
save("b_icon_w", { icon({ 40, 6, 12 }, { 90, 16, 26 }, function(img)
  for y = 6, 25 do
    local w = (y < 15) and math.floor((y - 6) * 0.65) or math.floor(math.sqrt(math.max(0, 49 - (y - 18) * (y - 18))))
    for x = -w, w do px(img, 16 + x, y, (math.abs(x) == w) and OUTLINE or hex("ff3b4e")) end
  end
  disc(img, 14, 18, 2, hex("ffb0c0"))
  for i = 0, 2 do
    local a = i * 2 * math.pi / 3 - math.pi / 2
    disc(img, 16 + math.cos(a) * 12, 16 + math.sin(a) * 12, 2.5, hex("ffd23f"))
    px(img, 16 + math.cos(a) * 12, 16 + math.sin(a) * 12, WHITE)
  end
end) }, 32, 32)

-- E 处决: crossed slashes over a bursting blood mark
save("b_icon_e", { icon({ 26, 4, 10 }, { 70, 10, 20 }, function(img)
  for y = 0, 31 do for x = 0, 31 do
    local d = math.abs(x - 16) + math.abs(y - 16)
    if d <= 8 then px(img, x, y, d == 8 and OUTLINE or (d <= 3 and hex("ff8a9a") or hex("8c1830"))) end
  end end
  for k = -1, 1 do
    line(img, 4 + k, 4, 28 + k, 28, (k == 0) and WHITE or hex("ff3b4e"))
    line(img, 28 + k, 4, 4 + k, 28, (k == 0) and WHITE or hex("ff3b4e"))
  end
  for _, p in ipairs({ { 6, 16 }, { 26, 16 }, { 16, 5 }, { 16, 27 } }) do disc(img, p[1], p[2], 1.2, hex("ff3b4e")) end
end) }, 32, 32)

-- R 千刃·剑舞: a ring of slashes around a vertical blade
save("b_icon_r", { icon({ 20, 4, 16 }, { 60, 8, 40 }, function(img)
  for i = 0, 7 do
    local a = i * math.pi / 4 + 0.3
    local cx, cy = 16 + math.cos(a) * 10, 16 + math.sin(a) * 10
    line(img, cx - math.sin(a) * 4, cy + math.cos(a) * 4, cx + math.sin(a) * 4, cy - math.cos(a) * 4, (i % 2 == 0) and hex("ff3b4e") or hex("ff8a9a"))
  end
  line(img, 16, 5, 16, 24, WHITE); line(img, 15, 7, 15, 24, hex("ffb0c0")); line(img, 17, 7, 17, 24, hex("ffb0c0"))
  line(img, 12, 24, 20, 24, hex("ffd23f")); line(img, 16, 25, 16, 28, hex("8c1830"))
end) }, 32, 32)

-- 血印 status mark: small blood drop
do
  local img = Image(9, 9, ColorMode.RGB)
  local rows = { "....K....", "...KRK...", "...KRK...", "..KRRRK..", ".KRRPRRK.", ".KRRRRRK.", ".KRRRRRK.", "..KRRRK..", "...KKK..." }
  for y = 1, 9 do for x = 1, 9 do
    local col = PAL[rows[y]:sub(x, x)]
    if col then img:drawPixel(x - 1, y - 1, col) end
  end end
  save("mark", { img }, 9, 9)
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
