#!/usr/bin/env python3
"""NeonMOBA — item database (single source of truth). Design: docs/design/属性与装备迭代设计案.md
Writes:  items_db.gd       GDScript constants for the game (do not edit by hand)
         art/items.png      24x24 icon per item, ICON_COLS (10) per row, in ORDER
Usage:   python3 tools/gen_items.py [project_root]

Stats are secondary stats only (no strength / agility / intelligence):
  hp hpr mana mpr atk as(%) def res ms range pspd vision ls(%) pow(%) cdr(%)
Prices follow the per-stat price table (PRICE below). Basic items are priced exactly by it;
finished items = components + an upgrade fee that pays for their special effect.
"""
import json, math, os, sys
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'

# gold per point of each stat (design doc, section 4.2)
PRICE = {'hp': 4, 'atk': 50, 'as': 25, 'def': 22, 'res': 22, 'pow': 40, 'cdr': 90, 'ms': 10, 'hpr': 100,
         'mana': 3, 'mpr': 150, 'ls': 70, 'range': 6, 'pspd': 1, 'vision': 2}

# shop tabs
KINDS = {'dmg': '输出', 'spd': '攻速', 'pow': '技能', 'def': '生存', 'mob': '机动', 'eye': '视野', 'hero': '英雄强化'}

I = []
def item(id, name, tier, kind, glyph, c1, c2, stats=None, comps=None, upgrade=0, special=None, note='', cost=None):
    stats = stats or {}
    comps = comps or []
    if cost is None:
        if comps:
            cost = sum(ids[c]['cost'] for c in comps) + upgrade
        else:
            cost = int(round(sum(PRICE[k] * v for k, v in stats.items())))
    it = dict(id=id, name=name, cat=tier, kind=kind, cost=cost, comps=comps, recipe=upgrade, stats=stats,
              special=special or {}, glyph=glyph, c1=c1, c2=c2, note=note)
    I.append(it)
    ids[id] = it

ids = {}
# ---------------- basic (priced by PRICE) ----------------
item('blade', '脉冲刃片', 'basic', 'dmg', 'blade', 'ff5a6a', 'ffd0d8', {'atk': 10})
item('chip', '超频芯片', 'basic', 'spd', 'chip', 'ffb030', 'fff0c0', {'as': 15})
item('core', '逻辑核心', 'basic', 'pow', 'core', 'b060ff', 'f0d0ff', {'pow': 10})
item('cap', '电容模块', 'basic', 'pow', 'cell', '4a8aff', 'c0e0ff', {'mana': 150, 'mpr': 1})
item('plate', '纳米装甲片', 'basic', 'def', 'plate', 'a0b0c8', 'e8f0ff', {'def': 15})
item('coat', '相位涂层', 'basic', 'def', 'shield', '6ad8ff', 'e0fbff', {'res': 15})
item('battery', '能量电池', 'basic', 'def', 'cell', 'ff4a5a', 'ffd0d0', {'hp': 200})
item('gel', '修复凝胶', 'basic', 'def', 'drop', '5dff7a', 'd0ffd8', {'hpr': 3})
item('leech', '吸能触点', 'basic', 'dmg', 'fang', 'c02a4a', 'ff8aa0', {'ls': 7})
item('boots', '推进靴', 'basic', 'mob', 'boot', '4ac0a0', 'c0fff0', {'ms': 40})
item('scope', '校准瞄具', 'basic', 'eye', 'scope', 'e0e060', 'fffff0', {'range': 50, 'pspd': 100}, note='近战只获得一半攻击距离')
item('lens', '广角镜片', 'basic', 'eye', 'lens', '60e0ff', 'f0ffff', {'vision': 150})

# ---------------- finished items: two components + upgrade fee, one special each ----------------
item('pierce', '穿甲弹匣', 'advanced', 'dmg', 'mag', 'ff5a6a', 'ffd23f', {'atk': 22}, ['blade', 'blade'], 600,
     {'pierce': 1}, '远程普攻穿透 1 个目标；近战扇形角度 +20°')
