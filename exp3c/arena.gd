extends Node2D
## 3C experiment (WASD + mouse aim) — standalone scene, does not touch the match code.
## Opened from the main menu with [4]; Esc returns. See docs/design/3C实验_狙击手.md.

const SniperT = preload("res://exp3c/sniper.gd")
const DummyT = preload("res://exp3c/dummy.gd")

const FIELD := Rect2(-1500, -1000, 3000, 2000)
const DUMMIES := ["walker", "walker", "walker", "runner", "runner", "dodger", "dodger", "heavy"]
const ZOOM_BASE := 1.0
const ZOOM_EYE := 0.8                  # R active: base view is wider
const ZOOM_CHARGE := 0.62              # fully charged: the view pulls back to this fraction of the base

var sniper: SniperT
var dummies: Array = []
var bullets: Array = []                # dicts, see spawn_bullet
var mines: Array = []
var fx: Array = []                     # {type, pos, t, life, ...}
var cam: Camera2D
var shake := 0.0
var font: SystemFont
var stats := {"basic_fired": 0, "basic_hit": 0, "snipe_fired": 0, "snipe_hit": 0, "perfect": 0, "kills": 0}
var _dmg_log: Array = []               # [time, dmg] for DPS
var clock := 0.0
var toast_t := 0.0
var toast_text := ""
# HUD
var hud: CanvasLayer
var stat_lbl: Label
var help_lbl: Label
var toast_lbl: Label
var skill_lbls := {}
var snd := {}
var players: Array = []

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 600
	ThemeDB.fallback_font = font
	_build_env()
	for n in ["attack", "lance", "learn", "zap", "dash", "whistle", "rune", "boom", "ahit", "hit", "explode", "pickup", "deny"]:
		snd[n] = load("res://sfx/%s.wav" % n)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	sniper = SniperT.new()
	sniper.arena = self
	sniper.z_index = 2
	add_child(sniper)
	for k in DUMMIES:
		var dm := DummyT.new()
		add_child(dm)
		dm.setup(k, self, _spawn_point())
		dummies.append(dm)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 6):
		env.set_glow_level(i, 1.0)
	we.environment = env
	add_child(we)
	RenderingServer.set_default_clear_color(Color(0.02, 0.015, 0.05))

func _ls(size: int, col: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(4, size / 5)
	ls.outline_color = Color(0.02, 0.0, 0.08, 0.95)
	return ls

func _label(size: int, col: Color, pos: Vector2, w := 600.0) -> Label:
	var l := Label.new()
	l.label_settings = _ls(size, col)
	l.position = pos
	l.size = Vector2(w, 40)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var title := _label(24, Color(0.6, 1.0, 1.0), Vector2(20, 14))
	title.text = "3C 实验 · 狙击手「鹰隼」"
	help_lbl = _label(14, Color(0.75, 0.75, 0.95), Vector2(20, 48), 900)
	help_lbl.text = "WASD 移动   左键 脉冲弹（按住连发）   右键 按住蓄力狙击，松开射出   Q 战术翻滚   E 震爆雷   R 天穹之眼   Esc 返回菜单"
	stat_lbl = _label(15, Color(0.9, 0.9, 1.0), Vector2(20, 76), 900)
	toast_lbl = _label(20, Color(1.0, 0.85, 0.4), Vector2(440, 560), 400)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var names := {"q": "Q 战术翻滚", "e": "E 震爆雷", "r": "R 天穹之眼", "rmb": "右键 蓄力狙击"}
	var x := 330.0
	for k in ["rmb", "q", "e", "r"]:
		var l := _label(17, Color(0.7, 1.0, 1.0), Vector2(x, 666), 160)
		l.text = names[k]
		skill_lbls[k] = l
		x += 160.0

# ------------------------------------------------------------ helpers used by sniper / dummies
func clamp_in(p: Vector2, r: float) -> Vector2:
	return Vector2(clampf(p.x, FIELD.position.x + r, FIELD.end.x - r), clampf(p.y, FIELD.position.y + r, FIELD.end.y - r))

func random_point(near: Vector2, max_d: float) -> Vector2:
	return clamp_in(near + Vector2.from_angle(randf() * TAU) * randf_range(120.0, max_d), 40.0)

func _spawn_point() -> Vector2:
	for _i in 20:
		var p := Vector2(randf_range(FIELD.position.x + 80, FIELD.end.x - 80), randf_range(FIELD.position.y + 80, FIELD.end.y - 80))
		if sniper == null or p.distance_to(sniper.position) > 500.0:
			return p
	return Vector2(900, 0)

func sfx(n: String, pitch := 1.0, vol := 0.0) -> void:
	for p in players:
		if not p.playing:
			p.stream = snd[n]
			p.pitch_scale = pitch
			p.volume_db = vol
			p.play()
			return

func add_shake(v: float) -> void:
	shake = maxf(shake, v)

func toast(t: String) -> void:
	toast_text = t
	toast_t = 1.2

func spawn_bullet(b: Dictionary) -> void:
	b["hit"] = []
	b["trail"] = b["pos"]
	bullets.append(b)
	if b["kind"] in ["basic", "loaded"]:
		stats["basic_fired"] += 1

func spawn_mine(from: Vector2, to: Vector2) -> void:
	mines.append({"from": from, "to": to, "t": 0.0, "fly": 0.45})

# ------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://main.tscn")
			KEY_Q: sniper.cast("q", _inputs())
			KEY_E: sniper.cast("e", _inputs())
			KEY_R: sniper.cast("r", _inputs())

var test_input := {}                   # smoke test: scripted input instead of the devices

func _inputs() -> Dictionary:
	if not test_input.is_empty():
		return test_input
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1.0
	return {"move": mv.normalized(), "mouse": get_global_mouse_position(),
		"lmb": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "rmb": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)}

