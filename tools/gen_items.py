"""NEON DRIFT v3 — item database (single source of truth).
Writes:  items_db.gd  (GDScript constants for the game)
         tools/neondrift_items.lua  (Aseprite script that draws one 24px icon per item)
Prices / recipes follow DOTA 2 (7.3x) closely, adapted to this hero.
"""
import json, os, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'

# id, name, cat, cost(total), comps, recipe, stats, special, glyph, c1, c2, note
I = []
def item(id, name, cat, cost, glyph, c1, c2, stats=None, comps=None, recipe=0, special=None, note=''):
    I.append(dict(id=id, name=name, cat=cat, cost=cost, comps=comps or [], recipe=recipe,
                  stats=stats or {}, special=special or {}, glyph=glyph, c1=c1, c2=c2, note=note))

# ---------------- consumables (applied on purchase) ----------------
item('clarity', '净化药水', 'consumable', 50, 'potion', '4aa8ff', 'c8e8ff', special={'c_mp': [6.0, 25.0]}, note='25 秒内恢复 150 魔法')
item('mango', '魔法芒果', 'consumable', 65, 'fruit', 'ffb030', '5dbb4a', special={'c_mana_now': 100}, note='立即恢复 100 魔法')
item('tome', '知识之书', 'consumable', 75, 'book', '3a7a3a', 'e8d890', special={'c_xp': 0.6}, note='立即获得当前等级 60% 的经验')
item('tango', '树之祭祀', 'consumable', 90, 'leaf', '5dbb4a', '2a6a2a', special={'c_hp': [7.0, 16.0]}, note='16 秒内恢复 112 生命')
item('salve', '治疗药膏', 'consumable', 100, 'potion', 'ff4a5a', 'ffd0d0', special={'c_hp': [40.0, 10.0]}, note='10 秒内恢复 400 生命')
item('shard', '阿哈利姆魔晶', 'consumable', 1400, 'crystal', '4aa8ff', 'b0f0ff', special={'shard': True}, note='永久升级 Q：脉冲射线变为三道扇形光束（限购 1 次）')
item('moon', '银月之晶', 'consumable', 4000, 'moon', 'c0d8ff', '6a80c0', special={'moon': 60}, note='永久提升 60 攻击速度（限购 1 次）')

