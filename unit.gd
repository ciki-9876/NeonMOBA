extends Node2D
## Base class for everything that can fight (heroes, hero.gd). Survival creeps were retired in stage 1.5;
## a few of their fields (boss, kind) remain because skill code still checks them.
## Holds shared combat state so skills, items and AI can treat every target the same way.
##
## Generic buffs (add_buff / has_buff / buff_v), used by the data-driven skill system:
##   root     can't move (can still attack / cast)
##   taunt    forced to attack buffs["taunt"].src
##   banish   invulnerable and can't act
##   dr       damage reduction (v = 0..1)
##   haste    move speed bonus (v = fraction)
##   as       attack speed bonus (flat)
##   def      physical defense bonus (flat)
##   res      magic resist bonus (flat)
##   grievous incoming heals and shields reduced (v = 0..1)
##   regen    hp regen bonus (per second)
## barrier / barrier_t : a damage-absorbing shield

const NEGATIVE := ["root", "taunt", "grievous"]

var team := 1
## deterministic id inside the current match (assigned by game/match.gd). Use it instead of
## get_instance_id() for any gameplay decision, otherwise results stop depending only on the seed.
var uid := 0
## last time this unit attacked / cast: in brush it stays visible for a moment afterwards
var revealed_t := -99.0
var is_hero := false
var kind := ""
var boss := false
var hp := 1.0
var max_hp := 1.0
var radius := 16.0
var armor := 0.0
var mr := 0.0
var dead := false

# classic status fields (kept as plain fields because creeps & kits read them every frame)
var stun := 0.0
var slow := 0.0
var slow_pct := 0.4
var silence := 0.0
var invuln := 0.0         # untargetable + immune (e.g. during 千刃)
var deso_t := 0.0         # 破甲钻头 armor break: time left
var deso_v := 0.0         # 破甲钻头 armor break: defense removed
var ac_v := 0.0           # defense removed by an enemy aura this frame (unused by current items)
var shiva_v := 0.0        # attack-interval penalty from an enemy 永冻之心 aura this frame
var charged := 0.0        # 霓虹 kit: 感电
var mark := 0.0           # 绯刃 kit: 血印
var mark_src: Object = null

# generic buffs
var buffs := {}
var barrier := 0.0
var barrier_max := 0.0
var barrier_t := 0.0

# motion / feedback
var flash := 0.0
var knock := Vector2.ZERO
var pull := Vector2.ZERO
var base_col := Color.WHITE

func armor_val() -> float:
	var a := armor + buff_v("def")
	if deso_t > 0.0: a -= deso_v
	return a - ac_v

func mr_val() -> float:
	return mr + buff_v("res")

func targetable() -> bool:
	return not dead and invuln <= 0.0 and not buffs.has("banish")

## hard-disabled: can't act on its own will
func disabled() -> bool:
	return stun > 0.0 or buffs.has("banish") or buffs.has("taunt")

func disable_left() -> float:
	var t := stun
	for id in ["taunt", "root"]:
		if buffs.has(id):
			t = maxf(t, float(buffs[id]["t"]))
	return t

func add_buff(id: String, dur: float, v := 0.0, src: Object = null) -> void:
	if dead or dur <= 0.0:
		return
	if buffs.has(id):
		var b: Dictionary = buffs[id]
		b["t"] = maxf(float(b["t"]), dur)
		b["v"] = maxf(float(b["v"]), v)
		if src != null:
			b["src"] = src
	else:
		buffs[id] = {"t": dur, "v": v, "src": src}

func has_buff(id: String) -> bool:
	return buffs.has(id)

func buff_v(id: String) -> float:
	return float(buffs[id]["v"]) if buffs.has(id) else 0.0

func buff_src(id: String) -> Object:
	if not buffs.has(id):
		return null
	var s = buffs[id]["src"]
	if s == null or not is_instance_valid(s):
		return null
	return s

func add_barrier(amount: float, dur: float) -> void:
	amount *= 1.0 - buff_v("grievous")
	if barrier_t <= 0.0:
		barrier = 0.0
	barrier = maxf(barrier, amount)
	barrier_max = barrier
	barrier_t = maxf(barrier_t, dur)

func dmg_taken_mult() -> float:
	return 1.0 - clampf(buff_v("dr"), 0.0, 0.9)

## removes debuffs; strong also removes stuns
func cleanse(strong: bool) -> void:
	slow = 0.0
	silence = 0.0
	deso_t = 0.0
	mark = 0.0
	charged = 0.0
	for id in NEGATIVE:
		buffs.erase(id)
	if strong:
		stun = 0.0

## 0..1: crowd control on this unit wears off this much faster in time (反应装甲 韧性)
func tenacity() -> float:
	return 0.0

func tick_status(d: float) -> void:
	var cc_d := d / maxf(0.2, 1.0 - tenacity())
	stun = maxf(0.0, stun - cc_d)
	slow = maxf(0.0, slow - cc_d)
	silence = maxf(0.0, silence - cc_d)
	invuln = maxf(0.0, invuln - d)
	deso_t = maxf(0.0, deso_t - d)
	charged = maxf(0.0, charged - d)
	mark = maxf(0.0, mark - d)
	flash -= d
	if barrier_t > 0.0:
		barrier_t -= d
		if barrier_t <= 0.0 or barrier <= 0.0:
			barrier = 0.0
			barrier_t = 0.0
	if not buffs.is_empty():
		var gone := []
		for id in buffs:
			var b: Dictionary = buffs[id]
			b["t"] = float(b["t"]) - (cc_d if NEGATIVE.has(id) else d)
			if float(b["t"]) <= 0.0:
				gone.append(id)
		for id in gone:
			buffs.erase(id)
