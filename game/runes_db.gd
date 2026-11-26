extends RefCounted
## Hero runes (英雄符文, owned by the team, per hero) and player signature abilities (选手专属能力).
## Both are "mods" applied to a hero when the match starts (hero.gd apply_mods):
##   {"type": "stat", "key": "hp"|"atk"|"def"|"res"|"as"|"ms"|"mana"|"hpr"|"mpr"|"pow"|"cdr", "v": number}   (secondary stats, see hero.gd STAT_KEYS)
##   {"type": "skill", "skill": "q", "key": "width"|"cd"|..., "add": n | "mul": n}          top-level skill field
##   {"type": "skill", "skill": "q", "op": "slow", "key": "dur", "add": n | "mul": n}       every effect block {"do": op}
##   {"type": "append", "skill": "w", "effect": {...effect block...}}                       extra effect (data heroes)
## Numbers may be per-level arrays where the skill field is one; "add"/"mul" are applied element-wise.
## Stage 1 ships a few examples to prove the pipeline; the real content comes in stage 3.

## slot: stat (stackable up to max) | skill | core. hero: "" = any hero.
const RUNES := {
	# calibrated: a full page of all three (15 stacks) vs none should be a clear but not decisive edge
	"r_vital": {"name": "坚韧符文", "slot": "stat", "hero": "", "max": 5, "desc": "最大生命 +12/层",
		"mods": [{"type": "stat", "key": "hp", "v": 12.0}]},
	"r_edge": {"name": "锋锐符文", "slot": "stat", "hero": "", "max": 5, "desc": "攻击力 +1/层",
		"mods": [{"type": "stat", "key": "atk", "v": 1.0}]},
	"r_guard": {"name": "守御符文", "slot": "stat", "hero": "", "max": 5, "desc": "物理防御 +2/层",
		"mods": [{"type": "stat", "key": "def", "v": 2.0}]},
	"anchor_long_chain": {"name": "长链", "slot": "skill", "hero": "anchor", "max": 1, "desc": "锚钩距离 +120",
		"mods": [{"type": "skill", "skill": "w", "op": "shot", "key": "len", "add": 120.0}]},
	"frost_deep_freeze": {"name": "深度冻结", "slot": "core", "hero": "frost", "max": 1, "desc": "绝对零度定身时间 +0.3 秒",
		"mods": [{"type": "skill", "skill": "r", "op": "root", "key": "dur", "add": 0.3}]},
}

## per hero, 2–3 possible signature abilities; each player who has the hero as a signature owns one of them
const SIGNATURES := {
	"anchor_wide_hook": {"hero": "anchor", "name": "巨锚", "desc": "锚钩的判定宽度 +20",
		"mods": [{"type": "skill", "skill": "w", "op": "shot", "key": "w", "add": 20.0}]},
	"anchor_quick_hook": {"hero": "anchor", "name": "快钩", "desc": "锚钩出手更快（前摇 -0.12 秒）",
		"mods": [{"type": "skill", "skill": "w", "key": "cast_point", "add": -0.12}]},
	"ember_twin_blast": {"hero": "ember", "name": "余火", "desc": "炎爆术落地后在原地留下 1.5 秒的灼烧",
		"mods": [{"type": "append", "skill": "q", "effect": {"do": "zone", "dur": 1.5, "tick": 0.5, "r": 180.0, "at": "pos",
			"each": [{"do": "damage", "on": "enemies", "at": "pos", "r": 180.0, "amt": [10, 15, 20, 25]}]}}]},
	"frost_cold_aura": {"hero": "frost", "name": "寒潮", "desc": "霜之壁垒的减速范围 +80",
		"mods": [{"type": "skill", "skill": "q", "op": "slow", "key": "r", "add": 80.0}]},
}

## mods for a team rune page {rune_id: stacks} on one hero
static func rune_mods(page: Dictionary, hero_id: String) -> Array:
	var out := []
	for rid in page:
		if not RUNES.has(rid):
			continue
		var r: Dictionary = RUNES[rid]
		if str(r["hero"]) != "" and str(r["hero"]) != hero_id:
			continue
		var n: int = clampi(int(page[rid]), 0, int(r["max"]))
		for i in n:
			out.append_array(r["mods"])
	return out

static func signature_mods(sig_id: String, hero_id: String) -> Array:
	if not SIGNATURES.has(sig_id) or str(SIGNATURES[sig_id]["hero"]) != hero_id:
		return []
	return SIGNATURES[sig_id]["mods"]
