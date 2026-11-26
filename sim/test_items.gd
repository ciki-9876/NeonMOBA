extends SceneTree
## Unit checks for the secondary-stat system and item effects (docs/design/属性与装备迭代设计案.md).
## godot --headless --script res://sim/test_items.gd      prints PASS/FAIL lines, exit code 1 on any failure
const MatchT = preload("res://game/match.gd")
const C = preload("res://game/consts.gd")
var gm: MatchT
var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if info == "" else "  (" + info + ")"))
	if not ok:
		fails += 1

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

func _initialize() -> void:
	gm = MatchT.new()
	root.add_child(gm)
	gm._start_rounds(["aegis", "lumen", "drift"], ["frost", "seer", "ember"], 1, 7, {"human": false, "map": "core_open"})
	var a = gm.heroes[0]   # aegis
	var d = gm.heroes[2]   # drift
	var e = gm.heroes[3]   # frost (foe)
	# fixed panel: no attributes, levels don't change stats
	check("defense curve", near(gm.def_mult(100.0), 0.5) and near(gm.def_mult(0.0), 1.0) and gm.def_mult(-50.0) > 1.0)
	check("aegis panel def", near(a.armor_val(), 53.0), str(a.armor_val()))
	check("drift interval (E passive +40%)", near(d.atk_interval(), 0.97 / (float(d.ST["as"]) / 100.0)), str(d.atk_interval()))
	var as0: float = float(d.ST["as"])
	var hp0: float = a.max_hp
	a.level += 5
	a.recalc()
	check("levels give no stats", near(a.max_hp, hp0))
	# items: stats
	d.inv = ["chip", "blade", "core"]
	d.recalc()
	check("as +15% shortens the interval", near(d.atk_interval(), 0.97 / ((as0 + 15.0) / 100.0)), str(d.atk_interval()))
	check("atk +10", near(d.atk_dmg(), 96.0), str(d.atk_dmg()))
	check("pow +10%", near(d.pow_mult(), 1.1))
	# skill power applies to skill damage, not to attacks
	e.hp = e.max_hp
	var before: float = e.hp
	var got: float = gm.damage(d, e, 100.0, "skill", "magic")
	check("skill dmg = 100 x pow x res", near(got, 100.0 * 1.1 * gm.def_mult(e.mr_val())), "%.1f" % got)
	got = gm.damage(d, e, 100.0, "attack", "phys", Vector2.ZERO, true)
	check("attack dmg = 100 x def", near(got, 100.0 * gm.def_mult(e.armor_val())), "%.1f" % got)
	e.hp = before
	# armor break
	d.inv = ["drill"]
	d.recalc()
	var def0: float = e.armor_val()
	d.attack_hit(e, 50.0, {})
	check("破甲钻头 -20 def", near(e.armor_val(), def0 - 20.0), "%.1f -> %.1f" % [def0, e.armor_val()])
	# grievous + heal
	d.inv = ["wound"]
	d.recalc()
	e.hp = 500.0
	gm.damage(d, e, 10.0, "skill", "magic")
	check("重创 applied", e.has_buff("grievous"))
	var hp1: float = e.hp
	gm.heal(null, e, 100.0)
	check("重创 heal -40%", near(e.hp - hp1, 60.0), "%.1f" % (e.hp - hp1))
	# spell shield: first skill hit each round
	e.inv = ["barrier"]
	e.recalc()
	e.spell_shield_used = false
	e.buffs.erase("grievous")
	var hp2: float = e.hp
	gm.damage(a, e, 150.0, "skill", "pure")
	check("屏障发生器 absorbs the first skill hit", near(e.hp, hp2), "%.1f" % (hp2 - e.hp))
	# tenacity
	e.inv = ["reactive"]
	e.recalc()
	e.stun = 1.0
	e.tick_status(0.4)
	check("韧性 20%: 0.4 s ticks 0.5 s of stun", near(e.stun, 0.5), "%.2f" % e.stun)
	e.stun = 0.0
	# arc every 4th attack
	d.inv = ["coil"]
	d.recalc()
	d.arc_n = 0
	e.barrier = 0.0
	var hp3: float = e.hp
	for i in 3:
		d.attack_hit(e, 10.0, {})
	check("超载线圈 no arc before the 4th hit", d.arc_n == 3)
	d.attack_hit(e, 10.0, {})
	check("超载线圈 arcs on the 4th hit", d.arc_n == 0 and e.hp < hp3)
	# upgrades: data hero patch, refund-safe
	var cd0: float = a.sv("w", "cd")
	a.gold = 9000.0
	gm.buy_for(a, "chipx", false)
	check("特化芯片 patches the right-click", near(a.sv("w", "cd"), cd0 - 3.0), "%.1f" % a.sv("w", "cd"))
	check("特化芯片 takes no slot", a.inv.is_empty() or not a.inv.has("chipx"))
	var rcd: float = a.sv("r", "cd") if int(a.sk["r"]) > 0 else -1.0
	gm.buy_for(a, "protocol", false)
	check("终极协议 owned", a.has_scepter())
	if rcd > 0.0:
		check("终极协议 patches R", near(a.sv("r", "cd"), rcd - 10.0), "%.1f" % a.sv("r", "cd"))
	gm.sell_for(a, a.inv.find("protocol"))
	if rcd > 0.0:
		check("selling 终极协议 restores R", near(a.sv("r", "cd"), rcd))
	check("shared HeroesDB untouched", near(float(a.def["skills"]["w"]["cd"]), cd0))
	print("RESULT %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
