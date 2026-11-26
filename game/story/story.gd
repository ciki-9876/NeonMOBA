extends RefCounted
## The story engine (M2): runs the original history (原本轨迹), state-driven generic events, the player's pending
## choices, past-life notes (前世笔记) and endings. State lives in world["story"] so it carries over seasons and saves:
##   {"flags": {}, "happened": {entry id: "S1W5"}, "failed": {entry id: "S1W5"}, "known": {note id: true},
##    "pending": [{"uid", "event", "ctx", "src", "key"}], "log": [{"s", "w", "text"}], "cool": {}, "budget": {}, "uid": n}
## Content: game/story/events_db.gd; vocabulary: game/story/rules.gd. Design: docs/design/角色机制设计.md 第四节.
const DB = preload("res://game/story/events_db.gd")
const Rules = preload("res://game/story/rules.gd")
const World = preload("res://game/league/world.gd")

const MAJOR_PER_WEEK := 1
const MINOR_PER_WEEK := 2
## conditions that describe where people are (used to tell whether a note is still likely to come true)
const STRUCTURAL := ["team_of", "free_agent", "staff_free", "league_of", "human_team", "retired", "coach_of"]

static func state(season: Dictionary) -> Dictionary:
	var w: Dictionary = season["world"]
	if not w.has("story") or (w["story"] as Dictionary).is_empty():
		w["story"] = {"flags": {}, "happened": {}, "failed": {}, "known": {}, "pending": [], "log": [], "cool": {}, "budget": {}, "uid": 0}
	return w["story"]

static func when_tag(season: Dictionary) -> String:
	return "S%dW%d" % [int(season.get("no", 1)), Rules.week_no(season)]

static func _rng(season: Dictionary, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(season["seed"]), int(season.get("no", 1)), Rules.week_no(season), str(season["phase"]), salt])
	return r

# ============================================================ hooks (called by game/league/season.gd)
static func start_career(season: Dictionary) -> void:
	var st := state(season)
	for n in DB.NOTES:
		if str(n["when"]) == "start":
			st["known"][n["id"]] = true

static func on_new_season(season: Dictionary) -> void:
	var st := state(season)
	for n in DB.NOTES:
		var wh: String = str(n["when"])
		if wh.begins_with("season:") and int(wh.substr(7)) <= int(season["no"]):
			st["known"][n["id"]] = true

## start of a stage: due timeline entries, generic events, suspensions, week-triggered notes
static func on_stage_start(season: Dictionary) -> void:
	var st := state(season)
	var codes := []
	match str(season["phase"]):
		"regular":
			codes.append("w%d" % (int(season["week"]) + 1))
			if int(season["week"]) == 0:
				codes.append("pre")
		"playoffs":
			if (season["leagues"]["pro"]["playoffs"] as Array).size() == 1:
				codes.append("po")
	var rng := _rng(season, 1)
	for e in DB.TIMELINE:
		if int(e["s"]) == int(season["no"]) and codes.has(str(e["at"])):
			_run_entry(season, e, rng)
	if str(season["phase"]) == "regular":
		for n in DB.NOTES:
			var wh: String = str(n["when"])
			if wh.begins_with("week:") and int(season["no"]) == 1 and int(wh.substr(5)) <= int(season["week"]) + 1:
				st["known"][n["id"]] = true
		for pid in season["world"]["players"]:
			var p: Dictionary = season["world"]["players"][pid]
			if int(p.get("suspended", 0)) > 0:
				p["suspended"] = int(p["suspended"]) - 1
		if int(season["week"]) >= 1:
			_generic(season, _rng(season, 2))

## a finished series: the human club meets people (notes "meet:<id>")
static func on_series(season: Dictionary, s: Dictionary) -> void:
	var h: String = str(season["human"])
	if h == "" or (str(s["a"]) != h and str(s["b"]) != h):
		return
	var opp: String = str(s["b"]) if str(s["a"]) == h else str(s["a"])
	var met := {}
	for pid in World.team(season["world"], opp).get("players", []):
		met[pid] = true
	for pid in World.team(season["world"], h).get("players", []):
		met[pid] = true
	if World.team(season["world"], opp).get("coach", "") != "":
		met[str(World.team(season["world"], opp)["coach"])] = true
	_meet(season, met)

static func _meet(season: Dictionary, met: Dictionary) -> void:
	var st := state(season)
	for n in DB.NOTES:
		var wh: String = str(n["when"])
		if wh.begins_with("meet:") and met.has(wh.substr(5)):
			st["known"][n["id"]] = true

