extends SceneTree
## Static checks of the fixed world and the story content (docs/design/角色设计规范.md 第六节).
## godot --headless --script res://sim/test_cast.gd
const Cast = preload("res://game/league/cast_db.gd")
const World = preload("res://game/league/world.gd")
const DB = preload("res://game/story/events_db.gd")
const Rules = preload("res://game/story/rules.gd")
const HeroesDB = preload("res://heroes_db.gd")
const RunesDB = preload("res://game/runes_db.gd")
var fails := 0
var warns := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("" if info == "" else "  (" + info + ")"))
	if not ok:
		fails += 1

func warn(text: String) -> void:
	print("WARN " + text)
	warns += 1

func _initialize() -> void:
	var w: Dictionary = World.build_fixed(1, "rin")
	var ids := {}
	for pid in w["players"]:
		ids[pid] = true
	for sid in w["staff"]:
		ids[sid] = true
	for t in w["teams"]:
		ids[str(t["id"])] = true
	# names
	var handles := {}
	var dup := []
	for pid in w["players"]:
		var nm: String = str(w["players"][pid]["name"])
		if handles.has(nm):
			dup.append(nm)
		handles[nm] = true
		for hid in HeroesDB.HEROES:
			if str(HeroesDB.HEROES[hid]["name"]) == nm or str(HeroesDB.HEROES[hid].get("short", "")) == nm:
				dup.append(nm + "(英雄名)")
	check("player handles are unique and not hero names", dup.is_empty(), str(dup))
	# rosters
	var bad := []
	for t in w["teams"]:
		var roles := {}
		for pid in t["players"]:
			roles[str(w["players"][pid]["role"])] = true
		if (t["players"] as Array).size() != 4 or roles.size() < 3:
			bad.append(str(t["id"]))
	check("every club has 4 players covering the 3 roles", bad.is_empty(), str(bad))
	check("16 clubs, 8 per league", World.league_teams(w, "pro").size() == 8 and World.league_teams(w, "sec").size() == 8)
	# gender ratio over named players (core + regular + generated club players)
	var f := 0
	var n := 0
	for pid in w["players"]:
		var p: Dictionary = w["players"][pid]
		if str(p["cast"]) in ["core", "regular", "gen"]:
			n += 1
			f += 1 if str(p["gender"]) == "f" else 0
	check("about a third of the named players are women", float(f) / n >= 0.27 and float(f) / n <= 0.42, "%d / %d" % [f, n])
	# heroes and signature abilities
	var bh := []
	for pid in w["players"]:
		var p: Dictionary = w["players"][pid]
		for hid in p["prof"]:
			if not HeroesDB.HEROES.has(hid):
				bh.append("%s:%s" % [pid, hid])
		for hid in p["sig"]:
			var ab: String = str(p["sig"][hid])
			if not HeroesDB.HEROES.has(hid) or (ab != "" and (not RunesDB.SIGNATURES.has(ab) or str(RunesDB.SIGNATURES[ab]["hero"]) != hid)):
				bh.append("%s sig %s/%s" % [pid, hid, ab])
	check("heroes and signature abilities exist", bh.is_empty(), str(bh))
	# budgets
	var over := []
	for pid in Cast.CORE:
		var p: Dictionary = w["players"][pid]
		for k in p["attrs"]:
			if int(p["attrs"][k]) > 17:
				over.append("%s %s" % [pid, k])
		if World.rating(p) > 16.0:
			over.append("%s mean" % pid)
		var pr: Array = p["pot_range"]
		if float(pr[1]) - float(pr[0]) > 4.0 or float(pr[1]) < float(pr[0]):
			over.append("%s potential %s" % [pid, str(pr)])
	check("core numbers within the budget", over.is_empty(), str(over))
	for t in w["teams"]:
		if str(t["league"]) != "pro":
			continue
		var tot := 0.0
		var k := 0
		for pid in t["players"]:
			if not (Cast.CORE.has(pid) and str(Cast.CORE[pid]["slot"]) == "bench"):
				tot += World.rating(w["players"][pid])
				k += 1
		var mean: float = float(Cast.TEAMS[t["id"]]["mean"])
		if absf(tot / k - mean) > 1.8:
			warn("club %s mean %.1f vs planned %.1f" % [t["id"], tot / k, mean])
	# relations
	var bl := []
	var links := {}
	for l in Cast.LINKS:
		for x in [l[0], l[1]]:
			if not ids.has(str(x)):
				bl.append(str(x))
			links[str(x)] = int(links.get(str(x), 0)) + 1
		if not Cast.LINK_VALUE.has(str(l[2])):
			bl.append("type " + str(l[2]))
	check("relations point to existing people", bl.is_empty(), str(bl))
	for pid in Cast.CORE:
		if int(links.get(pid, 0)) < 2:
			warn("core %s has %d relations (spec: at least 2)" % [pid, int(links.get(pid, 0))])
	# story content: vocabulary and references
	var errs := []
	var tl_ids := {}
	for e in DB.TIMELINE:
		var id: String = str(e["id"])
		if tl_ids.has(id):
			errs.append("duplicate timeline id " + id)
		tl_ids[id] = true
		if str(e["owner"]) != "world" and not ids.has(str(e["owner"])):
			errs.append("%s owner %s" % [id, e["owner"]])
		if not (str(e["at"]) in ["pre", "po", "end", "off"] or str(e["at"]).begins_with("w")):
			errs.append("%s at %s" % [id, e["at"]])
		_conds(e.get("if", []), id, ids, errs)
		_conds(e.get("result", []), id, ids, errs)
		_effects(e.get("do", []), id, ids, errs)
		if e.has("event") and not DB.EVENTS.has(str(e["event"])):
			errs.append("%s event %s" % [id, e["event"]])
	for ev in DB.EVENTS:
		for c in DB.EVENTS[ev].get("choices", []):
			_effects(c.get("effects", []), ev, ids, errs)
		for b in DB.EVENTS[ev].get("branches", []):
			_conds(b.get("if", []), ev, ids, errs)
			_effects(b.get("effects", []), ev, ids, errs)
		var past := 0
		for c in DB.EVENTS[ev].get("choices", []):
			past += 1 if bool(c.get("past", false)) else 0
		if not bool(DB.EVENTS[ev].get("auto", false)) and past != 1:
			errs.append("%s: exactly one choice must be marked past (%d)" % [ev, past])
	for g in DB.GENERIC:
		if not DB.EVENTS.has(str(g["id"])):
			errs.append("generic %s has no choice event" % g["id"])
		_conds(g["if"], str(g["id"]), ids, errs)
		_effects(g.get("ai", []), str(g["id"]), ids, errs)
	for nt in DB.NOTES:
		if not tl_ids.has(str(nt["bind"])):
			errs.append("note %s bind %s" % [nt["id"], nt["bind"]])
		var wh: String = str(nt["when"])
		if wh.begins_with("meet:") and not ids.has(wh.substr(5)):
			errs.append("note %s meets %s" % [nt["id"], wh])
	for pid in DB.ENDINGS:
		if not ids.has(pid):
			errs.append("ending of " + pid)
		for en in DB.ENDINGS[pid]:
			_conds(en["if"], "ending " + pid, ids, errs)
	check("story content uses the vocabulary and existing ids", errs.is_empty(), "; ".join(PackedStringArray(errs.slice(0, 8))))
	# timeline conflicts: two people moving into the same club and role at the same time
	var slots := {}
	var conf := []
	for e in DB.TIMELINE:
		for ef in e.get("do", []):
			if str(ef[0]) == "move" and w["players"].has(str(ef[1])):
				var k: String = "S%d %s %s %s" % [int(e["s"]), e["at"], ef[2], w["players"][str(ef[1])]["role"]]
				if slots.has(k):
					conf.append(k)
				slots[k] = true
	check("no conflicting moves in the timeline", conf.is_empty(), str(conf))
	print("RESULT %s (%d failed, %d warnings)" % ["OK" if fails == 0 else "FAILED", fails, warns])
	quit(1 if fails > 0 else 0)