# ---------------- basic ----------------
item('branch', '铁树枝干', 'basic', 50, 'branch', '8a6a3a', '5dbb4a', {'all': 1})
item('circlet', '圆环', 'basic', 155, 'ring', 'e0c060', 'ff4a5a', {'all': 2})
item('gauntlets', '力量手套', 'basic', 140, 'glove', 'd04a3a', '7a2a20', {'str': 3})
item('slippers', '敏捷便鞋', 'basic', 140, 'boots', '4ac060', '1a6a30', {'agi': 3})
item('mantle', '智力斗篷', 'basic', 140, 'cloak', '4a7aff', '1a2a7a', {'int': 3})
item('protect', '守护指环', 'basic', 175, 'ring', 'b0b8c0', '4aa8ff', {'armor': 2})
item('regen_ring', '回复戒指', 'basic', 175, 'ring', 'e0c060', '5dff7a', {'hpr': 1.25})
item('sage', '贤者面罩', 'basic', 175, 'mask', '5a8ad0', 'c8e0ff', {'mpr': 0.7})
item('blades', '攻击之爪', 'basic', 450, 'claw', 'c8c8d0', '6a6a70', {'dmg': 9})
item('gloves', '加速手套', 'basic', 450, 'glove', 'e0a030', '7a5010', {'as': 20})
item('band', '精灵布带', 'basic', 450, 'bracelet', '4ac060', 'e0e0a0', {'agi': 6})
item('belt', '力量腰带', 'basic', 450, 'belt', 'b04a2a', 'e0c060', {'str': 6})
item('robe', '法师长袍', 'basic', 450, 'robe', '4a6aff', 'e0c060', {'int': 6})
item('boots', '速度之靴', 'basic', 500, 'boots', 'a06a3a', '5a3a1a', {'ms': 45})
item('cloak', '抗魔斗篷', 'basic', 500, 'cloak', 'c03a3a', '5a1a1a', {'mr': 15})
item('chainmail', '锁子甲', 'basic', 550, 'chain', 'a0a8b0', '50585f', {'armor': 4})
item('roh', '治疗指环', 'basic', 700, 'ring', '5dff7a', 'e0c060', {'hpr': 6.5})
item('void', '虚无宝石', 'basic', 700, 'gem', '6a4aff', 'c0b0ff', {'mpr': 1.75})
item('energy', '能量之球', 'basic', 800, 'orb', '4a7aff', 'c0e0ff', {'mana': 250})
item('quarterstaff', '短棍', 'basic', 875, 'staff', 'a07a4a', 'e0c060', {'dmg': 10, 'as': 10})
item('morbid', '吸血面具', 'basic', 900, 'mask', '8a1a2a', 'ff4a5a', {'ls': 10})
item('vitality', '精气之球', 'basic', 1000, 'orb', 'ff4a5a', 'ffc0c0', {'hp': 250})
item('broadsword', '大剑', 'basic', 1000, 'sword', 'c8d0d8', '7a5a3a', {'dmg': 15})
item('alacrity', '欢欣之刃', 'basic', 1000, 'sword', '4ac060', 'c0ffc0', {'agi': 10})
item('ogre', '食人魔之斧', 'basic', 1000, 'axe', 'b04a2a', 'c8c8c8', {'str': 10})
item('wizard', '魔力法杖', 'basic', 1000, 'staff', '4a6aff', 'c0e0ff', {'int': 10})
item('javelin', '标枪', 'basic', 1100, 'spear', 'c8c8d0', '8a6a3a', {'dmg': 10})
item('point', '活力之球', 'basic', 1200, 'orb', 'b060ff', 'f0c0ff', {'hp': 175, 'mana': 175})
item('talisman', '闪避护符', 'basic', 1300, 'gem', '5dffa0', 'e0ffe0', {'eva': 15})
item('platemail', '板甲', 'basic', 1400, 'plate', 'a0a8b0', 'e0e8f0', {'armor': 10})
item('mithril', '秘银锤', 'basic', 1600, 'hammer', 'c8d8e8', '6a7a8a', {'dmg': 24})
item('ultimate', '极限法球', 'basic', 2050, 'orb', 'ffd23f', 'ffffff', {'all': 10})
item('hyperstone', '振奋宝石', 'basic', 2000, 'gem', 'ff8a2b', 'fff0c0', {'as': 60})
item('demon', '恶魔刀锋', 'basic', 2200, 'greatsword', 'c03a3a', '3a0a0a', {'dmg': 40})
item('eaglesong', '鹰歌弓', 'basic', 2800, 'bow', '4ac060', 'e0e0a0', {'agi': 25})
item('mystic', '神秘法杖', 'basic', 2800, 'staff', '6a4aff', 'ffd23f', {'int': 25})
item('reaver', '掠夺者之斧', 'basic', 2800, 'axe', 'c03a3a', 'ffd23f', {'str': 25})
item('relic', '圣者遗物', 'basic', 3800, 'sun', 'ffd23f', 'fff8c0', {'dmg': 55})