## end of a season (before promotion / aging): "end" observations, then the off-season entries
static func on_offseason(season: Dictionary, rng: RandomNumberGenerator) -> void:
	auto_resolve(season)
	var st := state(season)
	for at in ["end", "off"]:
		for e in DB.TIMELINE:
			if int(e["s"]) == int(season["no"]) and str(e["at"]) == at:
				_run_entry(season, e, rng)
	auto_resolve(season)
	# whatever of this season was never reached did not happen
	for e in DB.TIMELINE:
		var id: String = str(e["id"])
		if int(e["s"]) <= int(season["no"]) and not st["happened"].has(id) and not st["failed"].has(id):
			st["failed"][id] = when_tag(season)

# ============================================================ timeline
static func _run_entry(season: Dictionary, e: Dictionary, rng: RandomNumberGenerator) -> void:
	var st := state(season)
	var id: String = str(e["id"])
	if st["happened"].has(id) or st["failed"].has(id):
		return
	if not Rules.all(season, e.get("if", [])):
		st["failed"][id] = when_tag(season)
		return
	if bool(e.get("check", false)):
		st["happened"][id] = when_tag(season)
		return
	if rng.randf() >= float(e.get("p", 1.0)):
		st["failed"][id] = when_tag(season)
		return
	if e.has("event"):
		raise(season, str(e["event"]), {}, id)
		return
	st["happened"][id] = when_tag(season)
	var lines: Array = Rules.apply(season, e.get("do", []), {}, rng)
	if e.has("news"):
		lines.insert(0, Rules.fill(season, str(e["news"])))
	_news(season, lines)

## offer a choice event: to the player when it concerns the human club, otherwise the original choice is taken
static func raise(season: Dictionary, ev_id: String, ctx := {}, src := "") -> void:
	var st := state(season)
	var ev: Dictionary = DB.EVENTS.get(ev_id, {})
	if ev.is_empty():
		push_warning("story: unknown event %s" % ev_id)
		return
	if bool(ev.get("auto", false)):
		for b in ev.get("branches", []):
			if Rules.all(season, b.get("if", []), ctx):
				_news(season, Rules.apply(season, b.get("effects", []), ctx))
				break
		return
	var who: String = str(Rules.arg(ev.get("who", ""), ctx))
	var human: bool = who != "" and str(season["world"]["players"].get(who, {}).get("team", "")) == str(season["human"])
	st["uid"] = int(st["uid"]) + 1
	var item := {"uid": int(st["uid"]), "event": ev_id, "ctx": ctx, "src": src, "key": when_tag(season)}
	if human:
		st["pending"].append(item)
	else:
		_resolve_item(season, item, past_choice(ev))

static func past_choice(ev: Dictionary) -> int:
	var ch: Array = ev.get("choices", [])
	for i in ch.size():
		if bool(ch[i].get("past", false)):
			return i
	return 0

## the player picks a choice of a pending event
static func resolve(season: Dictionary, uid: int, choice: int) -> void:
	var st := state(season)
	for i in (st["pending"] as Array).size():
		var it: Dictionary = st["pending"][i]
		if int(it["uid"]) == uid:
			st["pending"].remove_at(i)
			_resolve_item(season, it, choice)
			return

## every pending choice is taken the original way (simulate to the end, or the season is over)
static func auto_resolve(season: Dictionary) -> void:
	var st := state(season)
	var guard := 0
	while not (st["pending"] as Array).is_empty() and guard < 50:
		guard += 1
		var it: Dictionary = st["pending"].pop_front()
		_resolve_item(season, it, past_choice(DB.EVENTS.get(str(it["event"]), {})))

static func _resolve_item(season: Dictionary, it: Dictionary, choice: int) -> void:
	var st := state(season)
	var ev: Dictionary = DB.EVENTS.get(str(it["event"]), {})
	var ch: Array = ev.get("choices", [])
	if ch.is_empty():
		return
	choice = clampi(choice, 0, ch.size() - 1)
	var c: Dictionary = ch[choice]
	var rng := _rng(season, 3 + int(it["uid"]))
	_news(season, Rules.apply(season, c.get("effects", []), it.get("ctx", {}), rng))
	var src: String = str(it.get("src", ""))
	if src != "":
		var e := entry(src)
		var ok: bool = bool(c.get("past", false))
		if e.has("result"):
			ok = Rules.all(season, e["result"])
		if ok:
			st["happened"][src] = str(it["key"])
		else:
			st["failed"][src] = str(it["key"])
	st["log"].append({"s": int(season.get("no", 1)), "w": Rules.week_no(season),
		"text": "%s → %s" % [Rules.fill(season, str(ev.get("text", "")), it.get("ctx", {})).left(40), Rules.fill(season, str(c.get("label", "")), it.get("ctx", {}))]})

