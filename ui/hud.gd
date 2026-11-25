extends Node
## In-game HUD: labels, bars, skill slots, toasts, feed, scoreboard, end screen.
## (split out of the old monolithic main.gd — see docs/架构说明.md)

const C = preload("res://game/consts.gd")
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
const ShopUIT = preload("res://ui/shop_ui.gd")
var shp: ShopUIT
const MenusT = preload("res://ui/menus.gd")
var mnu: MenusT
const PlayerInputT = preload("res://input/player_input.gd")
var inp: PlayerInputT
## main.gd (composition root)
var app: Node = null

var best := 0.0
# ui
var ui: CanvasLayer
var ui_root: Control
var hud: Control
var time_lbl: Label
var event_lbl: Label
var kills_lbl: Label
var buff_lbl: Label
var center_lbl: Label
var sub_lbl: Label
var deny_lbl: Label
var toast_box: VBoxContainer
var feed_box: VBoxContainer
var lvl_lbl: Label
var xp_fill: ColorRect
var hp_fill: ColorRect
var hp_txt: Label
var mp_fill: ColorRect
var mp_txt: Label
var slots := {}
var sel_panel: PanelContainer
var sel_name: Label
var sel_hp: Label
var sel_desc: Label
var silence_icon: TextureRect
var flash_rect: ColorRect
var points_lbl: Label
var attr_rt: RichTextLabel
var stats_panel: PanelContainer
var stats_rt: RichTextLabel
var score_rt: RichTextLabel
var board: PanelContainer
var board_rt: RichTextLabel
var minimap: Control
var respawn_lbl: Label
func _label(size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.label_settings = vw._ls(size, col)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _place(c: Control, preset: int, l: float, tp: float, w: float, h: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = tp
	c.offset_right = l + w
	c.offset_bottom = tp + h

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb

# ============================================================ HUD
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ui_root)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(flash_rect)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hud)

	time_lbl = _label(32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_place(time_lbl, Control.PRESET_CENTER_TOP, -200, 8, 400, 40)
	hud.add_child(time_lbl)
	score_rt = shp._rt(30)
	_place(score_rt, Control.PRESET_CENTER_TOP, -260, 6, 520, 44)
	hud.add_child(score_rt)
	event_lbl = _label(16, Color(1.0, 0.75, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_place(event_lbl, Control.PRESET_CENTER_TOP, -300, 46, 600, 24)
	hud.add_child(event_lbl)
	kills_lbl = _label(20, Color(0.6, 1.0, 1.0))
	_place(kills_lbl, Control.PRESET_TOP_LEFT, 20, 12, 400, 30)
	hud.add_child(kills_lbl)
	buff_lbl = _label(18, Color(1.0, 0.85, 0.4))
	_place(buff_lbl, Control.PRESET_TOP_LEFT, 20, 42, 500, 60)
	hud.add_child(buff_lbl)
	deny_lbl = _label(22, Color(1.0, 0.35, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	_place(deny_lbl, Control.PRESET_CENTER_BOTTOM, -300, -210, 600, 30)
	hud.add_child(deny_lbl)
	respawn_lbl = _label(30, Color(1.0, 0.5, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_place(respawn_lbl, Control.PRESET_CENTER, -300, -150, 600, 50)
	hud.add_child(respawn_lbl)
	toast_box = VBoxContainer.new()
	_place(toast_box, Control.PRESET_TOP_LEFT, 20, 96, 520, 300)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_box)
	feed_box = VBoxContainer.new()
	_place(feed_box, Control.PRESET_TOP_RIGHT, -380, 214, 364, 220)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed_box)
	minimap = Control.new()
	_place(minimap, Control.PRESET_TOP_RIGHT, -196, 12, 184, 184)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(vw._draw_minimap)
	hud.add_child(minimap)

	# ---- bottom hero panel (DOTA-like)
	var bar := PanelContainer.new()
	_place(bar, Control.PRESET_CENTER_BOTTOM, -330, -168, 660, 160)
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.03, 0.09, 0.92), Color(0.3, 0.8, 1.0, 0.8)))
	hud.add_child(bar)
	var root := Control.new()
	root.custom_minimum_size = Vector2(644, 144)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(root)
	lvl_lbl = _label(30, Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	lvl_lbl.position = Vector2(0, 6)
	lvl_lbl.size = Vector2(80, 60)
	root.add_child(lvl_lbl)
	var lv_cap := _label(13, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	lv_cap.text = "等级"
	lv_cap.size = Vector2(80, 18)
	root.add_child(lv_cap)
	var xp_back := ColorRect.new()
	xp_back.position = Vector2(8, 66)
	xp_back.size = Vector2(64, 6)
	xp_back.color = Color(0.15, 0.12, 0.05)
	root.add_child(xp_back)
	xp_fill = ColorRect.new()
	xp_fill.size = Vector2(0, 6)
	xp_fill.color = Color(1.0, 0.85, 0.3)
	xp_back.add_child(xp_fill)
	points_lbl = _label(13, Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	points_lbl.position = Vector2(0, 74)
	points_lbl.size = Vector2(80, 20)
	root.add_child(points_lbl)
	# 3C order on screen: right-click signature skill first, then Q E R (the right-click lives in slot "w")
	var keys := ["w", "q", "e", "r"]
	for i in 4:
		_make_slot(root, keys[i], Vector2(92 + i * 112, 22), 72)
	_make_slot(root, "attr", Vector2(560, 34), 48)
	var hp_back := ColorRect.new()
	hp_back.position = Vector2(8, 106)
	hp_back.size = Vector2(628, 16)
	hp_back.color = Color(0.1, 0.03, 0.03)
	root.add_child(hp_back)
	hp_fill = ColorRect.new()
	hp_fill.size = Vector2(628, 16)
	hp_fill.color = Color(0.25, 0.8, 0.3)
	hp_back.add_child(hp_fill)
	hp_txt = _label(13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hp_txt.position = Vector2(0, -3)
	hp_txt.size = Vector2(628, 18)
	hp_back.add_child(hp_txt)
	var mp_back := ColorRect.new()
	mp_back.position = Vector2(8, 124)
	mp_back.size = Vector2(628, 14)
	mp_back.color = Color(0.03, 0.04, 0.12)
	root.add_child(mp_back)
	mp_fill = ColorRect.new()
	mp_fill.size = Vector2(628, 14)
	mp_fill.color = Color(0.25, 0.45, 1.0)
	mp_back.add_child(mp_fill)
	mp_txt = _label(12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	mp_txt.position = Vector2(0, -3)
	mp_txt.size = Vector2(628, 16)
	mp_back.add_child(mp_txt)
	silence_icon = TextureRect.new()
	silence_icon.texture = gm.TEX["silence"]
	silence_icon.position = Vector2(600, 0)
	silence_icon.size = Vector2(32, 32)
	silence_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silence_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	silence_icon.visible = false
	root.add_child(silence_icon)

	# ---- selected unit panel
	sel_panel = PanelContainer.new()
	_place(sel_panel, Control.PRESET_BOTTOM_LEFT, 16, -330, 300, 150)
	sel_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.03, 0.09, 0.88), Color(1.0, 0.4, 0.5, 0.7)))
	hud.add_child(sel_panel)
	var sv := VBoxContainer.new()
	sel_panel.add_child(sv)
	sel_name = _label(20, Color(1.0, 0.6, 0.65))
	sv.add_child(sel_name)
	sel_hp = _label(14, Color(0.9, 0.9, 0.9))
	sv.add_child(sel_hp)
	sel_desc = _label(13, Color(0.85, 0.85, 1.0))
	sel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_desc.custom_minimum_size = Vector2(280, 0)
	sv.add_child(sel_desc)
	sel_panel.visible = false

	shp._build_ui_v3()
	# ---- scoreboard (Tab)
	board = PanelContainer.new()
	_place(board, Control.PRESET_CENTER, -420, -250, 840, 420)
	board.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.02, 0.08, 0.95), Color(0.3, 0.8, 1.0, 0.8)))
	board.visible = false
	hud.add_child(board)
	board_rt = shp._rt(15)
	board.add_child(board_rt)

	center_lbl = _label(84, Color(0.4, 1.0, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	center_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(center_lbl, Control.PRESET_CENTER, -640, -300, 1280, 130)
	ui_root.add_child(center_lbl)
	sub_lbl = _label(20, Color(0.9, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_place(sub_lbl, Control.PRESET_CENTER, -640, -160, 1280, 360)
	ui_root.add_child(sub_lbl)

func _make_slot(root: Control, key: String, pos: Vector2, size: float) -> void:
	var box := Control.new()
	box.position = pos
	box.size = Vector2(size, size)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(box)
	var icon := TextureRect.new()
	icon.texture = gm.TEX["icon_attr"] if key == "attr" else gm.TEX["icon_" + key]
	icon.size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var cdr := ColorRect.new()
	cdr.color = Color(0, 0, 0, 0.7)
	cdr.size = Vector2(size, 0)
	cdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cdr)
	var cdl := _label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cdl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cdl.size = Vector2(size, size)
	box.add_child(cdl)
	var kl := _label(14, Color(1, 1, 1, 0.9))
	kl.text = ("右键" if key == "w" else key.to_upper()) if key != "attr" else ""
	kl.position = Vector2(3, 0)
	box.add_child(kl)
	var ml := _label(12, Color(0.5, 0.7, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	ml.position = Vector2(0, size - 16)
	ml.size = Vector2(size - 3, 16)
	box.add_child(ml)
	var pips := HBoxContainer.new()
	pips.position = Vector2(0, size + 3)
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pips)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.position = Vector2(size / 2 - 14, -26)
	plus.size = Vector2(28, 24)
	plus.add_theme_font_size_override("font_size", 18)
	var psb := _panel_style(Color(0.35, 0.25, 0.0, 0.95), Color(1.0, 0.85, 0.3))
	psb.set_content_margin_all(0)
	plus.add_theme_stylebox_override("normal", psb)
	plus.add_theme_stylebox_override("hover", _panel_style(Color(0.6, 0.45, 0.05), Color(1.0, 0.95, 0.5)))
	plus.add_theme_stylebox_override("pressed", psb)
	plus.pressed.connect(inp._learn.bind(key))
	box.add_child(plus)
	slots[key] = {"box": box, "icon": icon, "cd": cdr, "cdl": cdl, "mana": ml, "pips": pips, "plus": plus, "size": size}

## re-skin the skill bar for the player's hero
func _setup_hud() -> void:
	var icons: Dictionary = gm.player.def["icons"]
	for key in slots:
		var sl: Dictionary = slots[key]
		var size: float = sl["size"]
		var n := 10
		if key != "attr":
			(sl["icon"] as TextureRect).texture = gm.TEX[icons[key]]
			n = int(gm.player.sdef[key]["max"])
			(sl["box"] as Control).tooltip_text = str(gm.player.kit.tip(key))
		else:
			(sl["box"] as Control).tooltip_text = "属性加成（最多 10 级）\n每级：力量、敏捷、智力各 +2。\nCtrl+O 学习"
		var pips := sl["pips"] as HBoxContainer
		for c in pips.get_children():
			pips.remove_child(c)
			c.queue_free()
		var pw := (size - 3 * (n - 1)) / n
		for i in n:
			var p := ColorRect.new()
			p.custom_minimum_size = Vector2(pw, 5)
			p.color = Color(0.25, 0.25, 0.3)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(p)

func _load_best() -> void:
	if FileAccess.file_exists("user://neondrift2.save"):
		var f := FileAccess.open("user://neondrift2.save", FileAccess.READ)
		best = float(f.get_var())

func _save_best() -> void:
	var f := FileAccess.open("user://neondrift2.save", FileAccess.WRITE)
	f.store_var(best)

func _fmt(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]

func _hud_match_ended(win: bool) -> void:
	shp._close_shop()
	center_lbl.modulate.a = 1.0
	sub_lbl.modulate.a = 1.0
	center_lbl.label_settings.font_size = 92
	respawn_lbl.text = ""
	if win:
		center_lbl.label_settings.font_color = Color(1.0, 0.9, 0.4)
		center_lbl.text = "VICTORY"
		_flash(Color(1, 1, 1, 0.6))
	else:
		center_lbl.label_settings.font_color = Color(1.0, 0.35, 0.6)
		center_lbl.text = "SIGNAL LOST" if gm.mode == C.M.SURVIVAL else "DEFEAT"
	if gm.mode == C.M.SURVIVAL:
		var new_best := gm.t > best
		if new_best:
			best = gm.t
			_save_best()
		sub_lbl.text = "%s存活 %s     等级 %d     消灭 %d\n\n最长存活 %s\n\n[ R 再来一局    Esc 返回菜单 ]" % [
			("你在霓虹尸潮中坚持了 30 分钟！\n\n" if win else ("★ 新纪录 ★\n" if new_best else "")), _fmt(gm.t), gm.player.level, gm.kills, _fmt(best)]
	elif gm.mode == C.M.ROUNDS:
		sub_lbl.text = "回合  霓虹队  %d  :  %d  赤潮队     用时 %s\n\n你：%s   %d / %d / %d\n\n[ R 再来一局    Esc 返回菜单 ]" % [
			gm.rounds.score[0], gm.rounds.score[1], _fmt(gm.t), gm.player.display_name(), gm.player.kills, gm.player.deaths, gm.player.assists]
	else:
		sub_lbl.text = "霓虹队  %d  :  %d  赤潮队     用时 %s\n\n你：%s  等级 %d   %d / %d / %d\n\n[ R 再来一局    Esc 返回菜单 ]" % [
			gm.team_kills[0], gm.team_kills[1], _fmt(gm.t), gm.player.display_name(), gm.player.level, gm.player.kills, gm.player.deaths, gm.player.assists]

func _feed(text: String, col: Color) -> void:
	var l := _label(16, col, HORIZONTAL_ALIGNMENT_RIGHT)
	l.text = text
	l.custom_minimum_size = Vector2(360, 0)
	feed_box.add_child(l)
	if feed_box.get_child_count() > 6:
		feed_box.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _flash(c: Color) -> void:
	flash_rect.color = c

func toast(text: String, col := Color.WHITE, dur := 4.0) -> void:
	var l := _label(16, col, HORIZONTAL_ALIGNMENT_LEFT)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	toast_box.add_child(l)
	if toast_box.get_child_count() > 6:
		toast_box.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _announce(text: String, col: Color, dur := 1.6) -> void:
	var l := _label(56, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	_place(l, Control.PRESET_CENTER_TOP, -500, 130, 1000, 80)
	l.pivot_offset = Vector2(500, 40)
	l.scale = Vector2(1.5, 1.5)
	ui.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

# ============================================================ HUD update
func _update_fx_ui(delta: float) -> void:
	gm.shake = maxf(0.0, gm.shake - delta * 40.0)
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 2.0)
	inp.marker_t -= delta
	if (gm.state != C.S.PLAY and gm.state != C.S.END) or gm.player == null:
		return
	var p := gm.player
	if gm.mode == C.M.SURVIVAL:
		time_lbl.text = "%s  /  30:00" % _fmt(gm.t)
		kills_lbl.text = "消灭 %d" % gm.kills
		var nxt := ""
		for i in range(gm.event_i, C.EVENTS.size()):
			var ev: Array = C.EVENTS[i]
			if str(ev[1]).begins_with("boss"):
				var names := {"boss1": "Boss · 典狱长", "boss2": "Boss · 典狱长·至尊", "boss3": "最终 Boss · 奇点之心"}
				nxt = "%s  ·  %s" % [names[ev[1]], _fmt(ev[0])]
				break
		event_lbl.text = nxt if nxt != "" else "坚持到 30:00！"
		if not gm.bosses.is_empty():
			var bz = gm.bosses[0]
			if is_instance_valid(bz) and not bz.dead:
				event_lbl.text = "%s   %d / %d   (%d%%)" % [gm._ename(bz), int(bz.hp), int(bz.max_hp), int(100.0 * bz.hp / bz.max_hp)]
	elif gm.mode == C.M.ROUNDS:
		_update_rounds_hud(p)
	else:
		score_rt.text = "[center][color=#5fe8ff]霓虹  %d[/color]   [color=#8a92b8]%s[/color]   [color=#ff6a6a]%d  赤潮[/color][/center]" % [gm.team_kills[0], _fmt(gm.t), gm.team_kills[1]]
		var b0 = gm.brain(0)
		var call_txt := ""
		if b0 != null:
			call_txt = "   ·   队伍指令：" + str({"group": "集结推进", "fight": "开团！", "hold": "等待队友复活", "retreat": "撤退"}.get(b0.intent, ""))
		event_lbl.text = ("先拿到 %d 次击倒获胜" % C.ARENA_KILLS if gm.t < C.ARENA_LEN else "加时赛：下一次击倒决定胜负") + call_txt
		respawn_lbl.text = ("阵亡 · %d 秒后复活" % int(ceil(p.respawn_t))) if (p.dead and gm.state == C.S.PLAY) else ""
		if board.visible and Engine.get_process_frames() % 15 == 0:
			_update_board()
	var buffs := []
	if p.haste_t > 0.0: buffs.append("极速神符 %ds" % int(ceil(p.haste_t)))
	if p.dd_t > 0.0: buffs.append("双倍伤害 %ds" % int(ceil(p.dd_t)))
	if p.slow > 0.0: buffs.append("减速中")
	if p.silence > 0.0: buffs.append("沉默 %.1fs" % p.silence)
	if p.hid == "blade" and int(p.kit.oath_n) > 0: buffs.append("血誓 ×%d" % int(p.kit.oath_n))
	if p.barrier > 0.0: buffs.append("护盾 %d" % int(p.barrier))
	if p.has_buff("root"): buffs.append("被缠绕")
	if p.has_buff("taunt"): buffs.append("被嘲讽")
	if p.has_buff("banish"): buffs.append("星界庇护")
	if p.has_buff("dr"): buffs.append("减伤 %d%%" % int(p.buff_v("dr") * 100.0))
	buff_lbl.text = "   ".join(PackedStringArray(buffs))
	shp._update_ui_v3(delta)
	lvl_lbl.text = str(p.level)
	xp_fill.size.x = 64.0 * (1.0 if p.level >= 25 else clampf(p.xp / p.xp_need(), 0.0, 1.0))
	points_lbl.text = ("技能点 %d" % p.skill_points) if p.skill_points > 0 else ""
	hp_fill.size.x = 628.0 * clampf(p.hp / p.max_hp, 0.0, 1.0)
	hp_txt.text = "%d / %d   +%.1f" % [int(p.hp), int(p.max_hp), p.hp_regen()]
	mp_fill.size.x = 628.0 * clampf(p.mana / p.mana_max, 0.0, 1.0)
	mp_txt.text = "%d / %d   +%.1f" % [int(p.mana), int(p.mana_max), p.mp_regen()]
	silence_icon.visible = p.silence > 0.0
	for s in slots:
		var sl: Dictionary = slots[s]
		var size: float = sl["size"]
		var lv: int = int(p.sk[s])
		var icon := sl["icon"] as TextureRect
		icon.modulate = Color(1, 1, 1) if lv > 0 else Color(0.35, 0.35, 0.4)
		var active: bool = s != "attr" and p.sdef[s]["type"] != "passive"
		var cdv := 0.0
		var cdmax := 1.0
		if active and lv > 0:
			cdv = float(p.cds[s])
			cdmax = p.skill_cd(s)
		var frac := clampf(cdv / maxf(cdmax, 0.01), 0.0, 1.0)
		(sl["cd"] as ColorRect).size = Vector2(size, size * frac)
		(sl["cdl"] as Label).text = ("%d" % int(ceil(cdv))) if cdv > 0.0 else ""
		var ml := sl["mana"] as Label
		if active and lv > 0:
			var mc: float = p.sv(s, "mana")
			ml.text = "%d" % int(mc)
			ml.label_settings.font_color = Color(0.5, 0.7, 1.0) if p.mana >= mc else Color(1.0, 0.3, 0.3)
		else:
			ml.text = ""
		if p.silence > 0.0 and active:
			icon.modulate = Color(0.6, 0.3, 0.8)
		if s == inp.targeting:
			icon.modulate = Color(1.8, 1.8, 1.2)
		var pips := sl["pips"] as HBoxContainer
		for i in pips.get_child_count():
			(pips.get_child(i) as ColorRect).color = Color(1.0, 0.85, 0.3) if i < lv else Color(0.25, 0.25, 0.3)
		(sl["plus"] as Button).visible = p.can_learn(s)
	# selection panel
	var sel = inp.selected
	if sel != null and is_instance_valid(sel) and sel != p and not sel.dead:
		sel_panel.visible = true
		var extra := ""
		if sel.charged > 0.0: extra += "  ·  感电"
		if sel.mark > 0.0: extra += "  ·  血印"
		if sel.stun > 0.0: extra += "  ·  晕眩"
		var arm: float = sel.armor_val()
		if sel.is_hero:
			sel_name.text = "%s  Lv.%d  %s" % [sel.display_name(), sel.level, ("（队友）" if sel.team == p.team else "（对方）")]
			sel_hp.text = "生命 %d / %d%s\n护甲 %.1f（物理减伤 %d%%）   魔抗 %d%%\n%d / %d / %d   攻击力 %d" % [int(sel.hp), int(sel.max_hp), extra, arm, int(round((1.0 - gm.armor_mult(arm)) * 100.0)), int(round(sel.mr_val() * 100.0)), sel.kills, sel.deaths, sel.assists, int(sel.atk_dmg())]
			var names := []
			for id in sel.inv:
				names.append(ItemsDB.DB[id]["name"])
			sel_desc.text = "装备：" + ("、".join(PackedStringArray(names)) if not names.is_empty() else "无")
		else:
			sel_name.text = ("精英 " if sel.elite else "") + gm._ename(sel)
			if sel.frenzy: extra += "  ·  狂怒"
			if sel.shield: extra += "  ·  护盾"
			sel_hp.text = "生命 %d / %d%s\n护甲 %.1f（物理减伤 %d%%）   魔抗 %d%%" % [int(sel.hp), int(sel.max_hp), extra, arm, int(round((1.0 - gm.armor_mult(arm)) * 100.0)), int(round(sel.mr_val() * 100.0))]
			sel_desc.text = C.EDEF[sel.kind]["desc"]
	else:
		sel_panel.visible = false

func _update_board() -> void:
	var txt := "[center][b][color=#ffd23f]计分板[/color][/b]   [color=#8a92b8]%s · 先拿到 %d 次击倒获胜[/color][/center]\n" % [_fmt(gm.t), C.ARENA_KILLS]
	if gm.rounds != null:
		txt = "[center][b][color=#ffd23f]计分板[/color][/b]   [color=#8a92b8]第 %d 回合 · 回合比分 %d : %d · 先赢 %d 回合获胜[/color][/center]\n" % [gm.rounds.round_n, gm.rounds.score[0], gm.rounds.score[1], gm.rounds.ROUNDS_TO_WIN]
	for tm in 2:
		var hc := "#5fe8ff" if tm == 0 else "#ff6a6a"
		txt += "\n[color=%s][b]%s  %d[/b][/color]\n" % [hc, ("霓虹队" if tm == 0 else "赤潮队"), gm.team_kills[tm]]
		for h in gm.heroes:
			if h.team != tm: continue
			var names := []
			for id in h.inv:
				names.append(ItemsDB.DB[id]["name"])
			var st := ("[color=#ff8080]阵亡 %ds[/color]" % int(ceil(h.respawn_t))) if h.dead else ""
			var heal_txt := ("   治疗 %d" % int(h.heal_done)) if h.heal_done >= 1.0 else ""
			txt += "  %s%s[color=#8a92b8]（%s）[/color]  Lv.%d   %d / %d / %d   金 %d%s   %s %s\n" % [
				("[color=#ffff80]你·[/color]" if h.is_player else ""), h.display_name(), HeroesDB.ROLE_NAMES[h.role()], h.level, h.kills, h.deaths, h.assists, int(h.gold),
				heal_txt, "、".join(PackedStringArray(names)), st]
	board_rt.text = txt

func _hud_world_cleared() -> void:
	for c in feed_box.get_children():
		c.queue_free()
	for c in toast_box.get_children():
		c.queue_free()

func _hud_match_started() -> void:
	mnu.menu_root.visible = false
	hud.visible = true
	board.visible = false
	stats_panel.visible = false
	center_lbl.text = ""
	sub_lbl.text = ""
	respawn_lbl.text = ""
	shp._close_shop()
	_setup_hud()
	shp._refresh_inv()
	var arena := gm.mode != C.M.SURVIVAL
	minimap.visible = arena
	score_rt.visible = arena
	time_lbl.visible = not arena
	kills_lbl.visible = not arena

# ============================================================ round mode
func _update_rounds_hud(p) -> void:
	var r = gm.rounds
	score_rt.text = "[center][color=#5fe8ff]霓虹  %d[/color]   [color=#8a92b8]第 %d 回合 · %s[/color]   [color=#ff6a6a]%d  赤潮[/color][/center]" % [
		r.score[0], r.round_n, _fmt(maxf(0.0, r.time_left())), r.score[1]]
	var txt := ""
	match r.phase:
		"buy":
			txt = "购买阶段 · %d 秒后开战（B 打开商店）" % int(ceil(r.time_left()))
			if p.refund_tokens > 0:
				txt += " · 本回合可原价卖出一件装备"
		"live":
			if not r.core_open():
				txt = "核心 %d 秒后开放" % int(ceil(r.CORE_UNLOCK - r.phase_t))
			else:
				txt = "核心开放 · 占领  霓虹 %d%%  /  赤潮 %d%%" % [int(r.capture[0] * 100.0), int(r.capture[1] * 100.0)]
				if r.phase_t >= r.OVERTIME_AT:
					txt += " · 决战：占领速度 ×2"
		"post":
			txt = "回合结束 · 下一回合即将开始"
	var b0 = gm.brain(0)
	if b0 != null and r.phase == "live":
		txt += "   ·   队伍指令：" + str({"group": "集结推进", "fight": "开团！", "hold": "等待", "retreat": "撤退", "setup": "卡位等待核心开放"}.get(b0.intent, ""))
	event_lbl.text = txt
	respawn_lbl.text = "阵亡 · 等待下一回合" if (p.dead and gm.state == C.S.PLAY and r.phase == "live") else ""
	if board.visible and Engine.get_process_frames() % 15 == 0:
		_update_board()

func _hud_round_started(n: int) -> void:
	_announce("第 %d 回合" % n, Color(0.6, 1.4, 2.0), 1.2)
	shp._refresh_inv()

func _hud_round_live(_n: int) -> void:
	_announce("开战！", Color(1.0, 0.85, 0.35), 0.9)
	if shp.shop_open:
		shp._close_shop()

func _hud_round_ended(_n: int, w: int, reason: String) -> void:
	var r = gm.rounds
	var col := Color(0.4, 1.6, 2.0) if w == 0 else (Color(2.0, 0.5, 0.5) if w == 1 else Color(1.4, 1.4, 1.4))
	var who := "霓虹队" if w == 0 else ("赤潮队" if w == 1 else "双方")
	_announce("%s 赢下本回合（%s）" % [who, reason] if w >= 0 else "平局（%s）" % reason, col, 2.0)
	if gm.player != null:
		var streak: int = r.loss_streak[gm.player.team]
		var pay: float = r.WIN_PAY if w == gm.player.team else r.loss_pay(streak)
		toast("回合收入 +%d 金%s" % [int(pay), "（连败 %d，补偿递增；下回合可原价卖出一件装备）" % streak if w != gm.player.team else ""], Color(1.0, 0.85, 0.3), 4.0)

