extends Node
## Main menu, survival hero select, 3V3 setup.
## (split out of the old monolithic main.gd — see docs/架构说明.md)

const C = preload("res://game/consts.gd")
const Rounds = preload("res://game/rounds.gd")
const Maps = preload("res://game/maps.gd")
const Unit = preload("res://unit.gd")
const Hero = preload("res://hero.gd")
const HeroAI = preload("res://hero_ai.gd")
const TeamAI = preload("res://team_ai.gd")
const HeroesDB = preload("res://heroes_db.gd")
const ItemsDB = preload("res://items_db.gd")
const Enemy = preload("res://game/enemy.gd")
const HeroShot = preload("res://game/hero_shot.gd")
const EShot = preload("res://game/enemy_shot.gd")
const Grid = preload("res://view/grid.gd")
const Ring = preload("res://view/ring.gd")

const MatchT = preload("res://game/match.gd")
var gm: MatchT

const PresenterT = preload("res://view/presenter.gd")
var vw: PresenterT
const HudT = preload("res://ui/hud.gd")
var hd: HudT
const ShopUIT = preload("res://ui/shop_ui.gd")
var shp: ShopUIT
const PlayerInputT = preload("res://input/player_input.gd")
var inp: PlayerInputT
## main.gd (composition root)
var app: Node = null

## rules line under the 3V3 setup (text depends on arena / rounds)
var arena_rule: Label
var sel_mode := C.M.SURVIVAL
var menu_root: Control
var menu_main: VBoxContainer
var menu_surv: Control
var menu_arena: Control
var arena_opts: Array = []
var diff_opt: OptionButton
var map_opt: OptionButton        # round mode: which map (game/maps.gd)
var map_lbl: Label
# ============================================================ menus
func _menu_btn(text: String, w: float, h: float, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_override("font", vw.ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6))
	b.add_theme_stylebox_override("normal", hd._panel_style(Color(0.05, 0.04, 0.12, 0.92), Color(0.3, 0.8, 1.0, 0.7)))
	b.add_theme_stylebox_override("hover", hd._panel_style(Color(0.12, 0.08, 0.22, 0.95), Color(1.0, 0.85, 0.3)))
	b.add_theme_stylebox_override("pressed", hd._panel_style(Color(0.2, 0.14, 0.05, 0.95), Color(1.0, 0.85, 0.3)))
	return b