static func entry(id: String) -> Dictionary:
	for e in DB.TIMELINE:
		if str(e["id"]) == id:
			return e
	return {}

# ============================================================ generic events
static func _generic(season: Dictionary, rng: RandomNumberGenerator) -> void:
	var st := state(season)
	var w: Dictionary = season["world"]
	var now: int = int(season.get("no", 1)) * 100 + Rules.week_no(season)
	var key := when_tag(season)
	var budget: Dictionary = st["budget"].get(key, {"major": 0, "minor": 0})
	for t in w["teams"]:
		var ids: Array = t["players"]
		for g in DB.GENERIC:
			var subjects := []
			if str(g["who"]) == "pair":
				for i in ids.size():
					for j in range(i + 1, ids.size()):
						subjects.append({"$p": str(ids[i]), "$q": str(ids[j]), "$t": str(t["id"])})
			else:
				for pid in ids:
					subjects.append({"$p": str(pid), "$t": str(t["id"])})
			for ctx in subjects:
				var ck: String = "%s|%s" % [g["id"], ctx["$p"]]
				if int(st["cool"].get(ck, -999)) > now:
					continue
				if not Rules.all(season, g["if"], ctx) or rng.randf() >= float(g["p"]):
					continue
				var human: bool = bool(t.get("human", false))
				if human:
					var kind: String = str(DB.EVENTS[g["id"]].get("kind", "minor"))
					var cap: int = MAJOR_PER_WEEK if kind == "major" else MINOR_PER_WEEK
					if int(budget.get(kind, 0)) >= cap:
						continue
					budget[kind] = int(budget.get(kind, 0)) + 1
					st["uid"] = int(st["uid"]) + 1
					st["pending"].append({"uid": int(st["uid"]), "event": g["id"], "ctx": ctx, "src": "", "key": key})
				else:
					_news(season, Rules.apply(season, g.get("ai", []), ctx, rng))
				st["cool"][ck] = now + int(g.get("cool", 4))
	st["budget"] = {key: budget}

# ============================================================ notes and endings
## [{"id", "text", "clear", "status": "pending"|"uncertain"|"fulfilled"|"changed"}] of the notes the protagonist remembers
static func notes(season: Dictionary) -> Array:
	var st := state(season)
	var out := []
	for n in DB.NOTES:
		if not st["known"].has(n["id"]):
			continue
		out.append({"id": n["id"], "text": n["text"], "clear": bool(n.get("clear", true)), "status": note_status(season, n)})
	return out

static func note_status(season: Dictionary, n: Dictionary) -> String:
	var st := state(season)
	var id: String = str(n["bind"])
	if st["happened"].has(id):
		return "fulfilled"
	if st["failed"].has(id):
		return "changed"
	var e := entry(id)
	for c in e.get("if", []):
		if STRUCTURAL.has(str(c[0])) and not Rules.test(season, c):
			return "uncertain"
	return "pending"

static func endings(season: Dictionary) -> Dictionary:
	var out := {}
	for pid in DB.ENDINGS:
		for en in DB.ENDINGS[pid]:
			if Rules.all(season, en["if"]):
				out[pid] = str(en["text"])
				break
	return out

static func pending(season: Dictionary) -> Array:
	return state(season)["pending"]

## the text and choices of a pending item, names filled in
static func describe(season: Dictionary, it: Dictionary) -> Dictionary:
	var ev: Dictionary = DB.EVENTS.get(str(it["event"]), {})
	var labels := []
	for c in ev.get("choices", []):
		labels.append(Rules.fill(season, str(c["label"]), it.get("ctx", {})))
	return {"text": Rules.fill(season, str(ev.get("text", "")), it.get("ctx", {})), "choices": labels, "kind": str(ev.get("kind", "minor"))}

static func _news(season: Dictionary, lines: Array) -> void:
	var st := state(season)
	var Stories = load("res://game/league/stories.gd")
	for l in lines:
		if str(l) == "":
			continue
		Stories.add(season, str(l), "story")
		st["log"].append({"s": int(season.get("no", 1)), "w": Rules.week_no(season), "text": str(l)})