# ------------------------------------------------------------ frame
func _process(d: float) -> void:
	d = minf(d, 0.05)
	clock += d
	sniper.step(d, _inputs())
	for dm in dummies:
		if dm.dead:
			dm.respawn_t -= d
			if dm.respawn_t <= 0.0:
				dm.setup(dm.kind, self, _spawn_point())
		else:
			dm.step(d)
	_step_bullets(d)
	_step_mines(d)
	for f in fx:
		f["t"] += d
	fx = fx.filter(func(f): return f["t"] < f["life"])
	_update_camera(d)
	_update_hud(d)
	sniper.queue_redraw()
	queue_redraw()

func _update_camera(d: float) -> void:
	var base := ZOOM_EYE if sniper.eye_on() else ZOOM_BASE
	var c: float = sniper.charge if sniper.charging else 0.0
	var target_z := base * lerpf(1.0, ZOOM_CHARGE, ease(c, 0.6))
	# pulling back follows the charge; coming back after the shot eases in ~0.4 s
	var rate := 10.0 if target_z < cam.zoom.x else 5.0
	var z := lerpf(cam.zoom.x, target_z, 1.0 - exp(-rate * d))
	cam.zoom = Vector2(z, z)
	var mouse := get_global_mouse_position()
	var look: Vector2 = (mouse - sniper.position) * 0.18
	look = look.limit_length(140.0) + sniper.aim_dir * 320.0 * c
	var target_p: Vector2 = sniper.position + look
	cam.position = cam.position.lerp(target_p, 1.0 - exp(-9.0 * d))
	shake = maxf(0.0, shake - d * 40.0)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake

func _hit(dm, dmg: float, from: Vector2, kind: String) -> void:
	var was_alive: bool = not dm.dead
	var mult := 1.2 if dm.mark_t > 0.0 else 1.0
	dmg *= mult
	dm.hurt(dmg, from, 60.0 if kind in ["snipe", "perfect"] else 0.0)
	_dmg_log.append([clock, dmg])
	var big := kind == "perfect"
	fx.append({"type": "num", "pos": dm.position + Vector2(randf_range(-10, 10), -dm.radius - 20), "t": 0.0, "life": 0.8,
		"text": ("完美 " if big else "") + str(int(dmg)), "big": big or kind == "snipe"})
	fx.append({"type": "ring", "pos": dm.position, "t": 0.0, "life": 0.25, "r": dm.radius + (30.0 if big else 12.0),
		"col": Color(3.0, 2.4, 0.6) if big else Color(1.0, 2.2, 2.6)})
	sfx("ahit" if kind in ["basic", "loaded"] else "hit", randf_range(0.9, 1.1), -6.0)
	if was_alive and dm.dead:
		stats["kills"] += 1
		fx.append({"type": "ring", "pos": dm.position, "t": 0.0, "life": 0.5, "r": 90.0, "col": dm.col})
		sfx("explode", 1.2, -6.0)

