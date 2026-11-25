extends RefCounted
## Base class for a hero's skill kit. hero.gd owns orders, attacks, stats and items;
## a kit only implements what is unique to the hero. Every method has a safe default,
## so a new hero overrides just the hooks it needs.

var h   # the hero (hero.gd)
var g   # the game (main.gd)

func setup(hero, game) -> void:
	h = hero
	g = game

## reset kit state (new game / respawn)
func reset() -> void:
	pass

## new round in round mode: also drop lingering zones / projectiles
func round_reset() -> void:
	reset()

## telegraphed danger this kit has on the ground / in flight, for the AI to dodge:
##   [{"kind": "area", "pos", "r", "t" (seconds until it lands)}, {"kind": "shot", "pos", "dir", "w", "speed", "left"}]
func threats() -> Array:
	return []

## add kit-provided stats during hero recalc (e.g. passive attack speed)
func stat_mods(_n: Dictionary) -> void:
	pass

## extra cooldown reduction in seconds (e.g. scepter upgrades)
func cd_reduction(_s: String) -> float:
	return 0.0

## how close the hero must walk before casting; 0 = cast from anywhere
func cast_range(s: String, _tgt) -> float:
	var r: float = float(h.sdef[s].get("range", 0.0))
	return r + float(h.ST.get("cast", 0.0)) if r > 0.0 else 0.0

## extra validation; return an error text or ""
func check(_s: String, _tgt) -> String:
	return ""

## perform the skill effect at the end of the cast point
func cast(_s: String, _tgt, _pos: Vector2, _chg := 0.0) -> void:
	pass

## called after any skill was cast
func on_cast(_s: String) -> void:
	pass

## an attack is launched; may write info["proc"], info["bonus"], info["ls"]
func on_attack_fire(_tgt, _info: Dictionary) -> void:
	pass

## an attack landed (after damage)
func on_attack_hit(_tgt, _info: Dictionary) -> void:
	pass

## per-frame logic while the hero is alive
func tick(_d: float) -> void:
	pass

## per-frame logic that keeps running even when the hero is dead (lingering zones)
func tick_world(_d: float) -> void:
	pass

## true while the kit controls the hero (no orders accepted)
func busy() -> bool:
	return false

## estimated damage of a skill against one hero, used by the AI for kill decisions
func est_damage(s: String) -> float:
	return h.sv(s, "dmg")

## world-space drawing (zones, telegraphs)
func draw(_o: Node2D) -> void:
	pass

## AI description of a skill (roles / aim / thresholds). Data kits infer it from effects.
func ai_meta(s: String) -> Dictionary:
	return h.sdef[s].get("ai", {})

## estimated healing of a skill on one ally, used by the AI
func est_heal(_s: String) -> float:
	return 0.0

## tooltip text for the HUD
func tip(s: String) -> String:
	return str(h.def.get("tips", {}).get(s, ""))

## the radius used by indicators / AI for a skill
func skill_radius(s: String) -> float:
	return float(h.sdef[s].get("radius", 0.0))
