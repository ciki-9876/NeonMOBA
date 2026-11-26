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
const Training = preload("res://game/league/training.gd")
const Save = preload("res://game/save.gd")
const Story = preload("res://game/story/story.gd")
const People = preload("res://game/league/people.gd")
const Cast = preload("res://game/league/cast_db.gd")

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
var view := "hub"          # hub | series | pick (4th player of a new career)
var pick_seed := 0
var pick_world: Dictionary = {}
var my_lineup: Dictionary = {}   # the human lineup being edited before a map ({role: pid})
var tab := "schedule"      # schedule | training | inbox | notes | table | teams | stats | news
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
	for t in [["schedule", "赛程"], ["training", "训练"], ["inbox", "消息"], ["notes", "笔记"], ["table", "积分榜"], ["teams", "战队"], ["stats", "数据"], ["news", "新闻"]]:
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
		season = Save.load_season()          # the autosave of the last session, if there is one
	gm.state = C.S.SELECT
	gm._clear_world()
	_redraw_world()
	mnu.menu_root.visible = false
	hd.hud.visible = false
	hd.center_lbl.text = ""
	hd.sub_lbl.text = ""
	root.visible = true
	if season.is_empty():
		_begin_pick()
		return
	Training.ensure(season)
	view = "hub"
	refresh()

## a new career: first the 4th player of 星火 (the remembered names or a walk-on)
func _begin_pick() -> void:
	pick_seed = int(Time.get_unix_time_from_system()) % 1000000
	pick_world = World.build_fixed(pick_seed)
	season = {}
	view = "pick"
	refresh_pick()

