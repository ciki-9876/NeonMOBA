-- NEON DRIFT pixel art generator (Aseprite script)
-- Builds every sprite as an .aseprite source + exported PNG sheet in ~/NeonDrift/art

local home = os.getenv("HOME")
local OUT = home .. "/NeonDrift/art/"

local function rgba(r, g, b, a) return app.pixelColor.rgba(r, g, b, a or 255) end
local function hex(h, a)
  return rgba(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16), a)
end

local OUTLINE = hex("0b0d1a")
local WHITE = hex("ffffff")

-- collect every sprite strip; they are packed into ONE atlas at the end
local strips = {}
local function save(name, frames, w, h)
  local n = #frames
  local img = Image(w * n, h, ColorMode.RGB)
  for i, f in ipairs(frames) do
    img:drawImage(f, Point((i - 1) * w, 0))
  end
  strips[#strips + 1] = { name = name, img = img, h = h }
end

-- ---------- hand-drawn sprites from ASCII maps ----------
local PAL = {
  ["."] = nil,
  K = OUTLINE, W = WHITE,
  C = hex("29f3ff"), c = hex("138a9e"),
  M = hex("ff2fd0"), m = hex("8a1677"),
  Y = hex("ffd23f"), O = hex("ff8a2b"),
  R = hex("ff3b4e"), r = hex("8c1830"),
}

local function fromMap(rows)
  local h = #rows
  local w = #rows[1]
  local img = Image(w, h, ColorMode.RGB)
  for y = 1, h do
    for x = 1, w do
      local ch = rows[y]:sub(x, x)
      local col = PAL[ch]
      if col then img:drawPixel(x - 1, y - 1, col) end
    end
  end
  return img
end

local ship1 = {
  "................",
  "................",
  "..KK............",
  "..KCK...........",
  "...KCCK.........",
  "...KcCCCKK......",
  "..KMKcCCWWCK....",
  ".KMMKccCCCCCCK..",
  ".KMMKccCCCCCCK..",
  "..KMKcCCWWCK....",
  "...KcCCCKK......",
  "...KCCK.........",
  "..KCK...........",
  "..KK............",
  "................",
  "................",
}
local ship2 = {}
for i, r in ipairs(ship1) do ship2[i] = r end
ship2[7]  = ".MMMKcCCWWCK...."
ship2[8]  = "YMMMKccCCCCCCK.."
ship2[9]  = "YMMMKccCCCCCCK.."
ship2[10] = ".MMMKcCCWWCK...."
save("player", { fromMap(ship1), fromMap(ship2) }, 16, 16)

local heart = {
  ".KK.KK.",
  "KRRKRRK",
  "KRWRRRK",
  "KRRRRRK",
  ".KRRRK.",
  "..KRK..",
  "...K...",
}
local heartEmpty = {}
for i, r in ipairs(heart) do heartEmpty[i] = r:gsub("[RW]", "r") end
save("heart", { fromMap(heart), fromMap(heartEmpty) }, 7, 7)

-- ---------- procedural neon shapes (convex polygon SDF) ----------
local function polygon(n, r, rot)
  local v = {}
  for i = 0, n - 1 do
    local a = rot + i * 2 * math.pi / n
    v[#v + 1] = { math.cos(a) * r, math.sin(a) * r }
  end
  return v
end

local function sdfPoly(v, px, py)
  local d = -1e9
  local n = #v
  for i = 1, n do
    local a, b = v[i], v[i % n + 1]
    local ex, ey = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(ex * ex + ey * ey)
    local nx, ny = ey / len, -ex / len -- outward normal for CCW in screen space (y down)
    local dd = (px - a[1]) * nx + (py - a[2]) * ny
    if dd > d then d = dd end
  end
  return d
end

-- make sure the polygon winds so that normals point outward
local function fixWinding(v)
  local s = 0
  for i = 1, #v do
    local a, b = v[i], v[i % #v + 1]
    s = s + (a[1] * b[2] - b[1] * a[2])
  end
  if s < 0 then
    local r = {}
    for i = #v, 1, -1 do r[#r + 1] = v[i] end
    return r
  end
  return v
end

local function shape(size, verts, bright, dark, coreR, eye)
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
        -- subtle top-left highlight band
        if px + py < -c * 0.55 and d < -2.6 then col = bright end
      elseif d < -0.6 then
        col = bright
      elseif d < 0.4 then
        col = OUTLINE
      end
      local rr = math.sqrt(px * px + py * py)
      if col and d < -1.6 and rr < coreR then col = WHITE end
      if col and eye and d < -1.6 and rr < coreR * 0.5 then col = OUTLINE end
      if col then img:drawPixel(x, y, col) end
    end
  end
  return img
end

local function enemy(name, size, verts, bright, dark, core)
  save(name, {
    shape(size, verts, bright, dark, core, true),
    shape(size, verts, bright, dark, core + 1.2, true),
  }, size, size)
end

local R, r = hex("ff3b4e"), hex("7a1427")
local Y, y = hex("ffd23f"), hex("8a5c10")
local G, g = hex("5dff7a"), hex("1b7a35")
local B, b = hex("3b9dff"), hex("173f8a")
local P, p = hex("b066ff"), hex("44217a")

enemy("chaser", 16, polygon(4, 7.6, 0), R, r, 2.2)
enemy("dasher", 16, { { 7.6, 0 }, { -6.2, -6.8 }, { -6.2, 6.8 } }, Y, y, 1.8) -- triangle pointing right
enemy("splitter", 16, polygon(4, 7.8, math.pi / 4), G, g, 2.4)
enemy("mini", 10, polygon(4, 4.8, 0), G, g, 1.2)
enemy("shooter", 16, polygon(6, 7.6, 0), B, b, 2.4)
enemy("tank", 26, polygon(8, 12.4, math.pi / 8), P, p, 3.6)

-- ---------- projectiles ----------
local function blob(w, h, bright, mid)
  local img = Image(w, h, ColorMode.RGB)
  for yy = 0, h - 1 do
    for xx = 0, w - 1 do
      local nx = (xx + 0.5 - w / 2) / (w / 2)
      local ny = (yy + 0.5 - h / 2) / (h / 2)
      local d = nx * nx + ny * ny
      if d < 0.35 then img:drawPixel(xx, yy, WHITE)
      elseif d < 0.75 then img:drawPixel(xx, yy, bright)
      elseif d < 1.05 then img:drawPixel(xx, yy, mid) end
    end
  end
  return img
end
save("bullet", { blob(10, 4, hex("29f3ff"), hex("138a9e")) }, 10, 4)
save("ebullet", { blob(8, 8, hex("ff2fd0"), hex("8a1677")) }, 8, 8)

-- spark particle
local spark = Image(3, 3, ColorMode.RGB)
spark:drawPixel(1, 0, WHITE); spark:drawPixel(0, 1, WHITE); spark:drawPixel(1, 1, WHITE)
spark:drawPixel(2, 1, WHITE); spark:drawPixel(1, 2, WHITE)
save("spark", { spark }, 3, 3)

-- orbital blade
local blade = shape(12, polygon(3, 5.6, -math.pi / 2), hex("ffffff"), hex("29f3ff"), 0, false)
save("blade", { blade }, 12, 12)

-- pack rows top-to-bottom with a 1px gap (Godot slices the same table)
local W, H = 64, 0
for _, st in ipairs(strips) do H = H + st.h + 1 end
local atlas = Image(W, H, ColorMode.RGB)
local yy = 0
for _, st in ipairs(strips) do
  atlas:drawImage(st.img, Point(0, yy))
  yy = yy + st.h + 1
end
local spr = Sprite(W, H, ColorMode.RGB)
spr:newCel(spr.layers[1], spr.frames[1], atlas, Point(0, 0))
app.refresh()