func _step_bullets(d: float) -> void:
	var keep := []
	for b in bullets:
		var p0: Vector2 = b["pos"]
		var p1: Vector2 = p0 + b["vel"] * d
		var travel := p0.distance_to(p1)
		b["range"] = float(b["range"]) - travel
		var done := float(b["range"]) <= 0.0 or not FIELD.has_point(p1)
		var counted := false
		for dm in dummies:
			if dm.dead or b["hit"].has(dm):
				continue
			if Geometry2D.get_closest_point_to_segment(dm.position, p0, p1).distance_to(dm.position) < dm.radius + float(b["r"]):
				b["hit"].append(dm)
				_hit(dm, float(b["dmg"]), p0, b["kind"])
				if not counted:
					counted = true
					if b["kind"] in ["basic", "loaded"]:
						stats["basic_hit"] += 1
					else:
						stats["snipe_hit"] += 1
						if b["kind"] == "perfect":
							stats["perfect"] += 1
							add_shake(8.0)
				if b.get("explode", false):
					_explode(dm.position, 130.0, float(b["dmg"]) * 0.5, dm)
				b["pierce"] = int(b["pierce"]) - 1
				if int(b["pierce"]) <= 0:
					done = true
					p1 = dm.position
					break
		b["trail"] = p0
		b["pos"] = p1
		if not done:
			keep.append(b)
		else:
			fx.append({"type": "trail", "a": b["trail"], "b": p1, "t": 0.0, "life": 0.35 if b["kind"] in ["snipe", "perfect"] else 0.08,
				"w": float(b["r"]), "kind": b["kind"]})
	bullets = keep

func _explode(p: Vector2, r: float, dmg: float, skip) -> void:
	fx.append({"type": "ring", "pos": p, "t": 0.0, "life": 0.4, "r": r, "col": Color(3.0, 1.6, 0.5)})
	for dm in dummies:
		if not dm.dead and dm != skip and dm.position.distance_to(p) < r + dm.radius:
			_hit(dm, dmg, p, "splash")
			dm.mark_t = 4.0
	sfx("boom", 1.3, -6.0)

func _step_mines(d: float) -> void:
	var keep := []
	for m in mines:
		m["t"] = float(m["t"]) + d
		if float(m["t"]) >= float(m["fly"]):
			var p: Vector2 = m["to"]
			fx.append({"type": "ring", "pos": p, "t": 0.0, "life": 0.45, "r": SniperT.MINE_R, "col": Color(0.6, 1.4, 2.8)})
			for dm in dummies:
				if not dm.dead and dm.position.distance_to(p) < SniperT.MINE_R + dm.radius:
					dm.knock += (dm.position - p).normalized() * 520.0
					dm.slow_t = 2.0
					_hit(dm, SniperT.MINE_DMG, p, "mine")
			add_shake(6.0)
			sfx("boom", 1.0, -4.0)
		else:
			keep.append(m)
	mines = keep

func _update_hud(d: float) -> void:
	var dps := 0.0
	_dmg_log = _dmg_log.filter(func(e): return clock - float(e[0]) < 5.0)
	for e in _dmg_log:
		dps += float(e[1])
	dps /= 5.0
	var bf: int = stats["basic_fired"]
	var sf: int = stats["snipe_fired"]
	stat_lbl.text = "脉冲弹命中 %d/%d (%d%%)    狙击命中 %d/%d (%d%%)    完美一击 %d    击倒 %d    DPS(5s) %d" % [
		stats["basic_hit"], bf, 100 * int(stats["basic_hit"]) / maxi(bf, 1), stats["snipe_hit"], sf, 100 * int(stats["snipe_hit"]) / maxi(sf, 1),
		stats["perfect"], stats["kills"], int(dps)]
	for k in ["q", "e", "r"]:
		var cd: float = sniper.cds[k]
		var l: Label = skill_lbls[k]
		var base: String = {"q": "Q 战术翻滚", "e": "E 震爆雷", "r": "R 天穹之眼"}[k]
		if k == "r" and sniper.eye_on():
			l.text = "%s  %.1f" % [base, sniper.eye_t]
			l.label_settings.font_color = Color(1.0, 0.85, 0.3)
		elif cd > 0.0:
			l.text = "%s  %.1f" % [base, cd]
			l.label_settings.font_color = Color(0.5, 0.5, 0.6)
		else:
			l.text = base
			l.label_settings.font_color = Color(0.7, 1.0, 1.0)
	var rl: Label = skill_lbls["rmb"]
	if sniper.charging:
		rl.text = "蓄力 %d%%" % int(sniper.charge * 100.0)
		rl.label_settings.font_color = Color(1.0, 0.85, 0.3) if sniper.charge >= 1.0 else Color(1.0, 0.5, 0.5)
	elif sniper.snipe_cd > 0.0:
		rl.text = "右键 蓄力狙击  %.1f" % sniper.snipe_cd
		rl.label_settings.font_color = Color(0.5, 0.5, 0.6)
	else:
		rl.text = "右键 蓄力狙击"
		rl.label_settings.font_color = Color(0.7, 1.0, 1.0)
	toast_t = maxf(0.0, toast_t - d)
	toast_lbl.text = toast_text if toast_t > 0.0 else ""