item('drill', '破甲钻头', 'advanced', 'dmg', 'drill', 'ff8a3a', 'c0c8d0', {'atk': 12, 'def': 15}, ['blade', 'plate'], 670,
     {'armor_break': [20.0, 4.0]}, '破甲：普攻命中使目标物理防御 -20，持续 4 秒')
item('rage', '暴走处理器', 'advanced', 'spd', 'chip', 'ff5a3a', 'ffd23f', {'as': 20, 'atk': 10}, ['chip', 'blade'], 825,
     {'crit': [0.25, 1.6]}, '普攻有 25% 几率造成 160% 伤害')
item('coil', '超载线圈', 'advanced', 'spd', 'coil', '6ad8ff', 'ffd23f', {'as': 35}, ['chip', 'chip'], 1050,
     {'arc': [4, 3, 60.0]}, '每第 4 次普攻命中释放连锁电弧，弹跳 3 次，每次 60 法术伤害')
item('qcirc', '量子回路', 'advanced', 'pow', 'core', '4a8aff', 'b060ff', {'pow': 12, 'mana': 150, 'cdr': 10}, ['core', 'cap'], 700,
     {}, '')
item('wound', '重创注射器', 'advanced', 'pow', 'syringe', 'b060ff', '5dff7a', {'pow': 20}, ['core', 'core'], 800,
     {'grievous': [0.4, 3.0]}, '重伤：技能命中使目标受到的治疗和护盾 -40%，持续 3 秒')
item('reso', '共振透镜', 'advanced', 'pow', 'lens', 'b060ff', '60e0ff', {'pow': 12, 'vision': 150}, ['core', 'lens'], 800,
     {'charge_fast': 0.2}, '蓄力技能的蓄力时间 -20%')
item('reactive', '反应装甲', 'advanced', 'def', 'plate', 'a0b0c8', 'ffd23f', {'def': 25, 'hp': 200}, ['plate', 'battery'], 670,
     {'tenacity': 0.2}, '韧性：受到的控制时间 -20%')
item('barrier', '屏障发生器', 'advanced', 'def', 'shield', '6ad8ff', 'ffd23f', {'res': 25, 'hp': 200}, ['coat', 'battery'], 670,
     {'spell_shield': 150.0}, '每回合第一次受到技能伤害时获得 150 点护盾（4 秒）')
item('pod', '再生舱', 'advanced', 'def', 'drop', '5dff7a', 'ff4a5a', {'hp': 250, 'hpr': 5}, ['gel', 'battery'], 600,
     {'regen_ooc': 2.0}, '脱离战斗 3 秒后生命回复翻倍')
item('gauntlet', '吸能护手', 'advanced', 'dmg', 'fang', 'c02a4a', 'ffd23f', {'atk': 12, 'ls': 10}, ['leech', 'blade'], 510,
     {}, '')
item('thruster', '冲锋推进器', 'advanced', 'mob', 'boot', 'ffb030', '4ac0a0', {'ms': 50, 'as': 10}, ['boots', 'chip'], 725,
     {'charge_move': 0.5}, '蓄力时的移速惩罚减半')
item('tboots', '战术护靴', 'advanced', 'mob', 'boot', 'a0b0c8', '4ac0a0', {'ms': 45, 'def': 15}, ['boots', 'plate'], 670,
     {'hurt_haste': [0.15, 2.0]}, '受到伤害后 2 秒内移速 +15%')
item('hawk', '鹰眼镜组', 'advanced', 'eye', 'scope', 'e0e060', '60e0ff', {'range': 70, 'vision': 200, 'pspd': 200},
     ['scope', 'lens'], 900, {'far_bonus': 0.15}, '远程普攻飞行超过攻击距离后伤害 +15%（近战只获得一半攻击距离）')
item('beacon', '支援信标', 'advanced', 'pow', 'beacon', '5dff7a', 'ffd23f', {'mpr': 2, 'hpr': 3}, ['cap', 'gel'], 600,
     {'heal_amp': 0.15}, '你施加的治疗和护盾 +15%')