func refresh_pick() -> void:
	_clear(body)
	_clear(actions)
	title.text = "新生涯 · 星火网咖"
	status.text = "城市赛冠军到手，次级联赛就要开始了。队里还缺一个人：前世记得的几个名字，现在还没人注意到他们。"
	body.add_child(_rt("[b]选择第四名队员[/b]（替补，每张图 4 选 3 登场，可以在购买阶段换人）", 18))
	for pid in World.pick_options(pick_world):
		var p: Dictionary = pick_world["players"][pid]
		var known: bool = Cast.CANDIDATES.has(pid)
		var attrs := []
		for k in Profiles.ATTRS:
			attrs.append("%s %d" % [Profiles.ATTR_NAMES[k], int(p["attrs"][k])])
		var heroes: Array = (p["prof"] as Dictionary).keys()
		heroes.sort_custom(func(x, y): return float(p["prof"][x]) > float(p["prof"][y]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := _rt("[color=%s]%s[/color] [b]%s[/b]  %s · %d 岁 · %s   能力 %.1f\n[color=#8a92b8]%s[/color]\n英雄：%s\n%s" % [
			ROLE_COL[p["role"]], HeroesDB.ROLE_NAMES[p["role"]], p["name"], "女" if str(p["gender"]) == "f" else "男", int(p["age"]),
			Cast.NATION_NAMES.get(p["nation"], p["nation"]), World.rating(p), "  ".join(PackedStringArray(attrs)),
			"、".join(PackedStringArray(heroes.slice(0, 3).map(func(h): return _hero_name(h)))),
			("[color=#ffd23f]前世记忆：%s[/color]" % str(p.get("tagline", ""))) if known else "[color=#8a92b8]路人：不在记忆里的面孔[/color]"], 14)
		l.custom_minimum_size = Vector2(760, 86)
		row.add_child(l)
		row.add_child(_btn("选择", _choose_pick.bind(pid), 100))
		body.add_child(row)
	actions.add_child(_btn("返回主菜单", _to_menu, 150))

func _choose_pick(pid: String) -> void:
	season = Season.create(pick_seed, {"pick": pid})
	pick_world = {}
	view = "hub"
	tab = "notes"
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
	confirm_new = false
	_begin_pick()

func _next_season() -> void:
	season = Season.next_season(season)
	view = "hub"
	tab = "news"
	refresh()

var confirm_new := false   # "放弃并重开" needs a second click within 4 seconds
var save_ok := true

func _autosave() -> void:
	save_ok = Save.save_season(season)

func _confirm_new() -> void:
	if confirm_new:
		new_season()
		return
	confirm_new = true
	refresh()
	get_tree().create_timer(4.0).timeout.connect(func():
		if confirm_new:
			confirm_new = false
			if root != null and root.visible and view == "hub":
				refresh())

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
	var lg: String = World.LEAGUE_NAMES.get(Season.human_league(season), "")
	var pre := "S%d %s · " % [int(season.get("no", 1)), lg]
	match str(season["phase"]):
		"regular": return pre + "常规赛 第 %d / %d 周" % [int(season["week"]) + 1, Season.n_weeks(season)]
		"playoffs": return pre + "季后赛 · %s" % ("半决赛" if (season["leagues"]["pro"]["playoffs"] as Array).size() == 1 else "总决赛")
		"promo": return pre + "升降级附加赛"
	return pre + "赛季结束"

# ============================================================ refresh
func refresh() -> void:
	if root == null:
		return
	if view == "pick":
		refresh_pick()
		return
	if season.is_empty():
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
		"training": _show_training()
		"inbox": _show_inbox()
		"notes": _show_notes()
		"table": _show_table()
		"teams": _show_teams()
		"stats": _show_stats()
		"news": _show_news()
	_hub_actions()

func _hub_actions() -> void:
	_autosave()
	title.text += "  · 已自动存档" if save_ok else "  · 存档失败"
	actions.add_child(_btn("确认放弃？再点一次" if confirm_new else "放弃生涯并重开", _confirm_new, 190))
	if str(season["phase"]) == "done":
		var up: bool = (season["moves"]["up"] as Array).has(str(season["human"]))
		var down: bool = (season["moves"]["down"] as Array).has(str(season["human"]))
		status.text = "S%d 结束。%s 查看新闻里的赛季奖项，然后进入下一赛季（选手会成长、老将会退役）。" % [int(season["no"]),
			"我们升入了职业联赛！" if up else ("我们降入了次级联赛……" if down else "")]
		actions.add_child(_btn("进入下一赛季", _next_season, 170))
		return
	var pend: int = Story.pending(season).size()
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
	if pend > 0:
		status.text = "有 %d 条消息等你处理。  " % pend + status.text
		actions.add_child(_btn("处理消息（%d）" % pend, _set_tab.bind("inbox"), 150))
	if not Season.stage_done(season):
		actions.add_child(_btn("其他比赛直接出结果", _skip_others, 190))
	elif pend == 0:
		actions.add_child(_btn("进入下一轮", _advance, 150))
	actions.add_child(_btn("模拟到赛季结束", _sim_to_end, 170))

# ------------------------------------------------------------ hub tabs
func _series_line(s: Dictionary) -> String:
	var sc := ""
	if Series.done(s) or (s["maps"] as Array).size() > 0:
		sc = "  [b]%d : %d[/b]" % [int(s["score"][0]), int(s["score"][1])]
	var kind: String = str({"regular": "", "semi": "半决赛  ", "final": "总决赛  ", "promo": "升降级附加赛  "}[str(s["kind"])])
	return "%s%s  vs  %s%s" % [kind, _team_bb(str(s["a"])), _team_bb(str(s["b"])), sc]

func _show_schedule() -> void:
	var cur_list: Array = Season.current_series(season)
	body.add_child(_rt("[b]%s[/b]" % _stage_label(), 17))
	var last_lg := ""
	for s in cur_list:
		if str(s.get("league", "")) != last_lg:
			last_lg = str(s.get("league", ""))
			body.add_child(_rt("[color=#8ad8ff]%s[/color]" % World.LEAGUE_NAMES.get(last_lg, "升降级附加赛"), 15))
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
		txt += "[color=#8a92b8]%s %s[/color]   %s\n" % [World.LEAGUE_NAMES.get(str(s.get("league", "")), "附加赛").left(2), wk, _series_line(s)]
	body.add_child(_rt(txt, 14))
	# the rest of the regular season
	if str(season["phase"]) == "regular":
		var t2 := "\n[b]后续赛程（我方）[/b]\n"
		var my_weeks: Array = season["leagues"][Season.human_league(season)]["weeks"]
		for w in range(int(season["week"]) + 1, my_weeks.size()):
			for s in my_weeks[w]:
				if str(s["a"]) == str(season["human"]) or str(s["b"]) == str(season["human"]):
					t2 += "第 %d 周   %s\n" % [w + 1, _series_line(s)]
		body.add_child(_rt(t2, 14))

func _show_training() -> void:
	var team: Dictionary = World.team(season["world"], str(season["human"]))
	var tr: Dictionary = Training.ensure(season)
	var locked: bool = Training.committed(season)
	body.add_child(_rt("[b]训练安排[/b]   [color=#8a92b8]%s[/color]" % _stage_label(), 17))
	body.add_child(_rt("[color=#8a92b8]每名选手每周一项：练一项能力、练一个英雄的熟练度，或者休息。训练在你进入本周比赛时结算。\n疲劳超过 40 训练效率下降；达到 70 比赛时能力 -1，达到 90 能力 -2；休息可以恢复 35。擅长英雄（★）的熟练度成长 ×2，年轻选手成长更快。[/color]", 13))
	if locked:
		body.add_child(_rt("[color=#ffd23f]本周训练已经结算。进入下一轮后可以重新安排。[/color]", 14))
	for pid in team["players"]:
		var p: Dictionary = season["world"]["players"][pid]
		var f: float = float(p.get("fatigue", 0.0))
		var fcol := "#6aff8a" if f < 40.0 else ("#ffd23f" if f < 70.0 else "#ff6a6a")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var attrs := []
		for k in Profiles.ATTRS:
			attrs.append("%s %d" % [Profiles.ATTR_NAMES[k], int(p["attrs"][k])])
		var l := _rt("[color=%s]%s[/color] [b]%s[/b] %d 岁   能力 %.1f   疲劳 [color=%s]%d[/color]\n[color=#8a92b8]%s[/color]" % [
			ROLE_COL[p["role"]], HeroesDB.ROLE_NAMES[p["role"]], p["name"], int(p["age"]), World.rating(p), fcol, int(f), "  ".join(PackedStringArray(attrs))], 14)
		l.custom_minimum_size = Vector2(560, 46)
		l.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(280, 34)
		ob.add_item("自动安排")
		ob.set_item_metadata(0, "")
		var cur_plan: String = Training.plan_of(season, pid)
		var sel := 0
		var opts: Array = Training.options(p)
		for i in opts.size():
			ob.add_item(str(opts[i][1]))
			ob.set_item_metadata(i + 1, str(opts[i][0]))
			if str(opts[i][0]) == cur_plan:
				sel = i + 1
		ob.select(sel)
		ob.disabled = locked
		ob.item_selected.connect(func(idx: int): Training.set_plan(season, str(pid), str(ob.get_item_metadata(idx))))
		row.add_child(ob)
		body.add_child(row)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	var b1 := _btn("全部自动安排", _plan_all.bind("auto"), 150)
	var b2 := _btn("全员休息", _plan_all.bind("rest"), 120)
	b1.disabled = locked
	b2.disabled = locked
	brow.add_child(b1)
	brow.add_child(b2)
	body.add_child(brow)
	var log: Array = tr.get("log", [])
	if not log.is_empty():
		var key: int = int(tr.get("log_key", -1))
		var when := "第 %d 周" % (key % 1000 + 1) if key % 1000 < 100 else "季后赛"
		var txt := "\n[b]上次训练结果[/b]  [color=#8a92b8]%s[/color]\n" % when
		for e in log:
			var p2: Dictionary = season["world"]["players"][str(e["pid"])]
			txt += "  [b]%s[/b]  %s   %s\n" % [p2["name"], Training.plan_text(str(e["plan"])), str(e["text"])]
		body.add_child(_rt(txt, 14))

func _plan_all(kind: String) -> void:
	var team: Dictionary = World.team(season["world"], str(season["human"]))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for pid in team["players"]:
		Training.set_plan(season, str(pid), "rest" if kind == "rest" else "")
	refresh()

func _show_table() -> void:
	for lg in Season.LEAGUES:
		var txt := "[b]%s积分榜[/b]（系列赛胜负 → 小分差；前四名进入季后赛；%s）\n[table=6]" % [World.LEAGUE_NAMES[lg],
			"第 8 名降级、第 7 名打升降级附加赛" if lg == "pro" else "冠军升级、亚军打升降级附加赛"]
		for h in ["排名", "战队", "胜-负", "小分", "近况", "平均能力"]:
			txt += "[cell][color=#8a92b8]%s[/color]   [/cell]" % h
		var i := 1
		for r in Season.standings(season, lg):
			var form := ""
			for w in (r["form"] as Array).slice(maxi(0, (r["form"] as Array).size() - 5)):
				form += "[color=#6aff8a]胜[/color]" if w else "[color=#ff6a6a]负[/color]"
			txt += "[cell]%d%s   [/cell][cell]%s   [/cell][cell]%d-%d   [/cell][cell]%d-%d   [/cell][cell]%s   [/cell][cell]%.1f[/cell]" % [
				i, (" ★" if i <= 4 else ""), _team_bb(str(r["id"])), r["w"], r["l"], r["mw"], r["ml"], form, Stories.team_rating(season, str(r["id"]))]
			i += 1
		txt += "[/table]\n"
		body.add_child(_rt(txt, 15))
	var hist: Array = season.get("history", [])
	if not hist.is_empty():
		var t2 := "[b]历届冠军[/b]\n"
		for h in hist:
			t2 += "S%d  职业联赛 %s   次级联赛 %s\n" % [int(h["no"]), _team_bb(str(h["champions"]["pro"])), _team_bb(str(h["champions"]["sec"]))]
		body.add_child(_rt(t2, 14))

func _show_teams() -> void:
	var order: Array = [str(season["human"])]
	for lg in [Season.human_league(season), "pro", "sec"]:
		for tid in season["leagues"][lg]["teams"]:
			if not order.has(str(tid)):
				order.append(str(tid))
	for tid in order:
		var t := World.team(season["world"], tid)
		var coach: String = str(t.get("coach", ""))
		var txt := "[b]%s[/b]  [color=#8a92b8]%s · 平均能力 %.1f%s[/color]\n" % [_team_bb(tid), World.LEAGUE_NAMES.get(str(t["league"]), ""),
			Stories.team_rating(season, tid), ("  · 主教练 " + World.display_name(season["world"], coach)) if coach != "" else ""]
		var mine: bool = tid == str(season["human"])
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
			var langs := []
			for l in p.get("langs", {}):
				langs.append("%s %d" % [Cast.LANG_NAMES.get(l, l), int(p["langs"][l])])
			var extra := ""
			if mine:
				extra = "      心情 %s   状态 %s   疲劳 %d   来队 %d 周\n" % [_mood(float(p.get("sat", 70.0))), _form_txt(float(p.get("form", 0.0))), int(p.get("fatigue", 0.0)), int(p.get("wt", 0))]
			txt += "  [color=%s]%s[/color] [b]%s[/b]%s %s %d 岁 %s  能力 %.1f   [color=#8a92b8]%s[/color]\n      英雄池：%s%s   [color=#8a92b8]语言：%s[/color]\n%s" % [
				ROLE_COL[p["role"]], HeroesDB.ROLE_NAMES[p["role"]], p["name"], ("「%s」" % str(p.get("tagline", ""))) if str(p.get("tagline", "")) != "" else "",
				"♀" if str(p["gender"]) == "f" else "♂", int(p["age"]), Cast.NATION_NAMES.get(p["nation"], p["nation"]), World.rating(p), "  ".join(PackedStringArray(attrs)),
				"、".join(PackedStringArray(pool)), ("    特质：" + "、".join(PackedStringArray(traits))) if not traits.is_empty() else "", "、".join(PackedStringArray(langs)), extra]
		body.add_child(_rt(txt, 14))

func _mood(v: float) -> String:
	return "[color=#6aff8a]满意[/color]" if v >= 65.0 else ("[color=#ffd23f]一般[/color]" if v >= 40.0 else "[color=#ff6a6a]不满[/color]")

func _form_txt(v: float) -> String:
	return "[color=#ff9a6a]火热[/color]" if v >= 1.0 else ("[color=#8ab0ff]低迷[/color]" if v <= -1.0 else "正常")

## 消息: choices waiting for the player, and what happened in the story so far
func _show_inbox() -> void:
	var pend: Array = Story.pending(season)
	body.add_child(_rt("[b]消息[/b]  [color=#8a92b8]（之后会搬进手机界面）[/color]", 18))
	if pend.is_empty():
		body.add_child(_rt("[color=#8a92b8]没有待处理的消息。[/color]", 14))
	for it in pend:
		var d: Dictionary = Story.describe(season, it)
		body.add_child(_rt("[color=%s]%s[/color]  %s" % ["#ffd23f" if str(d["kind"]) == "major" else "#8ad8ff", "重要" if str(d["kind"]) == "major" else "消息", str(d["text"])], 15))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for i in (d["choices"] as Array).size():
			row.add_child(_btn(str(d["choices"][i]), _choose_event.bind(int(it["uid"]), i), 300))
		body.add_child(row)
	var log: Array = Story.state(season)["log"]
	if not log.is_empty():
		var txt := "\n[b]最近发生的事[/b]\n"
		var rows: Array = log.slice(maxi(0, log.size() - 20))
		rows.reverse()
		for e in rows:
			txt += "[color=#8a92b8]S%d 第 %d 周[/color]  %s\n" % [int(e["s"]), int(e["w"]), str(e["text"])]
		body.add_child(_rt(txt, 14))

func _choose_event(uid: int, choice: int) -> void:
	Story.resolve(season, uid, choice)
	_autosave()
	refresh()

## 前世笔记: what the protagonist remembers, and whether it still holds
func _show_notes() -> void:
	body.add_child(_rt("[b]前世笔记[/b]  [color=#8a92b8]你记得的原本的历史。你改变得越多，它就越不可靠。[/color]", 18))
	var tag := {"pending": "[color=#c8d8ff]待发生[/color]", "uncertain": "[color=#ffd23f]不确定[/color]", "fulfilled": "[color=#6aff8a]已应验[/color]",
		"changed": "[color=#ff9a6a][s]已改变[/s][/color]"}
	var txt := ""
	for n in Story.notes(season):
		var t: String = str(n["text"]) if bool(n["clear"]) else "（模糊）" + str(n["text"])
		if str(n["status"]) == "changed":
			t = "[s]%s[/s]" % t
		txt += "%s  %s\n" % [tag.get(n["status"], ""), t]
	if txt == "":
		txt = "[color=#8a92b8]暂时什么都想不起来。[/color]"
	body.add_child(_rt(txt, 15))

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
		"stage": "#8ad8ff", "award": "#ffd23f", "intro": "#c8d8ff", "story": "#ffb0e0"}
	var n_weeks: int = Season.n_weeks(season)
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
	if human_side >= 0:
		Training.commit_human(season)   # the team trains, then plays
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
		var roles := [Series.roles_of(cur, season["world"], 0), Series.roles_of(cur, season["world"], 1)]
		Draft.apply(d, Draft.ai_choice(d, side2, roles[side2], roles[1 - side2], rng, Draft.noise_for(World.team(season["world"], Series.tid(cur, side2)), season["world"])))
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
	Series.start_draft(cur, season["world"], human_side, my_lineup)
	my_lineup = {}
	refresh()
	_kick_ai()

func _set_lineup(role: String, pid: String) -> void:
	# swap: whoever had this player moves to the role being replaced
	var old: String = str(my_lineup.get(role, ""))
	for r in my_lineup:
		if str(my_lineup[r]) == pid:
			my_lineup[r] = old
	my_lineup[role] = pid
	refresh()

## 4 选 3: the human picks the three starters of the next map (default: the AI suggestion)
func _show_lineup_picker() -> void:
	var w: Dictionary = season["world"]
	var tid: String = Series.tid(cur, human_side)
	if not Series.valid_lineup(w, tid, my_lineup):
		my_lineup = People.best_lineup(w, tid)
	var mates: Array = [str(my_lineup["tank"]), str(my_lineup["carry"]), str(my_lineup["support"])]
	var info: Dictionary = People.lineup_info(w, mates)
	body.add_child(_rt("[b]首发（4 选 3）[/b]  [color=#8a92b8]队内沟通 %.1f / 3 · 比赛中每回合购买阶段都可以换人[/color]" % float(info["comm"]), 16))
	for role in Series.ROLE_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := _rt("[color=%s]%s[/color]" % [ROLE_COL[role], HeroesDB.ROLE_NAMES[role]], 15)
		lab.custom_minimum_size.x = 60
		lab.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(lab)
		for pid in World.team(w, tid)["players"]:
			var p: Dictionary = w["players"][pid]
			var on: bool = str(my_lineup[role]) == str(pid)
			var tw: float = float(info["mods"].get(pid, 0.0)) if mates.has(pid) else 0.0
			var b := _btn("%s%s %.1f%s%s" % ["● " if on else "", p["name"], Draft.role_value(People.match_profile(w, p, mates), role),
				"" if str(p["role"]) == role else "（非本职）", ("  疲劳%d" % int(p.get("fatigue", 0.0))) if float(p.get("fatigue", 0.0)) >= 60.0 else ""], _set_lineup.bind(role, str(pid)), 200)
			if on:
				b.modulate = Color(1.2, 1.2, 0.8)
			row.add_child(b)
		var mod_txt := "配合修正 %+.1f" % float(info["mods"].get(str(my_lineup[role]), 0.0))
		row.add_child(_rt("[color=#8a92b8]%s[/color]" % mod_txt, 13))
		body.add_child(row)

func _show_series() -> void:
	var w: Dictionary = season["world"]
	var head := "[b]%s  %d : %d  %s[/b]   [color=#8a92b8]BO3 · %s[/color]" % [_team_bb(str(cur["a"])), int(cur["score"][0]), int(cur["score"][1]),
		_team_bb(str(cur["b"])), {"regular": "常规赛", "semi": "半决赛", "final": "总决赛", "promo": "升降级附加赛"}[str(cur["kind"])]]
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
		status.text = "第 %d 图：%s。%s准备禁选英雄。" % [(cur["maps"] as Array).size() + 1, _map_name(Series.next_map(cur)), "先定首发，再" if human_side >= 0 else ""]
		if human_side >= 0:
			_show_lineup_picker()
		actions.add_child(_btn("开始禁选", _start_map_draft, 150))
		if human_side < 0:
			actions.add_child(_btn("整个系列赛直接出结果", _skip_series, 200))
		actions.add_child(_btn("返回赛程", _back_to_hub, 120))
		return
	_show_draft(d, w)

func _show_draft(d: Dictionary, w: Dictionary) -> void:
	var map_no: int = (cur["maps"] as Array).size() + 1
	var roles := [Series.roles_of(cur, w, 0), Series.roles_of(cur, w, 1)]
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
			var cap_role := ""
			for r in cur["lineup"][human_side]:
				if str(cur["lineup"][human_side][r]) == Cast.PROTAGONIST:
					cap_role = str(r)
			if cap_role != "":
				actions.add_child(_btn("亲自上场（操控 %s）" % _hero_name(str(d["picks"][human_side][cap_role])), _play_map.bind(true), 230))
				actions.add_child(_btn("观战（AI 代打）", _play_map.bind(false), 170))
			else:
				actions.add_child(_btn("观战（队长在替补席）", _play_map.bind(false), 200))
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
	_autosave()
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