# ---------------- advanced (recipes) ----------------
item('wraith', '怨灵系带', 'advanced', 505, 'bracelet', '6aff8a', 'e0c060', {'agi': 6, 'str': 2, 'int': 2, 'armor': 1.5}, ['slippers', 'circlet'], 210)
item('treads', '动力鞋', 'advanced', 1400, 'boots', 'ffd23f', '8a5a1a', {'ms': 45, 'as': 25, 'agi': 10}, ['boots', 'gloves', 'band'])
item('phase', '相位鞋', 'advanced', 1500, 'boots', 'ff6a3a', '5a1a1a', {'ms': 45, 'dmg': 12, 'armor': 4}, ['boots', 'blades', 'chainmail'])
item('perseverance', '坚韧球', 'advanced', 1400, 'orb', '5dff7a', '6a4aff', {'hpr': 6.5, 'mpr': 1.75}, ['roh', 'void'])
item('lance', '魔龙枪', 'advanced', 1900, 'spear', '4ac060', 'ff6a3a', {'agi': 12, 'str': 12, 'range': 150}, ['band', 'band', 'ogre'])
item('crystalys', '水晶剑', 'advanced', 1950, 'sword', '6ad8ff', 'ffffff', {'dmg': 24}, ['broadsword', 'blades'], 500, {'crit': [0.3, 1.6]})
item('kaya', '慧光', 'advanced', 2050, 'staff', 'b060ff', 'ffd0ff', {'int': 16, 'amp': 10}, ['wizard', 'robe'], 600)
item('yasha', '夜叉', 'advanced', 2050, 'sword', '4ac060', 'e0ffe0', {'agi': 16, 'as': 10, 'ms_pct': 8}, ['alacrity', 'band'], 600)
item('sange', '散华', 'advanced', 2050, 'sword', 'ff4a3a', 'ffe0d0', {'str': 16, 'hpr': 3}, ['ogre', 'belt'], 600)
item('aether', '以太透镜', 'advanced', 2275, 'lens', '6ad8ff', 'ffffff', {'mana': 300, 'mpr': 1.5, 'cast': 225}, ['energy', 'void'], 775)
item('maelstrom', '漩涡', 'advanced', 2700, 'bolt', '6ad8ff', 'ffd23f', {'dmg': 24}, ['mithril', 'javelin'], 0, {'chain': [0.3, 4, 120]})
item('soul', '灵魂之助', 'advanced', 3000, 'orb', 'ff6ad8', 'ffffff', {'hp': 425, 'mana': 425}, ['vitality', 'energy', 'point'])
item('deso', '黯灭', 'advanced', 3500, 'skull', 'c03a3a', '2a0a0a', {'dmg': 50}, ['mithril', 'mithril'], 300, {'deso': 6})
item('sny', '散夜对剑', 'advanced', 4100, 'sword', 'ffb030', '4ac060', {'str': 16, 'agi': 16, 'as': 12, 'ms_pct': 12}, ['sange', 'yasha'])
item('ynk', '慧夜对剑', 'advanced', 4100, 'sword', '4ac060', 'b060ff', {'agi': 16, 'int': 16, 'ms_pct': 12, 'amp': 12}, ['yasha', 'kaya'])
item('kns', '散慧对剑', 'advanced', 4100, 'sword', 'ff4a3a', 'b060ff', {'str': 16, 'int': 16, 'amp': 12, 'hpr': 4}, ['kaya', 'sange'])
item('aghs', '阿哈利姆神杖', 'advanced', 4200, 'staff', '4aa8ff', 'ffd23f', {'all': 10, 'hp': 175, 'mana': 175}, ['point', 'ogre', 'alacrity', 'wizard'], 0, {'scepter': True})
item('heart', '恐鳌之心', 'advanced', 5000, 'heart', 'ff3a4a', 'ffc0c0', {'str': 40, 'hp': 250}, ['vitality', 'reaver'], 1200, {'heart': 1.2})
item('radiance', '辉耀', 'advanced', 5050, 'sun', 'ff8a2b', 'ffd23f', {'dmg': 55}, ['relic'], 1250, {'radiance': [60, 700]})
item('satanic', '撒旦之邪力', 'advanced', 5050, 'mask', 'c03a3a', 'ffd23f', {'str': 25, 'dmg': 25, 'ls': 25}, ['morbid', 'reaver', 'broadsword'], 350)
item('ac', '强袭胸甲', 'advanced', 5125, 'plate', 'ffd23f', '8a6a1a', {'armor': 14, 'as': 30}, ['platemail', 'hyperstone', 'chainmail'], 1175, {'ac_aura': 5})
item('daedalus', '代达罗斯之殇', 'advanced', 5150, 'greatsword', 'ffd23f', 'c03a3a', {'dmg': 88}, ['crystalys', 'demon'], 1000, {'crit': [0.3, 2.25]})
item('shiva', '希瓦的守护', 'advanced', 5175, 'flake', '6ad8ff', 'ffffff', {'armor': 15, 'int': 30}, ['platemail', 'mystic'], 975, {'shiva': 0.4})
item('mkb', '金箍棒', 'advanced', 5200, 'hammer', 'ffd23f', 'c03a3a', {'dmg': 40, 'as': 45}, ['demon', 'javelin', 'quarterstaff'], 1025, {'mkb': [0.8, 70]})
item('octarine', '玲珑心', 'advanced', 5275, 'orb', '6ad8ff', 'ffd23f', {'hp': 425, 'mana': 725, 'mpr': 1.5, 'cast': 225, 'cdr': 25}, ['soul', 'aether'])
item('skadi', '斯嘉蒂之眼', 'advanced', 5300, 'flake', '4aa8ff', 'c0e0ff', {'all': 22, 'hp': 220, 'mana': 220}, ['ultimate', 'ultimate', 'point'], 0, {'skadi': [0.4, 1.5]})
item('butterfly', '蝴蝶', 'advanced', 5450, 'wings', '4ac060', 'ffd23f', {'agi': 35, 'dmg': 25, 'as': 30, 'eva': 35}, ['eaglesong', 'talisman', 'quarterstaff'], 475)
item('mjollnir', '雷神之锤', 'advanced', 5500, 'bolt', 'ffd23f', '6ad8ff', {'dmg': 24, 'as': 70}, ['maelstrom', 'hyperstone'], 800, {'chain': [0.3, 12, 180]})
item('rapier', '圣剑', 'advanced', 7000, 'greatsword', 'ffffff', 'ffd23f', {'dmg': 330}, ['relic', 'demon'], 1000)