# ---------------- ultimate items: finished item + basic + upgrade fee ----------------
item('annihil', '歼灭者', 'ultimate', 'dmg', 'blade', 'ffd23f', 'ff3a3a', {'atk': 45, 'as': 20}, ['rage', 'blade'], 2000,
     {'crit': [0.3, 2.2]}, '普攻有 30% 几率造成 220% 伤害')
item('storm', '风暴核心', 'ultimate', 'spd', 'coil', 'ffd23f', '6ad8ff', {'as': 60}, ['coil', 'chip'], 1825,
     {'arc': [3, 5, 80.0]}, '每第 3 次普攻命中释放连锁电弧，弹跳 5 次，每次 80 法术伤害')
item('singular', '奇点透镜', 'ultimate', 'pow', 'orb', 'b060ff', 'ffffff', {'pow': 35, 'mana': 250, 'cdr': 20}, ['qcirc', 'core'], 2300,
     {'spell_vamp': 0.15}, '技能伤害的 15% 转为生命')
item('permafrost', '永冻之心', 'ultimate', 'def', 'flake', '6ad8ff', 'ffffff', {'def': 45, 'res': 25, 'hp': 250},
     ['reactive', 'coat'], 2300, {'as_aura': [0.2, 600.0]}, '光环：600 范围内对手攻击间隔 +20%')
item('undying', '不灭心核', 'ultimate', 'def', 'heart', 'ff3a4a', 'ffc0c0', {'hp': 700, 'hpr': 8}, ['pod', 'battery'], 2100,
     {'heart': 1.0}, '每秒额外回复 1% 最大生命')
item('bloodrage', '嗜血狂刃', 'ultimate', 'dmg', 'fang', 'ff2a4a', 'ffd23f', {'atk': 35, 'ls': 18}, ['gauntlet', 'blade'], 1800,
     {'low_ls': 0.35}, '生命低于 35% 时吸血翻倍')

# ---------------- hero upgrades (once per map) ----------------
item('chipx', '特化芯片', 'upgrade', 'hero', 'chipx', 'ffd23f', '6ad8ff', {}, [], 0, {'shard': True},
     '永久强化该英雄的右键（不占物品栏，限购 1 次）', cost=1400)
item('protocol', '终极协议', 'upgrade', 'hero', 'orb', '4aa8ff', 'ffd23f', {'hp': 250, 'pow': 10}, [], 0, {'scepter': True},
     '强化该英雄的 R（占一个物品栏）', cost=3800)

# ---- sanity
for it in I:
    if it['comps']:
        assert it['cost'] == sum(ids[c]['cost'] for c in it['comps']) + it['recipe'], it['id']
    for k in it['stats']:
        assert k in PRICE, (it['id'], k)

# ---------------- GDScript DB ----------------
def gd(v):
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list): return '[' + ', '.join(gd(x) for x in v) + ']'
    if isinstance(v, dict): return '{' + ', '.join(f'{json.dumps(k, ensure_ascii=False)}: {gd(x)}' for k, x in v.items()) + '}'
    raise TypeError(v)

lines = ['extends RefCounted', '## Generated by tools/gen_items.py — do not edit by hand.',
         '## cat: basic | advanced | ultimate | upgrade (hero upgrades). kind: shop tab, see KINDS.', '',
         'const KINDS := ' + gd(KINDS), '', 'const ORDER := ' + gd([it['id'] for it in I]), '', 'const DB := {']
for it in I:
    d = {k: it[k] for k in ('name', 'cat', 'kind', 'cost', 'comps', 'recipe', 'stats', 'special', 'note')}
    lines.append(f'\t"{it["id"]}": {gd(d)},')
lines.append('}')
open(os.path.join(ROOT, 'items_db.gd'), 'w').write('\n'.join(lines) + '\n')