# ------------------------------------------------------------ drawing (grid, field, bullets, mines, fx, crosshair)
func _draw() -> void:
	var z := cam.zoom.x
	var half := Vector2(680, 400) / z
	var cc := cam.get_screen_center_position()
	var step := 64.0
	var gc := Color(0.2, 0.4, 1.0, 0.16)
	var x := floorf((cc.x - half.x) / step) * step
	while x < cc.x + half.x:
		var major := posmod(int(roundf(x / step)), 4) == 0
		draw_line(Vector2(x, cc.y - half.y), Vector2(x, cc.y + half.y), gc * Color(1, 1, 1, 2.0 if major else 1.0), 2.0 if major else 1.0)
		x += step
	var y := floorf((cc.y - half.y) / step) * step
	while y < cc.y + half.y:
		var major2 := posmod(int(roundf(y / step)), 4) == 0
		draw_line(Vector2(cc.x - half.x, y), Vector2(cc.x + half.x, y), gc * Color(1, 1, 1, 2.0 if major2 else 1.0), 2.0 if major2 else 1.0)
		y += step
	draw_rect(FIELD, Color(0.6, 1.2, 2.4, 0.9), false, 6.0)
	# mines in flight
	for m in mines:
		var k: float = float(m["t"]) / float(m["fly"])
		var p: Vector2 = (m["from"] as Vector2).lerp(m["to"], k) + Vector2(0, -sin(k * PI) * 90.0)
		draw_circle(p, 8.0, Color(0.6, 1.6, 2.8))
		draw_arc(m["to"], SniperT.MINE_R, 0, TAU, 48, Color(0.6, 1.4, 2.8, 0.5), 2.0)
	# bullets
	for b in bullets:
		var bp: Vector2 = b["pos"]
		var tail: Vector2 = bp - (b["vel"] as Vector2).normalized() * (60.0 if b["kind"] in ["snipe", "perfect"] else 22.0)
		var bc := Color(0.6, 2.2, 2.6)
		match b["kind"]:
			"loaded": bc = Color(2.8, 2.0, 0.6)
			"snipe": bc = Color(2.6, 0.6, 0.7)
			"perfect": bc = Color(3.2, 2.6, 0.8)
		draw_line(tail, bp, bc, float(b["r"]))
		draw_circle(bp, float(b["r"]) * 0.7, Color(3, 3, 3))
	# fx
	for f in fx:
		var k2: float = float(f["t"]) / float(f["life"])
		match f["type"]:
			"ring":
				var rc: Color = f["col"]
				draw_arc(f["pos"], float(f["r"]) * (0.5 + 0.5 * k2), 0, TAU, 40, Color(rc.r, rc.g, rc.b, 1.0 - k2), 3.0)
			"trail":
				var tc := Color(3.0, 2.4, 0.7) if f["kind"] == "perfect" else (Color(2.6, 0.6, 0.7) if f["kind"] == "snipe" else Color(0.6, 2.0, 2.4))
				draw_line(f["a"], f["b"], Color(tc.r, tc.g, tc.b, 0.8 * (1.0 - k2)), float(f["w"]) * (1.0 - k2) + 1.0)
			"num":
				var big: bool = f["big"]
				var col := Color(3.0, 2.4, 0.6, 1.0 - k2) if big else Color(1, 1, 1, 1.0 - k2)
				draw_string(font, (f["pos"] as Vector2) + Vector2(0, -30.0 * k2), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26 if big else 17, col)
	# crosshair at the cursor (OS cursor is hidden); scale with zoom so it keeps its screen size
	var mp := get_global_mouse_position()
	var s := 1.0 / z
	var spread: float = 14.0 if not sniper.charging else lerpf(16.0, 3.0, sniper.charge)
	var chc := Color(1.6, 2.2, 2.4, 0.9) if not sniper.charging else (Color(3.0, 2.4, 0.6) if sniper.charge >= 1.0 else Color(2.4, 0.6, 0.6))
	for a in 4:
		var dv := Vector2.from_angle(a * PI / 2.0)
		draw_line(mp + dv * (spread * s), mp + dv * ((spread + 9.0) * s), chc, 2.0 * s)
	draw_circle(mp, 2.0 * s, chc)
	if sniper.atk_cd > 0.0 and not sniper.charging:
		draw_arc(mp, 22.0 * s, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - sniper.atk_cd / SniperT.ATK_INTERVAL), 24, Color(1, 1, 1, 0.35), 1.5 * s)
