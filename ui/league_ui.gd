extends Node
## Stage 2 — league screens: season hub (schedule, standings, teams, stats, news), BO3 series with map veto and
## hero draft, and the hand-off to real matches (play yourself / watch the AI / skip with the instant resolver).
## Logic lives in game/league/*.gd; this file only shows it and turns clicks into calls.
## Design: docs/design/赛事层设计.md

const C = preload("res://game/consts.gd")
const HeroesDB = preload("res://heroes_db.gd")
const Maps = preload("res://game/maps.gd")
const Profiles = preload("res://game/profiles.gd")
const Season = preload("res://game/league/season.gd")
const Series = preload("res://game/league/series.gd")
const Draft = preload("res://game/league/draft.gd")
const World = preload("res://game/league/world.gd")
const QuickSim = preload("res://game/league/quick_sim.gd")
const Bridge = preload("res://game/league/match_bridge.gd")
const Stories = preload("res://game/league/stories.gd")

const MatchT = preload("res://game/match.gd")
var gm: MatchT
const PresenterT = preload("res://view/presenter.gd")
var vw: PresenterT
const HudT = preload("res://ui/hud.gd")
var hd: HudT
const ShopUIT = preload("res://ui/shop_ui.gd")
var shp: ShopUIT
const MenusT = preload("res://ui/menus.gd")
var mnu: MenusT
var app: Node = null

const ROLE_COL := {"tank": "#6ab0ff", "carry": "#ff8a6a", "support": "#6aff9a"}

var season: Dictionary = {}
var view := "hub"          # hub | series
var tab := "schedule"      # schedule | table | teams | stats | news
var cur: Dictionary = {}   # the series on screen
var human_side := -1       # side of the human team in `cur` (-1: watching other teams)
var match_swap := false    # series sides flipped in the running match (human team is match team 0)
var in_match := false
var _step_timer: Timer

var root: Control
var title: Label
var status: Label
var tabs_box: HBoxContainer
var body: VBoxContainer
var scroll: ScrollContainer
var actions: HBoxContainer