func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hd.ui_root.add_child(menu_root)
	# main
	menu_main = VBoxContainer.new()
	menu_main.add_theme_constant_override("separation", 14)
	hd._place(menu_main, Control.PRESET_CENTER, -200, -40, 400, 420)
	menu_root.add_child(menu_main)
	# stage 1.5: the click-to-move survival and old 3V3 arena modes are retired (branch archive/v0-click-control)
	var b3 := _menu_btn("回合制 3V3   [1]", 400, 64, 24)
	b3.pressed.connect(_open_select.bind(C.M.ROUNDS))
	menu_main.add_child(b3)
	var b4 := _menu_btn("3C 实验 · WASD 狙击手   [2]", 400, 64, 24)
	b4.pressed.connect(open_exp3c)
	menu_main.add_child(b4)
	var hint := hd._label(15, Color(0.75, 0.75, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "WASD 移动   鼠标瞄准   左键 普攻（按住连发）   右键 特色技能（可蓄力的按住蓄力）\nQ E R 技能   B 商店   C 属性   Tab 计分板   Esc 暂停   F6 AI 托管"
	menu_main.add_child(hint)
	# survival: pick a hero
	menu_surv = Control.new()
	menu_surv.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_surv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(menu_surv)
	var cards := GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 14)
	cards.add_theme_constant_override("v_separation", 14)
	# 9+ heroes no longer fit on a 1280x720 screen: the card grid scrolls (mouse wheel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hd._place(scroll, Control.PRESET_CENTER, -630, -300, 1260, 590)
	menu_surv.add_child(scroll)
	scroll.add_child(cards)
	for id in HeroesDB.ORDER:
		cards.add_child(_hero_card(str(id)))
	var scroll_hint := hd._label(14, Color(0.7, 0.7, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	scroll_hint.text = "鼠标滚轮上下翻页，共 %d 名英雄" % HeroesDB.ORDER.size()
	hd._place(scroll_hint, Control.PRESET_CENTER_BOTTOM, -200, -100, 400, 24)
	menu_surv.add_child(scroll_hint)
	var back1 := _menu_btn("返回", 160, 44, 18)
	hd._place(back1, Control.PRESET_CENTER_BOTTOM, -80, -58, 160, 44)
	back1.pressed.connect(_show_menu)
	menu_surv.add_child(back1)
	# arena: 5v5 setup
	menu_arena = Control.new()
	menu_arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(menu_arena)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 60)
	hd._place(cols, Control.PRESET_CENTER, -400, -170, 800, 330)
	menu_arena.add_child(cols)
	arena_opts = []
	for tm in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.custom_minimum_size = Vector2(370, 0)
		cols.add_child(col)
		var head := hd._label(24, Color(0.4, 1.8, 1.0) if tm == 0 else Color(2.0, 0.5, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
		head.text = "霓虹队（我方）" if tm == 0 else "赤潮队（对方 AI）"
		col.add_child(head)
		for i in C.TEAM_SIZE:
			var row := HBoxContainer.new()
			col.add_child(row)
			var who := hd._label(17, Color(1, 1, 0.6) if (tm == 0 and i == 0) else Color(0.8, 0.8, 0.95))
			who.text = "你" if (tm == 0 and i == 0) else ("AI 队友 %d" % i if tm == 0 else "AI 对手 %d" % (i + 1))
			who.custom_minimum_size = Vector2(110, 0)
			row.add_child(who)
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(250, 40)
			ob.add_theme_font_override("font", vw.ui_font)
			ob.add_theme_font_size_override("font_size", 17)
			for id in HeroesDB.ORDER:
				ob.add_item("%s  ·  %s" % [HeroesDB.HEROES[id]["name"], HeroesDB.ROLE_NAMES[HeroesDB.HEROES[id]["role"]]])
			ob.add_item("随机（按职业补位）")
			ob.select(HeroesDB.ORDER.find("ember") if (tm == 0 and i == 0) else HeroesDB.ORDER.size())
			row.add_child(ob)
			arena_opts.append(ob)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	hd._place(bottom, Control.PRESET_CENTER_BOTTOM, -440, -150, 880, 50)
	menu_arena.add_child(bottom)
	var dl := hd._label(18, Color(0.8, 0.8, 1.0))
	dl.text = "AI 难度"
	bottom.add_child(dl)
	diff_opt = OptionButton.new()
	diff_opt.focus_mode = Control.FOCUS_NONE
	diff_opt.custom_minimum_size = Vector2(120, 40)
	diff_opt.add_theme_font_override("font", vw.ui_font)
	diff_opt.add_theme_font_size_override("font_size", 17)
	for nm in ["简单", "普通", "困难"]:
		diff_opt.add_item(nm)
	diff_opt.select(1)
	bottom.add_child(diff_opt)
	map_lbl = hd._label(18, Color(0.8, 0.8, 1.0))
	map_lbl.text = "地图"
	bottom.add_child(map_lbl)
	map_opt = OptionButton.new()
	map_opt.focus_mode = Control.FOCUS_NONE
	map_opt.custom_minimum_size = Vector2(170, 40)
	map_opt.add_theme_font_override("font", vw.ui_font)
	map_opt.add_theme_font_size_override("font_size", 17)
	for mid in Maps.ORDER:
		map_opt.add_item(str(Maps.MAPS[mid]["name"]))
	map_opt.select(0)
	bottom.add_child(map_opt)
	var go := _menu_btn("开始对战", 200, 48, 22)
	go.pressed.connect(_start_arena_from_menu)
	bottom.add_child(go)
	var back2 := _menu_btn("返回", 120, 48, 18)
	back2.pressed.connect(_show_menu)
	bottom.add_child(back2)
	var rule := hd._label(15, Color(0.75, 0.75, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	arena_rule = rule
	rule.text = "坦克 · 输出 · 辅助 三职业 3V3 · 先拿到 %d 次击倒的队伍获胜（%d 分钟后击倒多者获胜）· 阵亡后在泉水复活 · 可选相同英雄" % [C.ARENA_KILLS, int(C.ARENA_LEN / 60.0)]
	hd._place(rule, Control.PRESET_CENTER_BOTTOM, -500, -90, 1000, 30)
	menu_arena.add_child(rule)

func _hero_card(id: String) -> Control:
	var d: Dictionary = HeroesDB.HEROES[id]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(398, 236)
	var col: Color = d["col"]
	p.add_theme_stylebox_override("panel", hd._panel_style(Color(0.04, 0.03, 0.1, 0.94), Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.9)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var tr := TextureRect.new()
	tr.texture = gm.TEX[str(d["sprite"]) + "_0"]
	tr.custom_minimum_size = Vector2(56, 56)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = Color(1.6, 1.6, 1.6)
	top.add_child(tr)
	var nv := VBoxContainer.new()
	top.add_child(nv)
	var nm := hd._label(24, Color(1.0, 0.9, 0.5))
	nm.text = "%s   [%s]" % [d["name"], HeroesDB.ROLE_NAMES[d["role"]]]
	nv.add_child(nm)
	var tl := hd._label(14, Color(0.7, 0.95, 1.0))
	tl.text = str(d["title"])
	nv.add_child(tl)
	var body := shp._rt(13)
	var b: Dictionary = d["base"]
	var gn: Dictionary = d["gain"]
	var prim: String = d["primary"]
	var star := {"str": "", "agi": "", "int": ""}
	star[prim] = "★"
	var txt: String = "[color=#d8d8ff]%s[/color]\n" % d["blurb"]
	txt += "[color=#ff7a6a]力量%s %d(+%s)[/color]  [color=#6aff8a]敏捷%s %d(+%s)[/color]  [color=#6ab0ff]智力%s %d(+%s)[/color]  %s\n" % [
		star["str"], int(b["str"]), shp._num(gn["str"]), star["agi"], int(b["agi"]), shp._num(gn["agi"]), star["int"], int(b["int"]), shp._num(gn["int"]), "近战" if bool(d["melee"]) else "射手"]
	for s in ["q", "w", "e", "r"]:
		txt += "[color=#ffd23f]%s[/color] %s  " % [("右键" if s == "w" and bool(d.get("c3", false)) else s.to_upper()), d["skills"][s]["name"]]
	txt += "\n[color=#a0ffa0]%s[/color]" % d["combo"]
	body.text = txt
	body.custom_minimum_size = Vector2(380, 0)
	v.add_child(body)
	var pick := _menu_btn("选择 %s" % d["name"], 380, 38, 17)
	pick.pressed.connect(gm._start_survival.bind(id))
	v.add_child(pick)
	return p

func _show_menu() -> void:
	gm.state = C.S.MENU
	gm._clear_world()
	vw.overlay.queue_redraw()
	vw.floor_layer.queue_redraw()
	hd.hud.visible = false
	menu_root.visible = true
	menu_main.visible = true
	menu_surv.visible = false
	menu_arena.visible = false
	shp._close_shop()
	hd.center_lbl.text = "NEON DRIFT"
	hd.center_lbl.label_settings.font_size = 104
	hd.center_lbl.label_settings.font_color = Color(0.4, 1.0, 1.0)
	hd.center_lbl.modulate.a = 1.0
	hd.sub_lbl.modulate.a = 1.0
	hd.sub_lbl.text = "霓 虹 漂 移"

## 3C experiment: standalone scene (exp3c/), Esc there comes back here
func open_exp3c() -> void:
	get_tree().change_scene_to_file("res://exp3c/exp3c.tscn")

func _open_select(m: int) -> void:
	gm.state = C.S.SELECT
	sel_mode = m
	menu_main.visible = false
	menu_surv.visible = m == C.M.SURVIVAL
	menu_arena.visible = m == C.M.ARENA or m == C.M.ROUNDS
	hd.center_lbl.label_settings.font_size = 56
	hd.center_lbl.text = {C.M.SURVIVAL: "选择英雄", C.M.ARENA: "3V3 英雄竞技场", C.M.ROUNDS: "回合制 3V3"}[m]
	map_opt.visible = m == C.M.ROUNDS
	map_lbl.visible = m == C.M.ROUNDS
	if m == C.M.ROUNDS:
		arena_rule.text = "先赢 %d 个回合获胜 · 每回合开局购买装备 · 中央核心开放后占满或全歼对手赢下回合 · 回合内不复活、没有升级" % Rounds.ROUNDS_TO_WIN
	elif m == C.M.ARENA:
		arena_rule.text = "坦克 · 输出 · 辅助 三职业 3V3 · 先拿到 %d 次击倒的队伍获胜（%d 分钟后击倒多者获胜）· 阵亡后在泉水复活 · 可选相同英雄" % [C.ARENA_KILLS, int(C.ARENA_LEN / 60.0)]
	hd.sub_lbl.text = ""
	vw.sfx("select", 1.2, -6.0)

func _start_arena_from_menu() -> void:
	var a := []
	var b := []
	var n: int = HeroesDB.ORDER.size()
	for i in C.TEAM_SIZE * 2:
		var ob: OptionButton = arena_opts[i]
		var k := ob.selected
		var lst: Array = a if i < C.TEAM_SIZE else b
		var id: String = str(HeroesDB.ORDER[k]) if k < n else ""
		lst.append(id)
	gm._fill_random(a)
	gm._fill_random(b)
	if sel_mode == C.M.ROUNDS:
		gm._start_rounds(a, b, diff_opt.selected, -1, {"map": str(Maps.ORDER[map_opt.selected])})
	else:
		gm._start_arena(a, b, diff_opt.selected)