# ---- sanity: totals must equal component sums + recipe
ids = {it['id']: it for it in I}
for it in I:
    if it['comps']:
        s = sum(ids[c]['cost'] for c in it['comps']) + it['recipe']
        assert s == it['cost'], (it['id'], s, it['cost'])
prices = [it['cost'] for it in I]
assert min(prices) == 50 and max(prices) == 7000

# ---------------- GDScript DB ----------------
def gd(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list): return '[' + ', '.join(gd(x) for x in v) + ']'
    if isinstance(v, dict): return '{' + ', '.join(f'{json.dumps(k)}: {gd(x)}' for k, x in v.items()) + '}'
    raise TypeError(v)

lines = ['extends RefCounted', '## Generated by tools/gen_items.py — do not edit by hand.', '', 'const ORDER := ' + gd([it['id'] for it in I]), '', 'const DB := {']
for it in I:
    d = {k: it[k] for k in ('name', 'cat', 'cost', 'comps', 'recipe', 'stats', 'special', 'note')}
    lines.append(f'\t"{it["id"]}": {gd(d)},')
lines.append('}')
open(os.path.join(ROOT, 'items_db.gd'), 'w').write('\n'.join(lines) + '\n')

# ---------------- Aseprite icon script ----------------
LUA_HEAD = r'''-- NEON DRIFT v3 — item icons (generated by tools/gen_items.py)
-- Draws one 24x24 icon per item, 10 per row, and opens the sheet as a sprite.
local S = 24
local COLS = 10
local function rgba(r, g, b, a) return app.pixelColor.rgba(r, g, b, a or 255) end
local function hx(h, f)
  f = f or 1
  local function c(v) v = math.floor(v * f + 0.5); if v < 0 then return 0 elseif v > 255 then return 255 end; return v end
  return rgba(c(tonumber(h:sub(1, 2), 16)), c(tonumber(h:sub(3, 4), 16)), c(tonumber(h:sub(5, 6), 16)))
end
local OUT = rgba(12, 10, 20)
local img
local function px(x, y, col)
  x, y = math.floor(x), math.floor(y)
  if x >= 1 and y >= 1 and x < S - 1 and y < S - 1 then img:drawPixel(x, y, col) end
end
local function line(x0, y0, x1, y1, col, w)
  w = w or 1
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
  for i = 0, n do
    local x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
    for a = 0, w - 1 do for b = 0, w - 1 do px(x + a, y + b, col) end end
  end
end
local function rect(x, y, w, h, col) for j = 0, h - 1 do for i = 0, w - 1 do px(x + i, y + j, col) end end end
local function ell(cx, cy, rx, ry, col)
  for y = math.floor(cy - ry), math.ceil(cy + ry) do for x = math.floor(cx - rx), math.ceil(cx + rx) do
    local dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
    if dx * dx + dy * dy <= 1 then px(x, y, col) end
  end end
end
local function ring(cx, cy, r, col, t)
  t = t or 1.2
  for y = math.floor(cy - r - 1), math.ceil(cy + r + 1) do for x = math.floor(cx - r - 1), math.ceil(cx + r + 1) do
    local d = math.sqrt((x + 0.5 - cx) ^ 2 + (y + 0.5 - cy) ^ 2)
    if math.abs(d - r) <= t / 2 then px(x, y, col) end
  end end
end
local function outline(col)
  local solid = {}
  for y = 0, S - 1 do for x = 0, S - 1 do solid[y * S + x] = app.pixelColor.rgbaA(img:getPixel(x, y)) == 255 and img:getPixel(x, y) ~= BG_MARK end end
end

-- glyphs: (c1 main, c2 accent, d dark, l light)
local G = {}
G.potion = function(c1, c2, d, l) rect(10, 4, 4, 3, hx('c8b8a0')); ell(12, 14, 6.5, 6.5, d); ell(12, 14, 5.5, 5.5, c1); ell(10, 12, 1.6, 1.6, c2); rect(9, 7, 6, 2, hx('e0e0e8')) end
G.fruit = function(c1, c2, d, l) ell(12, 14, 7, 6.5, d); ell(12, 14, 6, 5.5, c1); ell(9.5, 11.5, 1.6, 1.6, l); line(12, 8, 14, 4, hx('6a4a2a'), 1); ell(16, 6, 2.5, 1.5, c2) end
G.leaf = function(c1, c2, d, l) for k = 0, 2 do local x = 6 + k * 5; ell(x + 1, 13, 2.5, 6, d); ell(x + 1, 13, 1.7, 5.2, c1); line(x + 1, 8, x + 1, 19, c2) end end
G.book = function(c1, c2, d, l) rect(5, 5, 14, 15, d); rect(6, 6, 12, 13, c1); rect(7, 7, 2, 11, d); rect(11, 9, 5, 2, c2); rect(11, 13, 5, 1, c2) end
G.crystal = function(c1, c2, d, l) for y = 3, 20 do local w = (y < 10) and (y - 3) * 0.8 or (20 - y) * 0.6; line(12 - w, y, 12 + w, y, (y % 3 == 0) and c2 or c1) end; line(12, 3, 12, 20, l) end
G.moon = function(c1, c2, d, l) ell(12, 12, 8, 8, c1); ell(15, 10, 7, 7, hx('112014')); ell(9, 14, 1.3, 1.3, c2); ell(8, 9, 1, 1, c2) end
G.branch = function(c1, c2, d, l) line(5, 19, 18, 5, c1, 2); line(11, 12, 7, 7, c1, 1); line(14, 9, 18, 12, c1, 1); ell(7, 7, 2, 1.5, c2); ell(18, 12, 2, 1.5, c2); ell(18, 5, 2, 2, c2) end
G.ring = function(c1, c2, d, l) ring(12, 13, 6, c1, 2.4); ring(12, 13, 6, l, 0.8); ell(12, 6, 3, 2.5, c2); ell(11, 5.5, 1, 1, hx('ffffff')) end
G.glove = function(c1, c2, d, l) rect(7, 10, 10, 9, d); rect(8, 11, 8, 7, c1); for k = 0, 3 do rect(8 + k * 2, 5 + (k == 0 and 3 or 0), 2, 6, c1) end; rect(6, 18, 12, 3, c2) end
G.boots = function(c1, c2, d, l) rect(7, 4, 6, 12, d); rect(8, 5, 4, 11, c1); rect(7, 14, 12, 5, d); rect(8, 15, 10, 3, c1); rect(7, 6, 6, 2, c2); rect(14, 15, 3, 1, l) end
G.mask = function(c1, c2, d, l) ell(12, 12, 8, 9, d); ell(12, 12, 7, 8, c1); ell(9, 10, 2, 1.4, hx('000000')); ell(15, 10, 2, 1.4, hx('000000')); line(9, 16, 15, 16, c2); line(12, 4, 12, 7, c2) end
G.cloak = function(c1, c2, d, l) for y = 5, 20 do local w = 3 + (y - 5) * 0.45; line(12 - w, y, 12 + w, y, (y < 7) and c2 or c1) end; line(12, 7, 12, 20, d) end
G.robe = function(c1, c2, d, l) for y = 4, 20 do local w = (y < 9) and 4 or 4 + (y - 9) * 0.4; line(12 - w, y, 12 + w, y, c1) end; line(12, 5, 12, 20, c2); rect(8, 11, 8, 1, c2) end
G.belt = function(c1, c2, d, l) rect(3, 9, 18, 7, d); rect(3, 10, 18, 5, c1); rect(9, 8, 6, 9, c2); rect(11, 10, 2, 5, d) end
G.bracelet = function(c1, c2, d, l) ring(12, 12, 7, c1, 3); ring(12, 12, 7, l, 0.8); for k = 0, 3 do local a = k * 1.57; ell(12 + math.cos(a) * 7, 12 + math.sin(a) * 7, 1.5, 1.5, c2) end end
G.claw = function(c1, c2, d, l) for k = 0, 2 do line(6 + k * 4, 20, 9 + k * 4, 4, c1, 2); px(9 + k * 4, 4, l) end; rect(5, 18, 14, 3, c2) end
G.chain = function(c1, c2, d, l) rect(5, 5, 14, 15, d); for y = 6, 18, 2 do for x = 6, 17, 2 do px(x + (y % 4 == 0 and 1 or 0), y, c1) end end; rect(9, 4, 6, 2, c2) end
G.plate = function(c1, c2, d, l) for y = 4, 20 do local w = (y < 8) and 8 or 7 - (y - 8) * 0.25; line(12 - w, y, 12 + w, y, (y % 5 == 0) and d or c1) end; line(12, 4, 12, 20, c2); rect(5, 4, 4, 3, c2); rect(15, 4, 4, 3, c2) end
G.sword = function(c1, c2, d, l) line(6, 18, 17, 7, c1, 2); line(7, 18, 18, 7, l); line(17, 6, 19, 4, l); line(5, 15, 9, 19, c2, 2); line(4, 20, 6, 18, hx('6a4a2a'), 2) end
G.greatsword = function(c1, c2, d, l) line(5, 19, 18, 6, c1, 3); line(6, 19, 19, 6, l); line(4, 15, 9, 20, c2, 2); line(3, 21, 5, 19, d, 2); px(19, 4, l); px(20, 4, l) end
G.hammer = function(c1, c2, d, l) line(6, 19, 15, 10, hx('8a6a3a'), 2); rect(12, 3, 9, 8, d); rect(13, 4, 7, 6, c1); rect(13, 4, 7, 1, l); rect(15, 6, 3, 2, c2) end
G.orb = function(c1, c2, d, l) ell(12, 12, 8, 8, d); ell(12, 12, 7, 7, c1); ell(12, 12, 4, 4, c2); ell(9.5, 9.5, 1.8, 1.8, hx('ffffff')) end
G.staff = function(c1, c2, d, l) line(7, 21, 15, 7, hx('8a6a3a'), 2); ell(16, 6, 4, 4, d); ell(16, 6, 3, 3, c1); ell(15, 5, 1, 1, c2); ring(16, 6, 4.5, c2, 0.8) end
G.axe = function(c1, c2, d, l) line(7, 21, 15, 5, hx('8a6a3a'), 2); ell(16, 8, 5, 5.5, d); ell(16, 8, 4, 4.5, c2); ell(17, 8, 2.5, 3.5, c1) end
G.bow = function(c1, c2, d, l) for k = 0, 30 do local a = -1.2 + k * 0.08; px(8 + math.cos(a) * 10, 12 + math.sin(a) * 10, c1); px(8 + math.cos(a) * 9, 12 + math.sin(a) * 9, c1) end; line(11, 3, 11, 21, l); line(4, 12, 20, 12, c2); px(20, 11, c2); px(20, 13, c2) end
G.spear = function(c1, c2, d, l) line(4, 20, 17, 7, hx('8a6a3a'), 2); for y = 3, 9 do local w = (y - 3) * 0.6; line(18 - w, y + w * 0, 18 + w, y, c1) end; line(16, 9, 20, 9, c2) end
G.gem = function(c1, c2, d, l) for y = 5, 19 do local w = (y < 10) and (y - 5) * 1.2 + 2 or (19 - y) * 0.75; line(12 - w, y, 12 + w, y, (y < 10) and c2 or c1) end; line(8, 10, 16, 10, l) end
G.heart = function(c1, c2, d, l) ell(9, 10, 4.5, 4.5, c1); ell(15, 10, 4.5, 4.5, c1); for y = 11, 20 do local w = (20 - y) * 0.85; line(12 - w, y, 12 + w, y, c1) end; ell(8, 9, 1.5, 1.5, c2) end
G.bolt = function(c1, c2, d, l) local p = { { 15, 2 }, { 8, 12 }, { 12, 12 }, { 9, 22 }, { 17, 10 }, { 13, 10 }, { 16, 2 } }; for i = 1, #p - 1 do line(p[i][1], p[i][2], p[i + 1][1], p[i + 1][2], c1, 2) end; ring(12, 12, 9, c2, 0.8) end
G.sun = function(c1, c2, d, l) for k = 0, 7 do local a = k * 0.785; line(12 + math.cos(a) * 6, 12 + math.sin(a) * 6, 12 + math.cos(a) * 10, 12 + math.sin(a) * 10, c1, 1) end; ell(12, 12, 5.5, 5.5, c1); ell(12, 12, 3.5, 3.5, c2) end
G.skull = function(c1, c2, d, l) ell(12, 10, 7, 6.5, hx('e0d8c8')); rect(8, 15, 8, 4, hx('e0d8c8')); ell(9.5, 10, 1.8, 2, c1); ell(14.5, 10, 1.8, 2, c1); for x = 9, 15, 2 do px(x, 18, hx('3a3030')) end; line(3, 21, 7, 17, c2, 2) end
G.lens = function(c1, c2, d, l) ring(10, 10, 6.5, c2, 1.6); ell(10, 10, 5.5, 5.5, c1); ell(8, 8, 1.5, 1.5, hx('ffffff')); line(14, 14, 20, 20, hx('8a6a3a'), 2) end
G.flake = function(c1, c2, d, l) for k = 0, 5 do local a = k * 1.047; line(12, 12, 12 + math.cos(a) * 9, 12 + math.sin(a) * 9, c1, 1); px(12 + math.cos(a) * 6 + math.cos(a + 1) * 2, 12 + math.sin(a) * 6 + math.sin(a + 1) * 2, c2) end; ell(12, 12, 2.5, 2.5, c2) end
G.wings = function(c1, c2, d, l) ell(7, 9, 5, 4.5, c1); ell(17, 9, 5, 4.5, c1); ell(8, 16, 3.5, 3.5, c2); ell(16, 16, 3.5, 3.5, c2); line(12, 6, 12, 19, d, 1); ell(7, 9, 1.5, 1.5, l); ell(17, 9, 1.5, 1.5, l) end

local BG = {
  consumable = { '1a3a20', '0c1a10', '5dbb4a' },
  basic = { '22283a', '10121c', '8a92b8' },
  advanced = { '3a2a10', '1a1008', 'ffd23f' },
}

local function draw_icon(it)
  img = Image(S, S, ColorMode.RGB)
  local bg = BG[it.cat]
  for y = 0, S - 1 do for x = 0, S - 1 do
    local t = (x + y) / (2 * S)
    local a, b = hx(bg[1]), hx(bg[2])
    local r = app.pixelColor.rgbaR(a) * (1 - t) + app.pixelColor.rgbaR(b) * t
    local g = app.pixelColor.rgbaG(a) * (1 - t) + app.pixelColor.rgbaG(b) * t
    local bb = app.pixelColor.rgbaB(a) * (1 - t) + app.pixelColor.rgbaB(b) * t
    img:drawPixel(x, y, rgba(math.floor(r), math.floor(g), math.floor(bb)))
  end end
  G[it.glyph](hx(it.c1), hx(it.c2), hx(it.c1, 0.45), hx(it.c1, 1.35))
  for i = 0, S - 1 do
    img:drawPixel(i, 0, hx(bg[3])); img:drawPixel(i, S - 1, OUT); img:drawPixel(0, i, hx(bg[3])); img:drawPixel(S - 1, i, OUT)
  end
  return img
end

'''