# ============================================================ build
func build() -> void:
	root = PanelContainer.new()
	root.add_theme_stylebox_override("panel", hd._panel_style(Color(0.03, 0.02, 0.08, 0.94), Color(0.3, 0.8, 1.0, 0.5)))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	root.visible = false
	hd.ui_root.add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	root.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	title = hd._label(24, Color(1.0, 0.85, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 6)
	top.add_child(tabs_box)
	for t in [["schedule", "赛程"], ["table", "积分榜"], ["teams", "战队"], ["stats", "数据"], ["news", "新闻"]]:
		var b := shp._small_btn(t[1], 76)
		b.pressed.connect(_set_tab.bind(t[0]))
		tabs_box.add_child(b)
	var back := shp._small_btn("主菜单", 76)
	back.pressed.connect(_to_menu)
	top.add_child(back)
	status = hd._label(15, Color(0.75, 0.85, 1.0))
	v.add_child(status)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(actions)
	_step_timer = Timer.new()
	_step_timer.wait_time = 0.35
	_step_timer.one_shot = true
	_step_timer.timeout.connect(_ai_step)
	add_child(_step_timer)

# ============================================================ entry / exit
## main menu [3]: continue the running season or start a new one
func open() -> void:
	if season.is_empty():
		season = Season.create(int(Time.get_unix_time_from_system()) % 1000000)
	gm.state = C.S.SELECT
	gm._clear_world()
	_redraw_world()
	mnu.menu_root.visible = false
	hd.hud.visible = false
	hd.center_lbl.text = ""
	hd.sub_lbl.text = ""
	view = "hub"
	root.visible = true
	refresh()

## the arena drawing (floor, overlay) keeps the last frame until redrawn
func _redraw_world() -> void:
	vw.overlay.queue_redraw()
	vw.floor_layer.queue_redraw()

func hide() -> void:
	if root != null:
		root.visible = false

func _to_menu() -> void:
	hide()
	mnu._show_menu()

func new_season() -> void:
	season = Season.create(int(Time.get_unix_time_from_system()) % 1000000)
	view = "hub"
	tab = "news"
	refresh()

func _set_tab(t: String) -> void:
	tab = t
	view = "hub"
	refresh()

# ============================================================ helpers
func _clear(c: Node) -> void:
	for n in c.get_children():
		c.remove_child(n)
		n.queue_free()

func _rt(text: String, size := 15) -> RichTextLabel:
	var r := shp._rt(size)
	r.text = text
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

func _btn(text: String, cb: Callable, w := 120.0) -> Button:
	var b := shp._small_btn(text, w)
	b.custom_minimum_size.y = 34
	b.pressed.connect(cb)
	return b

func _tname(tid: String) -> String:
	return Stories.team_name(season, tid)

func _tcol(tid: String) -> String:
	if tid == str(season["human"]):
		return "#ffd23f"
	return "#c8d8ff"

func _team_bb(tid: String) -> String:
	return "[color=%s]%s[/color]" % [_tcol(tid), _tname(tid)]

func _hero_name(hid: String) -> String:
	return str(HeroesDB.HEROES[hid]["short"]) if HeroesDB.HEROES.has(hid) else hid

func _map_name(mid: String) -> String:
	return str(Maps.MAPS[mid]["name"]) if Maps.MAPS.has(mid) else mid

func _stage_label() -> String:
	match str(season["phase"]):
		"regular": return "常规赛 第 %d / %d 周" % [int(season["week"]) + 1, (season["weeks"] as Array).size()]
		"playoffs": return "季后赛 · %s" % ("半决赛" if (season["playoffs"] as Array).size() == 1 else "总决赛")
	return "赛季结束 · 冠军 %s" % _tname(str(season["champion"]))

# ============================================================ refresh
func refresh() -> void:
	if root == null or season.is_empty():
		return
	var me: Dictionary = World.team(season["world"], str(season["human"]))
	title.text = "%s · %s" % [str(me.get("name", "联赛")), _stage_label()]
	_clear(body)
	_clear(actions)
	if view == "series":
		_show_series()
		return
	match tab:
		"schedule": _show_schedule()
		"table": _show_table()
		"teams": _show_teams()
		"stats": _show_stats()
		"news": _show_news()
	_hub_actions()

func _hub_actions() -> void:
	if str(season["phase"]) == "done":
		status.text = "赛季已经结束。可以查看新闻里的赛季奖项，或者开始新赛季（重新生成选手和战队）。"
		actions.add_child(_btn("开始新赛季", new_season, 160))
		return
	var hs: Dictionary = Season.human_series(season)
	if not hs.is_empty() and not Series.done(hs):
		var opp: String = str(hs["b"]) if str(hs["a"]) == str(season["human"]) else str(hs["a"])
		status.text = "本轮你的对手：%s（BO3）。其他比赛可以逐场观战，也可以直接出结果。" % _tname(opp)
		actions.add_child(_btn("进入我的系列赛", _open_series.bind(hs), 170))
	elif Season.stage_done(season):
		status.text = "本轮所有比赛已经结束。"
	elif not hs.is_empty():
		var won: bool = str(hs["winner"]) == str(season["human"])
		status.text = "我方本轮比赛已结束（%s %d:%d）。其他比赛可以逐场观战，也可以直接出结果。" % [
			"胜" if won else "负", maxi(int(hs["score"][0]), int(hs["score"][1])) if won else mini(int(hs["score"][0]), int(hs["score"][1])),
			mini(int(hs["score"][0]), int(hs["score"][1])) if won else maxi(int(hs["score"][0]), int(hs["score"][1]))]
	else:
		status.text = "我方本轮没有比赛（已被淘汰）。可以观战其他比赛，或者直接出结果。"
	if not Season.stage_done(season):
		actions.add_child(_btn("其他比赛直接出结果", _skip_others, 190))
	else:
		actions.add_child(_btn("进入下一轮", _advance, 150))
	actions.add_child(_btn("模拟到赛季结束", _sim_to_end, 170))

# ------------------------------------------------------------ hub tabs
func _series_line(s: Dictionary) -> String:
	var sc := ""
	if Series.done(s) or (s["maps"] as Array).size() > 0:
		sc = "  [b]%d : %d[/b]" % [int(s["score"][0]), int(s["score"][1])]
	var kind: String = str({"regular": "", "semi": "半决赛  ", "final": "总决赛  "}[str(s["kind"])])
	return "%s%s  vs  %s%s" % [kind, _team_bb(str(s["a"])), _team_bb(str(s["b"])), sc]

func _show_schedule() -> void:
	var cur_list: Array = Season.current_series(season)
	body.add_child(_rt("[b]%s[/b]" % _stage_label(), 17))
	for s in cur_list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := _rt(_series_line(s), 16)
		l.custom_minimum_size.x = 520
		l.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(l)
		if not Series.done(s):
			var mine: bool = str(s["a"]) == str(season["human"]) or str(s["b"]) == str(season["human"])
			if mine:
				row.add_child(_btn("进入", _open_series.bind(s), 90))
			else:
				row.add_child(_btn("观战", _open_series.bind(s), 90))
				row.add_child(_btn("直接出结果", _skip_one.bind(s), 120))
		else:
			row.add_child(_btn("详情", _open_series.bind(s), 90))
		body.add_child(row)
	# finished weeks (most recent first)
	var txt := "\n[b]已完成的比赛[/b]\n"
	var done: Array = season["done"].duplicate()
	done.reverse()
	if done.is_empty():
		txt += "[color=#8a92b8]暂无[/color]\n"
	for s in done.slice(0, 24):
		var wk := "第 %d 周" % (int(s["week"]) + 1) if str(s["kind"]) == "regular" else "季后赛"
		txt += "[color=#8a92b8]%s[/color]   %s\n" % [wk, _series_line(s)]
	body.add_child(_rt(txt, 14))
	# the rest of the regular season
	if str(season["phase"]) == "regular":
		var t2 := "\n[b]后续赛程（我方）[/b]\n"
		for w in range(int(season["week"]) + 1, (season["weeks"] as Array).size()):
			for s in season["weeks"][w]:
				if str(s["a"]) == str(season["human"]) or str(s["b"]) == str(season["human"]):
					t2 += "第 %d 周   %s\n" % [w + 1, _series_line(s)]
		body.add_child(_rt(t2, 14))

func _show_table() -> void:
	var txt := "[b]积分榜[/b]（系列赛胜负 → 小分差；前四名进入季后赛）\n[table=6]"
	for h in ["排名", "战队", "胜-负", "小分", "近况", "档次"]:
		txt += "[cell][color=#8a92b8]%s[/color]   [/cell]" % h
	var i := 1
	for r in Season.standings(season):
		var form := ""
		for w in (r["form"] as Array).slice(maxi(0, (r["form"] as Array).size() - 5)):
			form += "[color=#6aff8a]胜[/color]" if w else "[color=#ff6a6a]负[/color]"
		var t: Dictionary = World.team(season["world"], str(r["id"]))
		txt += "[cell]%d%s   [/cell][cell]%s   [/cell][cell]%d-%d   [/cell][cell]%d-%d   [/cell][cell]%s   [/cell][cell]%s[/cell]" % [
			i, (" ★" if i <= 4 else ""), _team_bb(str(r["id"])), r["w"], r["l"], r["mw"], r["ml"], form, World.TIER_NAMES[int(t["tier"])]]
		i += 1
	txt += "[/table]"
	body.add_child(_rt(txt, 16))

func _show_teams() -> void:
	for t in season["world"]["teams"]:
		var txt := "[b]%s[/b]  [color=#8a92b8]%s · 平均能力 %.1f[/color]\n" % [_team_bb(str(t["id"])), World.TIER_NAMES[int(t["tier"])], Stories.team_rating(season, str(t["id"]))]
		for pid in t["players"]:
			var p: Dictionary = season["world"]["players"][pid]
			var pool := []
			var heroes: Array = (p["prof"] as Dictionary).keys()
			heroes.sort_custom(func(x, y): return float(p["prof"][x]) > float(p["prof"][y]))
			for hid in heroes.slice(0, 4):
				var star := "★" if (p["sig"] as Dictionary).has(hid) else ""
				pool.append("%s%s %s" % [star, _hero_name(hid), Profiles.stage(p, hid)[1]])
			var attrs := []
			for k in Profiles.ATTRS:
				attrs.append("%s %d" % [Profiles.ATTR_NAMES[k], int(p["attrs"][k])])
			var traits := []
			for tr in p.get("traits", []):
				traits.append(World.TRAITS.get(tr, tr))
			txt += "  [color=%s]%s[/color] [b]%s[/b] %d 岁  能力 %.1f   [color=#8a92b8]%s[/color]\n      英雄池：%s%s\n" % [
				ROLE_COL[p["role"]], HeroesDB.ROLE_NAMES[p["role"]], p["name"], int(p["age"]), World.rating(p), "  ".join(PackedStringArray(attrs)),
				"、".join(PackedStringArray(pool)), ("    特质：" + "、".join(PackedStringArray(traits))) if not traits.is_empty() else ""]
		body.add_child(_rt(txt, 14))

func _show_stats() -> void:
	var txt := "[b]选手数据[/b]（按影响力排序：和同职业选手平均水平相比）\n[table=9]"
	for h in ["选手", "职业", "战队", "图数", "击倒/阵亡/助攻", "KDA", "场均伤害", "场均治疗", "MVP"]:
		txt += "[cell][color=#8a92b8]%s[/color]   [/cell]" % h
	for r in Stories.leaderboard(season).slice(0, 16):
		var n := maxf(1.0, float(r["maps"]))
		txt += "[cell]%s   [/cell][cell][color=%s]%s[/color]   [/cell][cell]%s   [/cell][cell]%d   [/cell][cell]%d/%d/%d   [/cell][cell]%.1f   [/cell][cell]%d   [/cell][cell]%d   [/cell][cell]%d[/cell]" % [
			r["name"], ROLE_COL[r["role"]], HeroesDB.ROLE_NAMES[r["role"]], r["team"], r["maps"], r["k"], r["d"], r["a"], r["kda"], int(float(r["dmg"]) / n), int(float(r["heal"]) / n), r["mvp"]]
	txt += "[/table]\n\n[b]英雄数据[/b]\n[table=5]"
	for h in ["英雄", "出场", "胜率", "被禁", "职业"]:
		txt += "[cell][color=#8a92b8]%s[/color]   [/cell]" % h
	var ids: Array = (season["hstats"] as Dictionary).keys()
	ids.sort_custom(func(x, y): return int(season["hstats"][x]["picks"]) + int(season["hstats"][x]["bans"]) > int(season["hstats"][y]["picks"]) + int(season["hstats"][y]["bans"]))
	for hid in ids:
		var hs: Dictionary = season["hstats"][hid]
		txt += "[cell]%s   [/cell][cell]%d   [/cell][cell]%d%%   [/cell][cell]%d   [/cell][cell]%s[/cell]" % [
			HeroesDB.HEROES[hid]["name"], hs["picks"], int(100.0 * float(hs["wins"]) / maxf(1.0, float(hs["picks"]))), hs["bans"], HeroesDB.ROLE_NAMES[HeroesDB.HEROES[hid]["role"]]]
	txt += "[/table]"
	body.add_child(_rt(txt, 14))

func _show_news() -> void:
	var txt := ""
	var items: Array = season["news"].duplicate()
	items.reverse()
	var col := {"upset": "#ff9a6a", "sweep": "#c8d8ff", "comeback": "#ffd23f", "streak": "#b8a0ff", "star": "#6aff9a",
		"stage": "#8ad8ff", "award": "#ffd23f", "intro": "#c8d8ff"}
	var n_weeks: int = (season["weeks"] as Array).size()
	for n in items:
		var wk: String = ("第 %d 周" % (int(n["week"]) + 1)) if int(n["week"]) < n_weeks else "季后赛"
		txt += "[color=#8a92b8]%s[/color]  [color=%s]%s[/color]\n" % [wk, col.get(n["kind"], "#ffffff"), n["text"]]
	body.add_child(_rt(txt, 15))

# ------------------------------------------------------------ hub actions
func _skip_one(s: Dictionary) -> void:
	var rng := Season.rng_of(season)
	Series.quick_play(s, season, rng)
	Season.save_rng(season, rng)
	Season.finish_series(season, s)
	refresh()

func _skip_others() -> void:
	Season.quick_rest(season, true)
	refresh()

func _advance() -> void:
	Season.advance(season)
	tab = "schedule"
	refresh()

func _sim_to_end() -> void:
	Season.quick_to_end(season)
	tab = "news"
	refresh()

# ============================================================ series screen
func _open_series(s: Dictionary) -> void:
	cur = s
	human_side = -1
	if str(s["a"]) == str(season["human"]):
		human_side = 0
	elif str(s["b"]) == str(season["human"]):
		human_side = 1
	view = "series"
	refresh()
	_kick_ai()

## the AI makes its next veto / draft step after a short pause, so the draft can be followed
func _kick_ai() -> void:
	if Series.done(cur) or in_match:
		return
	var v: Dictionary = cur["veto"]
	if Draft.veto_action(v) != "done":
		if Draft.veto_side(v) != human_side:
			_step_timer.start()
		return
	if (cur["draft"] as Dictionary).is_empty():
		return
	if not Draft.done(cur["draft"]) and int(Draft.current(cur["draft"])[1]) != human_side:
		_step_timer.start()

func _ai_step() -> void:
	if view != "series" or cur.is_empty():
		return
	var rng := Season.rng_of(season)
	var v: Dictionary = cur["veto"]
	if Draft.veto_action(v) != "done":
		var side: int = Draft.veto_side(v)
		Draft.veto_apply(v, Draft.veto_ai(v, side, Series.map_record(season, Series.tid(cur, side)), rng))
	elif not (cur["draft"] as Dictionary).is_empty() and not Draft.done(cur["draft"]):
		var d: Dictionary = cur["draft"]
		var side2: int = int(Draft.current(d)[1])
		var roles := [Draft.by_role(season["world"], Series.tid(cur, 0)), Draft.by_role(season["world"], Series.tid(cur, 1))]
		Draft.apply(d, Draft.ai_choice(d, side2, roles[side2], roles[1 - side2], rng, Draft.noise_for(World.team(season["world"], Series.tid(cur, side2)))))
	Season.save_rng(season, rng)
	refresh()
	_kick_ai()

func _human_veto(m: String) -> void:
	Draft.veto_apply(cur["veto"], m)
	refresh()
	_kick_ai()

func _human_draft(hid: String) -> void:
	Draft.apply(cur["draft"], hid)
	refresh()
	_kick_ai()

func _start_map_draft() -> void:
	Series.start_draft(cur)
	refresh()
	_kick_ai()

func _show_series() -> void:
	var w: Dictionary = season["world"]
	var head := "[b]%s  %d : %d  %s[/b]   [color=#8a92b8]BO3 · %s[/color]" % [_team_bb(str(cur["a"])), int(cur["score"][0]), int(cur["score"][1]),
		_team_bb(str(cur["b"])), {"regular": "常规赛", "semi": "半决赛", "final": "总决赛"}[str(cur["kind"])]]
	body.add_child(_rt(head, 20))
	# finished maps
	var i := 1
	for m in cur["maps"]:
		var mvp: String = Stories.player_name(season, str(m["mvp"]))
		var picks := ["", ""]
		for side in 2:
			var names := []
			for hid in m["picks"][side]:
				names.append(_hero_name(hid))
			picks[side] = "、".join(PackedStringArray(names))
		body.add_child(_rt("第 %d 图 %s   %s [b]%d:%d[/b] %s   （%s 对 %s）  MVP %s  [color=#8a92b8]%s[/color]" % [i, _map_name(str(m["map"])),
			_team_bb(str(cur["a"])), m["score"][0], m["score"][1], _team_bb(str(cur["b"])), picks[0], picks[1], mvp,
			"实机" if str(m.get("mode", "")) == "full" else "直接出结果"], 14))
		i += 1
	if Series.done(cur):
		status.text = "系列赛结束：%s 获胜。" % _tname(str(cur["winner"]))
		actions.add_child(_btn("返回赛程", _back_to_hub, 150))
		return
	# map veto
	var v: Dictionary = cur["veto"]
	var vt := "[b]地图[/b]  "
	var vm := []
	for k in (v["maps"] as Array).size():
		vm.append("第 %d 图 %s" % [k + 1, _map_name(str(v["maps"][k]))])
	vt += "   ".join(PackedStringArray(vm))
	if not (v["bans"] as Array).is_empty():
		vt += "   [color=#8a92b8]（禁用 %s）[/color]" % _map_name(str(v["bans"][0]))
	body.add_child(_rt(vt, 15))
	if Draft.veto_action(v) != "done":
		var vside: int = Draft.veto_side(v)
		var verb: String = "选择" if Draft.veto_action(v) == "pick" else "禁用"
		if vside == human_side:
			status.text = "轮到你%s地图（%s）。" % [verb, ["第 1 图", "第 2 图", "一张，剩下的一张作为决胜图"][int(v["step"])]]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			for m in Draft.veto_left(v):
				row.add_child(_btn("%s %s" % [verb, _map_name(m)], _human_veto.bind(m), 170))
			body.add_child(row)
			for m in Draft.veto_left(v):
				var rec: Array = Series.map_record(season, str(season["human"])).get(m, [0, 0])
				body.add_child(_rt("  [color=#8a92b8]%s：%s  我方本赛季 %d 胜 %d 负[/color]" % [_map_name(m), Maps.MAPS[m]["desc"], rec[0], rec[1]], 13))
		else:
			status.text = "%s 正在%s地图……" % [_tname(Series.tid(cur, vside)), verb]
		return
	# hero draft of the next map
	var d: Dictionary = cur["draft"]
	if d.is_empty():
		status.text = "第 %d 图：%s。准备禁选英雄。" % [(cur["maps"] as Array).size() + 1, _map_name(Series.next_map(cur))]
		actions.add_child(_btn("开始禁选", _start_map_draft, 150))
		if human_side < 0:
			actions.add_child(_btn("整个系列赛直接出结果", _skip_series, 200))
		actions.add_child(_btn("返回赛程", _back_to_hub, 120))
		return
	_show_draft(d, w)

func _show_draft(d: Dictionary, w: Dictionary) -> void:
	var map_no: int = (cur["maps"] as Array).size() + 1
	var roles := [Draft.by_role(w, Series.tid(cur, 0)), Draft.by_role(w, Series.tid(cur, 1))]
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	body.add_child(cols)
	for side in 2:
		var txt := "%s%s\n" % [_team_bb(Series.tid(cur, side)), "  [color=#8a92b8]（先手）[/color]" if int(d.get("first", 0)) == side else ""]
		var bans := []
		for hid in d["bans"][side]:
			bans.append(_hero_name(hid))
		txt += "禁用：%s\n" % ("、".join(PackedStringArray(bans)) if not bans.is_empty() else "—")
		for role in Series.ROLE_ORDER:
			var p: Dictionary = roles[side][role]
			var hid: String = str(d["picks"][side].get(role, ""))
			var pick: String = "[b]%s[/b] %s" % [_hero_name(hid), Profiles.stage(p, hid)[1]] if hid != "" else "[color=#8a92b8]…[/color]"
			var sig := []
			for sh in p["sig"]:
				sig.append(_hero_name(sh))
			txt += "[color=%s]%s[/color] %s：%s   [color=#8a92b8]招牌 %s[/color]\n" % [ROLE_COL[role], HeroesDB.ROLE_NAMES[role], p["name"], pick, "、".join(PackedStringArray(sig))]
		var r := _rt(txt, 15)
		r.custom_minimum_size.x = 580
		cols.add_child(r)
	if Draft.done(d):
		status.text = "第 %d 图 %s：禁选完成。" % [map_no, _map_name(Series.next_map(cur))]
		if human_side >= 0:
			actions.add_child(_btn("亲自上场（操控 %s）" % _hero_name(str(d["picks"][human_side]["carry"])), _play_map.bind(true), 230))
			actions.add_child(_btn("观战（AI 代打）", _play_map.bind(false), 170))
		else:
			actions.add_child(_btn("观战本图", _play_map.bind(false), 140))
		actions.add_child(_btn("跳过（直接出结果）", _quick_map, 190))
		if human_side < 0:
			actions.add_child(_btn("返回赛程", _back_to_hub, 120))
		return
	var cur_step: Array = Draft.current(d)
	var action: String = str(cur_step[0])
	var side3: int = int(cur_step[1])
	var verb: String = "禁用" if action == "ban" else "选择"
	if side3 != human_side:
		status.text = "第 %d 图 %s：%s 正在%s英雄……" % [map_no, _map_name(Series.next_map(cur)), _tname(Series.tid(cur, side3)), verb]
		return
	status.text = "第 %d 图 %s：轮到你%s英雄。%s" % [map_no, _map_name(Series.next_map(cur)), verb,
		"每个职业选 1 个，由对应职业的选手使用。" if action == "pick" else "禁掉对手最擅长的英雄。"]
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	var ok := Draft.available(d, side3, action)
	var mine: Dictionary = roles[side3]
	var theirs: Dictionary = roles[1 - side3]
	for hid in HeroesDB.ORDER:
		var role: String = str(HeroesDB.HEROES[hid]["role"])
		var who: Dictionary = mine[role] if action == "pick" else theirs[role]
		var note := "%s %s" % [who["name"], Profiles.stage(who, hid)[1]]
		if (who["sig"] as Dictionary).has(hid):
			note = "★" + note
		var b := shp._small_btn("%s · %s\n%s" % [_hero_name(hid), HeroesDB.ROLE_NAMES[role], note], 190)
		b.custom_minimum_size.y = 52
		var tex_key: String = str(HeroesDB.HEROES[hid]["sprite"]) + "_0"
		if gm.TEX.has(tex_key):
			b.icon = gm.TEX[tex_key]
			b.expand_icon = false
		if d["taken"].has(hid):
			b.disabled = true
			b.modulate = Color(0.45, 0.45, 0.5)
		elif not ok.has(hid):
			b.disabled = true
			b.modulate = Color(0.65, 0.65, 0.7)
		else:
			b.pressed.connect(_human_draft.bind(hid))
		grid.add_child(b)

func _back_to_hub() -> void:
	view = "hub"
	tab = "schedule"
	refresh()

func _skip_series() -> void:
	var rng := Season.rng_of(season)
	Series.quick_play(cur, season, rng)
	Season.save_rng(season, rng)
	Season.finish_series(season, cur)
	refresh()

## instant result of the drafted map
func _quick_map() -> void:
	var rng := Season.rng_of(season)
	var lu := Series.lineups(cur, season["world"])
	var res: Dictionary = QuickSim.play_map(lu[0], lu[1], Series.next_map(cur), rng)
	res["winner_tid"] = Series.tid(cur, int(res["winner"]))
	Season.save_rng(season, rng)
	_record(res)

func _record(res: Dictionary) -> void:
	Series.record_map(cur, res)
	if Series.done(cur):
		Season.finish_series(season, cur)
	refresh()
	_kick_ai()

# ============================================================ real matches
func _play_map(human_plays: bool) -> void:
	var args: Dictionary = Bridge.match_args(cur, season["world"], str(season["human"]) if human_side >= 0 else "", human_plays)
	match_swap = bool(args["swap"])
	args["setup"]["league"] = true
	args["setup"]["league_watch"] = not human_plays
	in_match = true
	root.visible = false
	var rng := Season.rng_of(season)
	var mseed: int = rng.randi() % 1000000
	Season.save_rng(season, rng)
	hd.center_lbl.text = ""
	hd.sub_lbl.text = ""
	gm._start_rounds(args["a"], args["b"], 1, mseed, args["setup"])

## called by the input module when the finished match screen is closed (or a league match is abandoned)
func on_match_done(abandon := false) -> void:
	if not in_match:
		return
	in_match = false
	var res: Dictionary
	if abandon or gm.state != C.S.END:
		# leaving early: the rest of the map is decided by the instant resolver
		var rng := Season.rng_of(season)
		var lu := Series.lineups(cur, season["world"])
		res = QuickSim.play_map(lu[0], lu[1], Series.next_map(cur), rng)
		res["winner_tid"] = Series.tid(cur, int(res["winner"]))
		Season.save_rng(season, rng)
	else:
		res = Bridge.result_from(gm, cur, match_swap)
	gm.state = C.S.SELECT
	gm._clear_world()
	_redraw_world()
	hd.hud.visible = false
	hd.center_lbl.text = ""
	hd.sub_lbl.text = ""
	shp._close_shop()
	root.visible = true
	_record(res)

func active() -> bool:
	return in_match