func _ref_ok(v, ids: Dictionary) -> bool:
	if typeof(v) != TYPE_STRING:
		return true
	var s: String = str(v)
	return s.begins_with("$") or ids.has(s)

func _conds(list: Array, where: String, ids: Dictionary, errs: Array) -> void:
	for c in list:
		var name: String = str(c[0])
		if not Rules.CONDITIONS.has(name):
			errs.append("%s: condition %s" % [where, name])
			continue
		if name in ["not"]:
			_conds([c[1]], where, ids, errs)
		elif name == "any":
			_conds(c[1], where, ids, errs)
		elif name in ["team_of", "same_team", "free_agent", "human_team", "attr_avg", "fame", "fatigue", "form", "satisfaction", "bench_streak",
				"age", "persona", "contract_pay", "retired", "comm_low", "role", "suspended", "staff_free"]:
			if not _ref_ok(c[1], ids):
				errs.append("%s: %s of unknown %s" % [where, name, c[1]])
			if name in ["team_of", "same_team"] and str(c[2]) != "" and not _ref_ok(c[2], ids):
				errs.append("%s: %s unknown %s" % [where, name, c[2]])
		elif name in ["league_of", "team_rank", "streak", "made_playoffs"] and not _ref_ok(c[1], ids):
			errs.append("%s: unknown club %s" % [where, c[1]])

func _effects(list: Array, where: String, ids: Dictionary, errs: Array) -> void:
	for e in list:
		var name: String = str(e[0])
		if not Rules.EFFECTS.has(name):
			errs.append("%s: effect %s" % [where, name])
			continue
		if name in ["chain"] and not DB.EVENTS.has(str(e[1])):
			errs.append("%s: chain %s" % [where, e[1]])
		elif name in ["move", "coach"]:
			if not _ref_ok(e[1], ids) or (str(e[2]) != "" and not _ref_ok(e[2], ids)):
				errs.append("%s: %s %s -> %s" % [where, name, e[1], e[2]])
		elif name in ["attr", "prof", "potential", "persona", "fame", "form", "satisfaction", "respect", "fatigue", "release", "retire", "suspend", "lang", "trait_add", "trait_remove", "contract_pay"]:
			if not _ref_ok(e[1], ids):
				errs.append("%s: %s of unknown %s" % [where, name, e[1]])
		elif name in ["suspend_team", "relegate", "fold"] and not _ref_ok(e[1], ids):
			errs.append("%s: %s unknown club %s" % [where, name, e[1]])