# ---------------- icons (24x24, neon on dark) ----------------
S, COLS = 24, 10
def hexc(h, f=1.0, a=255):
    c = [min(255, max(0, int(int(h[i:i + 2], 16) * f))) for i in (0, 2, 4)]
    return (c[0], c[1], c[2], a)
TIER_FRAME = {'basic': '4a5070', 'advanced': '6ad8ff', 'ultimate': 'ffd23f', 'upgrade': 'ff6ad8'}

def put(img, x, y, c):
    x, y = int(x), int(y)
    if 1 <= x < S - 1 and 1 <= y < S - 1:
        img.putpixel((x, y), c)
def line(img, x0, y0, x1, y1, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0), 1))
    for i in range(n + 1):
        t = i / n
        put(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)
def rect(img, x0, y0, x1, y1, c, fill=True):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if fill or y in (y0, y1) or x in (x0, x1):
                put(img, x, y, c)
def disc(img, cx, cy, r, c):
    for y in range(S):
        for x in range(S):
            if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r:
                put(img, x, y, c)
def circ(img, cx, cy, r, c):
    for a in range(48):
        t = a / 48 * 2 * math.pi
        put(img, cx + math.cos(t) * r, cy + math.sin(t) * r, c)

def glyph(img, g, c1, c2, d):
    if g == 'blade':
        for i in range(12): line(img, 6 + i, 17 - i, 7 + i, 17 - i, c1)
        line(img, 5, 18, 9, 14, c2); line(img, 17, 5, 19, 4, c2)
    elif g in ('chip', 'chipx'):
        rect(img, 7, 7, 16, 16, d); rect(img, 7, 7, 16, 16, c1, False); rect(img, 10, 10, 13, 13, c2)
        for k in (9, 12, 15):
            line(img, 4, k - 1, 6, k - 1, c1); line(img, 17, k - 1, 19, k - 1, c1)
            line(img, k - 1, 4, k - 1, 6, c1); line(img, k - 1, 17, k - 1, 19, c1)
        if g == 'chipx': put(img, 11, 11, (255, 255, 255, 255)); put(img, 12, 12, (255, 255, 255, 255))
    elif g == 'core':
        disc(img, 12, 12, 7, d); circ(img, 12, 12, 7, c1); disc(img, 12, 12, 3, c2)
        line(img, 12, 3, 12, 6, c1); line(img, 12, 18, 12, 21, c1)
    elif g == 'cell':
        rect(img, 8, 5, 15, 19, d); rect(img, 8, 5, 15, 19, c1, False); rect(img, 10, 3, 13, 4, c1)
        rect(img, 10, 12, 13, 17, c2)
    elif g == 'plate':
        rect(img, 6, 6, 17, 13, d)
        for y in range(14, 19): line(img, 6 + (y - 13), y, 17 - (y - 13), y, d)
        rect(img, 6, 6, 17, 13, c1, False); line(img, 6, 13, 11, 18, c1); line(img, 17, 13, 12, 18, c1)
        line(img, 12, 7, 12, 16, c2)
    elif g == 'shield':
        circ(img, 12, 12, 8, c1); circ(img, 12, 12, 6, c2); circ(img, 12, 12, 4, c1)
    elif g == 'drop':
        disc(img, 12, 14, 5, c1)
        for y in range(5, 10): line(img, 12 - (y - 5) // 2, y, 12 + (y - 5) // 2, y, c1)
        put(img, 10, 13, c2); put(img, 10, 14, c2)
    elif g == 'fang':
        for y in range(5, 19): line(img, 8, y, 8 + max(0, (19 - y) // 3), y, c1); line(img, 15, y, 15 + max(0, (19 - y) // 3), y, c1)
        line(img, 7, 5, 18, 5, c2)
    elif g == 'boot':
        rect(img, 8, 4, 12, 14, c1); rect(img, 8, 15, 18, 18, c1); line(img, 5, 9, 7, 9, c2); line(img, 4, 12, 7, 12, c2)
        line(img, 13, 16, 18, 16, c2)
    elif g == 'scope':
        circ(img, 12, 12, 7, c1); line(img, 12, 3, 12, 9, c2); line(img, 12, 15, 12, 21, c2)
        line(img, 3, 12, 9, 12, c2); line(img, 15, 12, 21, 12, c2); put(img, 12, 12, c1)
    elif g == 'lens':
        disc(img, 12, 12, 7, d); circ(img, 12, 12, 7, c1); disc(img, 10, 10, 2, c2); circ(img, 12, 12, 4, c1)
    elif g == 'mag':
        rect(img, 8, 4, 15, 19, d); rect(img, 8, 4, 15, 19, c1, False)
        for y in (7, 10, 13, 16): line(img, 10, y, 13, y, c2)
    elif g == 'drill':
        for y in range(5, 18): line(img, 12 - (y - 5) // 3, y, 12 + (y - 5) // 3, y, c1)
        line(img, 8, 9, 16, 11, c2); line(img, 8, 13, 16, 15, c2); rect(img, 10, 18, 14, 20, c2)
    elif g == 'coil':
        for k in range(4): circ(img, 12, 6 + k * 4, 4, c1)
        line(img, 12, 3, 14, 7, c2); line(img, 14, 7, 10, 12, c2); line(img, 10, 12, 13, 20, c2)
    elif g == 'syringe':
        line(img, 5, 19, 17, 7, c1); line(img, 6, 19, 18, 7, c1); line(img, 7, 18, 13, 12, c2)
        line(img, 16, 5, 20, 9, c1); line(img, 3, 21, 5, 19, c2)
    elif g == 'beacon':
        rect(img, 10, 10, 13, 19, c1); circ(img, 12, 8, 3, c2); circ(img, 12, 8, 6, c1)
    elif g == 'orb':
        disc(img, 12, 12, 8, d); circ(img, 12, 12, 8, c1); disc(img, 12, 12, 4, c2); disc(img, 10, 10, 1.5, (255, 255, 255, 255))
    elif g == 'flake':
        for a in range(6):
            t = a / 6 * 2 * math.pi
            line(img, 12, 12, 12 + math.cos(t) * 8, 12 + math.sin(t) * 8, c1)
            put(img, 12 + math.cos(t) * 5, 12 + math.sin(t) * 5, c2)
        disc(img, 12, 12, 2, c2)
    elif g == 'heart':
        disc(img, 9, 10, 4, c1); disc(img, 15, 10, 4, c1)
        for y in range(11, 20): line(img, 5 + (y - 11), y, 19 - (y - 11), y, c1)
        put(img, 8, 9, c2); put(img, 9, 8, c2)
    else:
        disc(img, 12, 12, 6, c1)

rows = (len(I) + COLS - 1) // COLS
sheet = Image.new('RGBA', (COLS * S, rows * S), (0, 0, 0, 0))
for n, it in enumerate(I):
    img = Image.new('RGBA', (S, S), (10, 8, 22, 255))
    fr = hexc(TIER_FRAME[it['cat']])
    for k in range(S):
        img.putpixel((k, 0), fr); img.putpixel((k, S - 1), fr); img.putpixel((0, k), fr); img.putpixel((S - 1, k), fr)
    glyph(img, it['glyph'], hexc(it['c1']), hexc(it['c2']), hexc(it['c1'], 0.35))
    sheet.paste(img, ((n % COLS) * S, (n // COLS) * S))
sheet.save(os.path.join(ROOT, 'art', 'items.png'))
print('items:', len(I), ' basic', sum(1 for i in I if i['cat'] == 'basic'), ' advanced', sum(1 for i in I if i['cat'] == 'advanced'),
      ' ultimate', sum(1 for i in I if i['cat'] == 'ultimate'), ' upgrade', sum(1 for i in I if i['cat'] == 'upgrade'))
for it in I:
    print(f"  {it['id']:<10} {it['name']:<6} {it['cat']:<9} {it['cost']:>5}  {it['stats']}  {it['special']}")
