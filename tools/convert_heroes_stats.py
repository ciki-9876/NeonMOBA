#!/usr/bin/env python3
"""One-off (reusable) converter: old attribute heroes -> fixed secondary-stat panel.
Design: docs/design/属性与装备迭代设计案.md.  Usage: python3 tools/convert_heroes_stats.py heroes_db.gd

For each hero entry it
  * replaces "primary"/"base"/"gain"/"base_dmg"/"bat"/"ms"/"armor" with "stats": {hp, atk, interval, def, res,
    mana, hpr, mpr, ms} (the level-12 panel of the old formulas, passives excluded; HP before the round-mode
    multiplier). Heroes not in PANEL are derived from their old numbers at level 12 (same formulas as before);
  * converts str/agi/int scaling dicts with RIGHTCLICK (or by evaluating them at level 12);
  * buff / passive "armor" -> "def" (x6, same damage reduction under 100/(100+def)).
"""
import re, sys

# hero: hp, atk, interval, def, res, mana, hpr, mpr, ms
PANEL = {
    'aegis':  (1525, 90, 1.24, 53, 39, 478, 7.0, 2.2, 300),
    'anchor': (1595, 96, 1.36, 37, 37, 453, 7.3, 2.1, 295),
    'frost':  (1641, 96, 1.34, 46, 39, 503, 7.6, 2.3, 300),
    'drift':  (1102, 86, 0.97, 55, 41, 644, 5.1, 2.9, 305),
    'blade':  (1454, 88, 1.04, 56, 39, 478, 6.7, 2.2, 315),
    'ember':  (1289, 90, 1.17, 49, 43, 797, 6.0, 3.5, 305),
    'lumen':  (1080, 83, 1.27, 40, 41, 759, 5.0, 3.4, 300),
    'seer':   (1010, 81, 1.14, 46, 41, 721, 4.7, 3.2, 305),
    'tide':   (1010, 83, 1.24, 43, 41, 759, 4.7, 3.4, 305),
}
# right-click (or any) scaling dicts, old text -> new text
RIGHTCLICK = {
    '{"v": 30, "agi": 1.1, "charge": [0.5, 1.2]}': '{"v": 30, "atk": 0.7, "charge": [0.5, 1.2]}',
    '{"v": 30, "str": 1.1}': '{"v": 30, "atk": 0.72}',
    '{"v": 30, "str": 1.0}': '{"v": 30, "hp": 0.05}',
    '{"v": 30, "str": 1.2}': '{"v": 30, "hp": 0.06}',
    '{"v": 40, "int": 1.5}': '126',
    '{"v": 30, "int": 1.2}': '95',
    '{"v": 40, "str": 1.5}': '{"v": 40, "hp": 0.075}',
    '{"v": 55, "int": 1.9, "charge": [0.6, 1.4]}': '{"v": 169, "charge": [0.6, 1.4]}',
    '{"v": 40, "int": 1.6}': '131',
    '{"v": 2, "int": 0.08}': '6.6',
}

def derive(block):
    """level-12 panel from the old formulas (for heroes without a PANEL row)"""
    num = lambda k: float(re.search(r'"%s": ([\d.]+)' % k, block).group(1))
    base = {a: float(re.search(r'"base": \{[^}]*"%s": ([\d.]+)' % a, block).group(1)) for a in ('str', 'agi', 'int')}
    gain = {a: float(re.search(r'"gain": \{[^}]*"%s": ([\d.]+)' % a, block).group(1)) for a in ('str', 'agi', 'int')}
    v = {a: base[a] + gain[a] * 11 for a in base}
    prim = re.search(r'"primary": "(\w+)"', block).group(1)
    hp = 200 + v['str'] * 22
    mr = 1 - 0.75 * (1 - v['int'] * 0.001)
    return (round(hp), round(num('base_dmg') + v[prim]), round(num('bat') / (1 + v['agi'] / 100), 2),
            round(6 * (num('armor') + v['agi'] / 6)), round(100 * mr / (1 - mr)), round(75 + v['int'] * 12),
            round(1 + v['str'] * 0.1, 1), round(0.5 + v['int'] * 0.05, 1), round(num('ms')))

def convert(src):
    out = src
    for m in re.finditer(r'\n\t"(\w+)": \{\n', src):
        hid = m.group(1)
        start = m.end()
        nxt = re.search(r'\n\t"(\w+)": \{\n|\n\}', src[start:])
        block = src[start:start + nxt.start()]
        if '"primary"' not in block:
            continue
        p = PANEL.get(hid) or derive(block)
        stats = ('"stats": {"hp": %s, "atk": %s, "interval": %s, "def": %s, "res": %s, "mana": %s, "hpr": %s, "mpr": %s, "ms": %s},'
                 % tuple(p))
        nb = re.sub(r'"primary": "\w+", "base": \{[^}]*\}, "gain": \{[^}]*\},', stats, block)
        nb = re.sub(r'"base_dmg": [\d.]+, "bat": [\d.]+, ', '', nb)
        nb = re.sub(r'"ms": [\d.]+, "armor": [\d.]+, ', '', nb)
        for a, b in RIGHTCLICK.items():
            nb = nb.replace(a, b)
        nb = re.sub(r'"id": "armor", "v": \[([\d., ]+)\]',
                    lambda mm: '"id": "def", "v": [%s]' % ', '.join(str(int(float(x) * 6)) for x in mm.group(1).split(',')), nb)
        nb = re.sub(r'"armor": \[([\d., ]+)\]',
                    lambda mm: '"def": [%s]' % ', '.join(str(int(float(x) * 6)) for x in mm.group(1).split(',')), nb)
        for t in ('敏捷', '力量', '智力'):
            nb = nb.replace(' · ' + t + ' · ', ' · 近战 · ' if '"melee": true' in nb else ' · 远程 · ')
        assert not re.search(r'"(str|agi|int)": [\d.]', nb), (hid, re.findall(r'\{[^{}]*"(?:str|agi|int)"[^{}]*\}', nb))
        out = out.replace(block, nb)
    return out

if __name__ == '__main__':
    path = sys.argv[1]
    s = open(path, encoding='utf-8').read()
    open(path, 'w', encoding='utf-8').write(convert(s))