LUA_TAIL = r'''
local rows = math.ceil(#ITEMS / COLS)
local sheet = Image(S * COLS, S * rows, ColorMode.RGB)
for i, it in ipairs(ITEMS) do
  local ic = draw_icon(it)
  sheet:drawImage(ic, Point(((i - 1) % COLS) * S, math.floor((i - 1) / COLS) * S))
end
local spr = Sprite(S * COLS, S * rows, ColorMode.RGB)
spr:newCel(spr.layers[1], spr.frames[1], sheet, Point(0, 0))
app.refresh()
'''

data = ['local ITEMS = {']
for it in I:
    data.append(f"  {{ id = '{it['id']}', cat = '{it['cat']}', glyph = '{it['glyph']}', c1 = '{it['c1']}', c2 = '{it['c2']}' }},")
data.append('}')
lua = LUA_HEAD.replace('''local function outline(col)
  local solid = {}
  for y = 0, S - 1 do for x = 0, S - 1 do solid[y * S + x] = app.pixelColor.rgbaA(img:getPixel(x, y)) == 255 and img:getPixel(x, y) ~= BG_MARK end end
end
''', '') + '\n'.join(data) + '\n' + LUA_TAIL
os.makedirs(os.path.join(ROOT, 'tools'), exist_ok=True)
open(os.path.join(ROOT, 'tools', 'neondrift_items.lua'), 'w').write(lua)
print(len(I), 'items; price range', min(prices), '-', max(prices))
