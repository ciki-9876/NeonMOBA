extends Node2D
## World presentation: effects, audio, camera, world drawing. Optional: the match runs without it.
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

const HudT = preload("res://ui/hud.gd")
var hd: HudT
const ShopUIT = preload("res://ui/shop_ui.gd")
var shp: ShopUIT
const MenusT = preload("res://ui/menus.gd")
var mnu: MenusT
const PlayerInputT = preload("res://input/player_input.gd")
var inp: PlayerInputT
## main.gd (composition root)
var app: Node = null

var SND := {}
## cosmetic randomness only (never the match RNG, so watching a match cannot change its result)
var rng := RandomNumberGenerator.new()
var fade_grad: Gradient
var ui_font: SystemFont
var label_set: LabelSettings
var label_skill: LabelSettings
var label_big: LabelSettings
var grid: Grid
var floor_layer: Node2D
var fx: Node2D
var overlay: Node2D
var cam: Camera2D
var popups := 0
var snd_cd := {}
var _heal_label: LabelSettings
var sfx_players: Array = []
var sfx_i := 0
var music: AudioStreamPlayer
func _load_view_assets() -> void:
	for n in ["shoot", "hit", "explode", "boom", "pickup", "levelup", "hurt", "dash", "select", "zap", "warning", "music",
			"attack", "ahit", "lance", "blink", "nova", "chain", "singularity", "collapse", "learn", "deny", "slam",
			"whistle", "silence", "mend", "fuse", "rune", "boss"]:
		SND[n] = load("res://sfx/%s.wav" % n)
	fade_grad = Gradient.new()
	fade_grad.set_color(0, Color(1, 1, 1, 1))
	fade_grad.set_color(1, Color(1, 1, 1, 0))
	label_set = _ls(18, Color.WHITE)
	label_skill = _ls(24, Color(0.6, 1.0, 1.0))
	label_big = _ls(32, Color(1.0, 0.9, 0.35))

func _ls(size: int, col: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = ui_font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(4, size / 5)
	ls.outline_color = Color(0.02, 0.0, 0.08, 0.95)
	return ls

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

func _build_audio() -> void:
	for i in 22:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)
	music = AudioStreamPlayer.new()
	music.stream = SND["music"]
	music.volume_db = -11.0
	add_child(music)
	music.finished.connect(music.play)
	music.play()

func sfx(n: String, pitch := 1.0, vol := 0.0, min_gap := 0.0) -> void:
	if gm.sfx_origin != Vector2.INF:
		var dist := gm.sfx_origin.distance_to(cam.get_screen_center_position())
		if dist > 1000.0:
			return
		vol -= dist / 120.0
	if min_gap > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if snd_cd.get(n, 0.0) > now:
			return
		snd_cd[n] = now + min_gap
	var p: AudioStreamPlayer = sfx_players[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_players.size()
	p.stream = SND[n]
	p.pitch_scale = pitch
	p.volume_db = vol
	p.play()

func add_shake(v: float, src) -> void:
	if src != null and is_instance_valid(src) and not src.is_player:
		if src.position.distance_to(cam.get_screen_center_position()) > 700.0:
			return
		v *= 0.5
	gm.shake = maxf(gm.shake, v)

## 3C melee: the swing sweeps the whole arc in front of the hero
func swing_fx(h, dir: Vector2, strong: bool) -> void:
	var col: Color = Color(2.6, 0.5, 0.6) if strong else Color(h.def["col"])
	var reach: float = h.melee_reach()
	var arc: float = h.melee_arc()
	var base: float = dir.angle()
	for ring in 2:
		var l := Line2D.new()
		l.width = 6.0 if ring == 0 else 3.0
		l.default_color = Color(col.r, col.g, col.b, 0.9 if ring == 0 else 0.5)
		var r: float = reach * (1.0 if ring == 0 else 0.7)
		for i in 13:
			var a := base - arc / 2.0 + arc * i / 12.0
			l.add_point(h.position + Vector2.from_angle(a) * r)
		fx.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, 0.2)
		tw.tween_callback(l.queue_free)
	sfx("ahit", rng.randf_range(0.6, 0.75), -8.0, 0.04)

func _draw_bolts(o: Node2D) -> void:
	for b in gm.bolts:
		var ow = b["owner"]
		var col := Color(0.6, 2.2, 2.6) if int(b["team"]) == _viewer() else Color(2.6, 0.7, 0.6)
		if ow != null and is_instance_valid(ow) and ow.is_player:
			col = Color(0.6, 2.6, 2.8)
		var p: Vector2 = b["pos"]
		var tail: Vector2 = p - (b["dir"] as Vector2) * 26.0
		o.draw_line(tail, p, col, 5.0)
		o.draw_circle(p, 4.0, Color(3, 3, 3))

## the player's aim: crosshair line toward the cursor up to the basic attack's reach; charge line for charge skills
func _draw_aim(o: Node2D, h) -> void:
	var dir := Vector2.from_angle(h.face)
	if h.charging != "":
		var cfg: Dictionary = h.charge_cfg()
		var lc := Color(3.0, 2.4, 0.6, 0.9) if h.charge >= 1.0 else Color(2.6, 0.6, 0.5, 0.3 + 0.5 * h.charge)
		o.draw_line(h.position + dir * (h.radius + 10.0), h.position + dir * float(h.kit.ai_meta(h.charging).get("reach", 800.0)) * lerpf(0.8, 1.4, h.charge) / 1.4, lc, 1.0 + 2.0 * h.charge)
		return
	if bool(h.def["melee"]):
		var ma: float = h.melee_arc()
		o.draw_arc(h.position, h.melee_reach(), h.face - ma / 2.0, h.face + ma / 2.0, 20, Color(1, 1, 1, 0.12), 1.5)
	else:
		var r: float = h.bolt_reach()
		o.draw_line(h.position + dir * (h.radius + 10.0), h.position + dir * r, Color(0.6, 2.0, 2.4, 0.18), 1.5)
		o.draw_arc(h.position, h.atk_range(), h.face - 0.25, h.face + 0.25, 8, Color(0.6, 2.0, 2.4, 0.35), 2.0)

## camera: centred on the player with a look-ahead toward the cursor; its height follows the hero's vision
## (more vision = higher camera, capped) and charge skills pull it back further while charging
var _zoom := 1.0
func _update_camera(delta: float) -> void:
	var h = gm.player
	if h == null:
		return
	var target_z := 1.0
	var look := Vector2.ZERO
	if gm.mode == C.M.ROUNDS:
		target_z = clampf(360.0 / (h.vision() * 0.6), 0.55, 1.0)
		if h.charging != "":
			var cz: float = float(h.charge_cfg().get("zoom", 1.0))
			target_z = maxf(0.45, target_z * lerpf(1.0, cz, h.charge))
		if not h.dead:
			look = ((cam.get_global_mouse_position() - h.position) * 0.18).limit_length(160.0)
	var rate := 8.0 if target_z < _zoom else 4.0
	_zoom = lerpf(_zoom, target_z, 1.0 - exp(-rate * delta))
	cam.zoom = Vector2(_zoom, _zoom)
	if not h.dead:
		var tp: Vector2 = h.position + look + (Vector2(0, 70) if gm.mode != C.M.ROUNDS else Vector2.ZERO)
		cam.position = cam.position.lerp(tp, 1.0 - exp(-10.0 * delta)) if gm.mode == C.M.ROUNDS else tp

func slash_fx(h, tgt, strong: bool) -> void:
	var col: Color = Color(2.6, 0.5, 0.6) if strong else Color(2.2, 1.6, 1.8)
	var l := Line2D.new()
	l.width = 5.0 if strong else 3.0
	l.default_color = col
	var base: float = (tgt.position - h.position).angle()
	var r: float = h.radius + 26.0
	for i in 9:
		var a := base - 0.9 + 1.8 * i / 8.0
		l.add_point(h.position + Vector2.from_angle(a) * r)
	fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.18)
	tw.tween_callback(l.queue_free)
	sfx("ahit", rng.randf_range(0.6, 0.75), -6.0, 0.04)

func x_slash_fx(p: Vector2, col: Color) -> void:
	for k in 2:
		var l := Line2D.new()
		l.width = 6.0
		l.default_color = col
		var d := Vector2(26, -26) if k == 0 else Vector2(26, 26)
		l.add_point(p - d)
		l.add_point(p + d)
		fx.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "width", 0.0, 0.3)
		tw.tween_callback(l.queue_free)

func beam_fx(a: Vector2, b: Vector2, col: Color, scl := 1.0) -> void:
	for k in 3:
		var l := Line2D.new()
		l.width = [44.0, 22.0, 8.0][k] * scl
		l.default_color = [Color(col.r * 0.5, col.g * 0.5, col.b * 0.6, 0.35), Color(col.r, col.g, col.b, 0.8), Color(3, 3, 3, 1)][k]
		l.add_point(a)
		l.add_point(b)
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		fx.add_child(l)
		var tw := l.create_tween()
		tw.tween_property(l, "width", 0.0, 0.32)
		tw.tween_callback(l.queue_free)
	for i in 8:
		_burst(a.lerp(b, i / 7.0), col, 6, 220.0, 0.35, 2.5)

func ghost(h, p: Vector2, col: Color) -> void:
	var gs := Sprite2D.new()
	gs.texture = gm.TEX[str(h.def["sprite"]) + "_0"]
	gs.scale = Vector2(C.PIX, C.PIX)
	gs.rotation = h.face
	gs.position = p
	gs.modulate = col
	fx.add_child(gs)
	var tw := gs.create_tween()
	tw.tween_property(gs, "modulate:a", 0.0, 0.4)
	tw.tween_callback(gs.queue_free)

var _crit_label: LabelSettings
func _crit_ls() -> LabelSettings:
	if _crit_label == null:
		_crit_label = _ls(30, Color(1.0, 0.25, 0.2))
	return _crit_label

var _gold_label: LabelSettings
func _gold_ls() -> LabelSettings:
	if _gold_label == null:
		_gold_label = _ls(16, Color(1.0, 0.82, 0.2))
	return _gold_label

var _chain_label: LabelSettings
func _chain_ls() -> LabelSettings:
	if _chain_label == null:
		_chain_label = _ls(20, Color(1.0, 0.95, 0.4))
	return _chain_label

# ============================================================ drawing
func _draw_floor() -> void:
	if gm.mode == C.M.SURVIVAL or gm.state == C.S.MENU or gm.state == C.S.SELECT:
		return
	if gm.mode == C.M.ROUNDS:
		_draw_rounds_floor()
		return
	var o := floor_layer
	o.draw_circle(Vector2.ZERO, C.ARENA_R, Color(0.05, 0.03, 0.12, 0.55))
	o.draw_arc(Vector2.ZERO, C.ARENA_R, 0, TAU, 160, Color(0.6, 1.2, 2.4, 0.9), 6.0)
	o.draw_arc(Vector2.ZERO, C.ARENA_R + 14.0, 0, TAU, 160, Color(1.6, 0.4, 2.0, 0.5), 2.0)
	o.draw_arc(Vector2.ZERO, 260.0, 0, TAU, 64, Color(0.6, 0.8, 1.6, 0.35), 2.0)
	for tm in 2:
		var hp := gm.home_pos(tm)
		var c := Color(0.3, 1.6, 1.2) if tm == 0 else Color(2.0, 0.4, 0.4)
		o.draw_circle(hp, C.FOUNTAIN_R, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.35))
		o.draw_arc(hp, C.FOUNTAIN_R, 0, TAU, 64, Color(c.r, c.g, c.b, 0.8), 3.0)
		o.draw_arc(hp, 40.0, 0, TAU, 32, c, 4.0)
	for spot in C.RUNE_SPOTS:
		o.draw_arc(spot, 46.0, 0, TAU, 32, Color(1.4, 1.4, 0.6, 0.5), 2.0)

func _draw_minimap() -> void:
	if gm.mode == C.M.SURVIVAL or gm.state == C.S.MENU:
		return
	var m := hd.minimap
	var c := Vector2(92, 92)
	var k := 86.0 / C.ARENA_R
	m.draw_circle(c, 90.0, Color(0.03, 0.02, 0.08, 0.85))
	m.draw_arc(c, 88.0, 0, TAU, 64, Color(0.5, 1.0, 2.0, 0.8), 2.0)
	for tm in 2:
		m.draw_circle(c + gm.home_pos(tm) * k, C.FOUNTAIN_R * k, Color(0.3, 1.4, 1.0, 0.4) if tm == 0 else Color(1.6, 0.3, 0.3, 0.4))
	if gm.rounds != null:
		m.draw_arc(c + gm.rounds.core_pos() * k, gm.rounds.CORE_R * k, 0, TAU, 24, Color(1.8, 1.8, 1.8, 0.9) if gm.rounds.core_open() else Color(0.6, 0.6, 0.8, 0.6), 2.0)
	for r in gm.runes:
		m.draw_circle(c + r.position * k, 3.0, Color(1.6, 1.6, 0.6))
	if gm.terrain != null:
		for b in gm.terrain.brush:
			m.draw_circle(c + b[0] * k, float(b[1]) * k, Color(0.2, 0.9, 0.4, 0.35))
		for pl in gm.terrain.circles:
			m.draw_circle(c + pl[0] * k, maxf(2.0, float(pl[1]) * k), Color(0.7, 0.75, 1.0, 0.9))
		for rc in gm.terrain.rects:
			m.draw_rect(Rect2(c + rc.position * k, rc.size * k), Color(0.7, 0.75, 1.0, 0.9))
	for h in gm.heroes:
		if h.dead or not _seen(h): continue
		var col: Color = h.team_color()
		m.draw_circle(c + h.position * k, 5.0 if h.is_player else 3.5, col)
		if h.is_player:
			m.draw_arc(c + h.position * k, 7.0, 0, TAU, 16, Color.WHITE, 1.5)
	var vr := Rect2(c + (cam.get_screen_center_position() - Vector2(640, 360) / cam.zoom.x) * k, Vector2(1280, 720) / cam.zoom.x * k)
	m.draw_rect(vr, Color(1, 1, 1, 0.5), false, 1.0)

func _draw_overlay() -> void:
	if gm.state == C.S.MENU or gm.state == C.S.SELECT: return
	var o := overlay
	var tick := Time.get_ticks_msec() * 0.001
	if gm.rounds != null:
		_draw_rounds_overlay(o, tick)
	for z in gm.zones:
		var p: Vector2 = z["pos"]
		var r: float = z["r"]
		var k: float = clampf(z["t"] / z["delay"], 0.0, 1.0)
		var col: Color = {"artillery": Color(1.0, 0.5, 0.1), "slam": Color(1.0, 0.3, 0.2), "silence": Color(0.75, 0.3, 1.0)}[z["type"]]
		o.draw_circle(p, r, Color(col.r, col.g, col.b, 0.12))
		o.draw_circle(p, r * k, Color(col.r, col.g, col.b, 0.22))
		o.draw_arc(p, r, 0, TAU, 48, Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.9), 2.5)
		if z["type"] == "artillery":
			var src: Vector2 = z.get("src", p)
			var sp := src.lerp(p, k) + Vector2(0, -sin(k * PI) * 160.0)
			o.draw_texture_rect(gm.TEX["shell"], Rect2(sp - Vector2(12, 12), Vector2(24, 24)), false, Color(2, 1.6, 1))
	for e in gm.enemies:
		if e.dead: continue
		if e.aura != "":
			var ac := Color(1.0, 0.25, 0.35, 0.38) if e.aura == "frenzy" else Color(0.3, 0.65, 1.0, 0.38)
			o.draw_arc(e.position, 280.0, tick * 0.6, tick * 0.6 + TAU, 64, ac, 1.5)
			o.draw_circle(e.position, 280.0, Color(ac.r, ac.g, ac.b, 0.025))
		elif e.kind == "mender":
			o.draw_arc(e.position, 260.0, 0, TAU, 48, Color(0.4, 1.0, 0.6, 0.25), 1.5)
	for h in gm.heroes:
		if _seen(h):
			h.kit.draw(o)
	var half_view: Vector2 = Vector2(700, 420) / cam.zoom.x
	var view := Rect2(cam.get_screen_center_position() - half_view, half_view * 2.0)
	_draw_bolts(o)
	# heroes: team rings, windup / backswing / cast feedback, bars
	for h in gm.heroes:
		if h.dead or not view.has_point(h.position) or not _seen(h): continue
		_draw_hero(o, h, tick)
	if inp.selected != null and is_instance_valid(inp.selected) and inp.selected != gm.player and not inp.selected.dead:
		o.draw_arc(inp.selected.position, inp.selected.radius + 10.0, 0, TAU, 32, Color(1.0, 0.85, 0.3, 0.9), 2.5)
	if gm.player != null and not gm.player.dead and gm.mode == C.M.ROUNDS:
		_draw_aim(o, gm.player)
	for e in gm.enemies:
		if e.dead or not view.has_point(e.position): continue
		var w := clampf(e.radius * 2.2, 36.0, 220.0)
		var top: Vector2 = e.position + Vector2(-w / 2.0, -e.radius - 18.0)
		o.draw_rect(Rect2(top, Vector2(w, 6)), Color(0, 0, 0, 0.75))
		o.draw_rect(Rect2(top + Vector2(1, 1), Vector2((w - 2) * clampf(e.hp / e.max_hp, 0.0, 1.0), 4)), Color(1.0, 0.82, 0.25) if e.elite else Color(0.95, 0.2, 0.2))
		if e.shield:
			o.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 8)), Color(0.4, 0.8, 1.6), false, 1.0)
		if e.frenzy:
			o.draw_rect(Rect2(top + Vector2(0, 7), Vector2(w, 2)), Color(1.6, 0.3, 0.4))
		_draw_status(o, e, top, w, tick)
		if e.kind == "bomber" and e.phase == 1:
			o.draw_arc(e.position, 140.0, 0, TAU, 32, Color(1.6, 0.9, 0.2, 0.7), 2.0)
	if inp.marker_t > 0.0:
		var mk := inp.marker_t / 0.45
		o.draw_arc(inp.marker_pos, 18.0 * mk + 4.0, 0, TAU, 24, Color(inp.marker_col.r, inp.marker_col.g, inp.marker_col.b, mk), 2.5)
	if gm.state == C.S.PLAY and inp.targeting != "" and gm.player != null and not gm.player.dead:
		_draw_targeting(o)

func _draw_status(o: Node2D, u, top: Vector2, w: float, tick: float) -> void:
	var x := w + 3.0
	if u.charged > 0.0:
		o.draw_texture_rect(gm.TEX["charge"], Rect2(top + Vector2(x, -4), Vector2(14, 14)), false, Color(1.6, 2.2, 2.4))
		x += 16.0
	if u.mark > 0.0:
		o.draw_texture_rect(gm.TEX["mark"], Rect2(top + Vector2(x, -5), Vector2(16, 16)), false, Color(2.4, 0.6, 0.7))
		x += 18.0
	if u.silence > 0.0:
		o.draw_texture_rect(gm.TEX["silence"], Rect2(top + Vector2(x, -6), Vector2(16, 16)), false)
	if u.has_buff("root"):
		o.draw_arc(u.position, u.radius + 6.0, tick * 3.0, tick * 3.0 + TAU * 0.8, 20, Color(1.2, 0.9, 2.4, 0.9), 3.0)
		o.draw_arc(u.position, u.radius + 10.0, -tick * 3.0, -tick * 3.0 + TAU * 0.6, 20, Color(1.0, 0.7, 2.0, 0.7), 2.0)
	if u.has_buff("taunt"):
		o.draw_string(ui_font, u.position + Vector2(-6, -u.radius - 40.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(2.6, 0.6, 0.3))
	if u.has_buff("banish"):
		o.draw_circle(u.position, u.radius + 14.0, Color(1.2, 0.9, 2.4, 0.25))
		o.draw_arc(u.position, u.radius + 14.0, tick * 2.0, tick * 2.0 + TAU, 32, Color(2.0, 1.6, 2.8, 0.9), 2.0)
	if u.barrier > 0.0:
		o.draw_arc(u.position, u.radius + 12.0, 0, TAU, 32, Color(0.7, 1.6, 2.6, 0.75), 3.0)
	if u.has_buff("dr"):
		o.draw_arc(u.position, u.radius + 16.0, 0, TAU, 32, Color(2.2, 1.8, 0.6, 0.35), 1.5)
	if u.stun > 0.0:
		for i in 3:
			var a: float = tick * 6.0 + i * TAU / 3.0
			o.draw_texture_rect(gm.TEX["stun"], Rect2(u.position + Vector2(cos(a) * 16.0 - 9.0, -u.radius - 34.0 + sin(a) * 5.0), Vector2(18, 18)), false)

func _draw_hero(o: Node2D, h, tick: float) -> void:
	var tc: Color = h.team_color()
	var pos: Vector2 = h.position
	var alpha := 1.0 if h.is_player else 0.6
	o.draw_arc(pos, h.radius + 10.0, 0, TAU, 32, Color(tc.r, tc.g, tc.b, 0.55), 2.0)
	var fdir := Vector2.from_angle(h.face)
	var nose: Vector2 = pos + fdir * (h.radius + 8.0)
	if h.atk_phase == 1:
		var k: float = clampf(1.0 - h.atk_t / maxf(h.atk_total, 0.01), 0.0, 1.0)
		var wc := Color(0.5, 2.2, 2.6, 0.95 * alpha) if h.team == 0 else Color(2.6, 0.7, 0.6, 0.95 * alpha)
		o.draw_arc(pos, h.radius + 18.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, wc, 3.5)
		o.draw_circle(nose, 2.0 + 7.0 * k, Color(wc.r, wc.g, wc.b, (0.35 + 0.6 * k) * alpha))
		if bool(h.def["melee"]):
			var ma: float = h.melee_arc()
			o.draw_arc(pos, h.melee_reach() * (0.6 + 0.4 * k), h.face - ma / 2.0, h.face + ma / 2.0, 24, Color(wc.r, wc.g, wc.b, (0.15 + 0.4 * k) * alpha), 2.0)
	elif h.atk_phase == 2:
		var k2: float = clampf(h.atk_t / maxf(h.atk_bs_total, 0.01), 0.0, 1.0)
		o.draw_arc(pos, h.radius + 18.0, -PI / 2.0, -PI / 2.0 + TAU * k2, 40, Color(0.75, 0.75, 0.85, 0.5 * alpha), 2.0)
	if h.charging != "":
		var chc: Color = Color(3.0, 2.4, 0.6) if h.charge >= 1.0 else Color(h.def["col"])
		o.draw_arc(pos, h.radius + 22.0, -PI / 2.0, -PI / 2.0 + TAU * h.charge, 40, chc, 4.0)
	if h.casting() and h.cast_t > 0.0:
		var kc: float = clampf(1.0 - h.cast_t / maxf(h.cast_point_total(), 0.01), 0.0, 1.0)
		var cc: Color = h.def["col"]
		o.draw_arc(pos, h.radius + 22.0, -PI / 2.0, -PI / 2.0 + TAU * kc, 40, cc, 4.0)
		o.draw_circle(nose, 3.0 + 9.0 * kc, Color(cc.r, cc.g, cc.b, 0.5 + 0.5 * kc))
		if not h.is_player:
			o.draw_string(ui_font, pos + Vector2(-40, h.radius + 40.0), str(h.sdef[h.cast_skill]["name"]), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(cc.r, cc.g, cc.b, 0.9))
	var rad: Array = h.sp().get("radiance", [])
	if not rad.is_empty():
		o.draw_arc(pos, float(rad[1]), 0, TAU, 96, Color(1.6, 0.9, 0.3, 0.2), 2.0)
	if h.is_player and gm.mode == C.M.SURVIVAL:
		return
	# bars
	var w := 70.0
	var top: Vector2 = pos + Vector2(-w / 2.0, -h.radius - 30.0)
	o.draw_rect(Rect2(top - Vector2(1, 1), Vector2(w + 2, 11)), Color(0, 0, 0, 0.8))
	var hc := Color(0.3, 1.0, 0.4) if h.team == 0 else Color(1.0, 0.25, 0.25)
	if h.is_player: hc = Color(0.35, 1.1, 1.2)
	var hpw: float = w * clampf(h.hp / h.max_hp, 0.0, 1.0)
	o.draw_rect(Rect2(top, Vector2(hpw, 6)), hc)
	if h.barrier > 0.0:
		o.draw_rect(Rect2(top + Vector2(hpw, 0), Vector2(minf(w - hpw + 8.0, w * h.barrier / h.max_hp), 6)), Color(0.9, 1.6, 2.4))
	o.draw_rect(Rect2(top + Vector2(0, 7), Vector2(w * clampf(h.mana / h.mana_max, 0.0, 1.0), 2)), Color(0.3, 0.5, 1.2))
	o.draw_string(ui_font, top + Vector2(-20, 8), str(h.level), HORIZONTAL_ALIGNMENT_RIGHT, 16, 12, Color(1.0, 0.9, 0.4))
	if not h.is_player:
		o.draw_string(ui_font, top + Vector2(0, -4), h.display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(hc.r, hc.g, hc.b, 0.9))
	_draw_status(o, h, top, w, tick)

func _draw_targeting(o: Node2D) -> void:
	var mp := get_global_mouse_position()
	var pp: Vector2 = gm.player.position
	if inp.targeting == "attack":
		o.draw_arc(pp, gm.player.atk_range(), 0, TAU, 96, Color(1.0, 0.3, 0.3, 0.35), 1.5)
		o.draw_arc(mp, 14.0, 0, TAU, 24, Color(1.0, 0.3, 0.3, 0.9), 2.0)
		o.draw_line(mp + Vector2(-20, 0), mp + Vector2(20, 0), Color(1.0, 0.3, 0.3, 0.9), 2.0)
		o.draw_line(mp + Vector2(0, -20), mp + Vector2(0, 20), Color(1.0, 0.3, 0.3, 0.9), 2.0)
		return
	var st: Dictionary = gm.player.sdef[inp.targeting]
	var col: Color = gm.player.def["col"]
	var ind: String = st.get("ind", "circle")
	var cast_b: float = float(gm.player.ST.get("cast", 0.0))
	match ind:
		"line":
			var dir := (mp - pp).normalized()
			var n: Vector2 = dir.orthogonal() * float(st["width"]) / 2.0
			var ln: float = 0.0 if st.get("range", 0.0) is Array else float(st.get("range", 0.0))
			if ln <= 0.0:
				ln = float(gm.player.kit.ai_meta(inp.targeting).get("reach", 800.0))
			var b: Vector2 = pp + dir * ln
			o.draw_colored_polygon(PackedVector2Array([pp + n, b + n, b - n, pp - n]), Color(col.r * 0.3, col.g * 0.4, col.b * 0.4, 0.18))
			o.draw_polyline(PackedVector2Array([pp + n, b + n, b - n, pp - n, pp + n]), Color(col.r, col.g, col.b, 0.8), 2.0)
		"blink":
			var maxd: float = gm.player.sv(inp.targeting, "dist") + cast_b
			var dest := pp + (mp - pp).limit_length(maxd)
			var r: float = float(st["radius"])
			o.draw_arc(pp, maxd, 0, TAU, 96, Color(1.0, 0.4, 0.9, 0.35), 1.5)
			o.draw_circle(dest, r, Color(1.0, 0.3, 0.9, 0.12))
			o.draw_arc(dest, r, 0, TAU, 64, Color(1.8, 0.5, 1.6, 0.8), 2.0)
		"dash":
			var maxd2: float = gm.player.sv(inp.targeting, "dist") + cast_b
			var u = inp._unit_at(mp, true)
			var dest2: Vector2 = u.position if u != null else pp + (mp - pp).limit_length(maxd2)
			var w2: float = float(st["width"]) / 2.0
			var dir2 := (dest2 - pp).normalized()
			var n2 := dir2.orthogonal() * w2
			o.draw_arc(pp, maxd2, 0, TAU, 96, Color(col.r, col.g, col.b, 0.3), 1.5)
			o.draw_colored_polygon(PackedVector2Array([pp + n2, dest2 + n2, dest2 - n2, pp - n2]), Color(1.0, 0.2, 0.3, 0.16))
			o.draw_polyline(PackedVector2Array([pp + n2, dest2 + n2, dest2 - n2, pp - n2, pp + n2]), Color(col.r, col.g, col.b, 0.8), 2.0)
			if u != null:
				o.draw_arc(u.position, u.radius + 12.0, 0, TAU, 24, Color(2.4, 0.5, 0.6), 3.0)
		"ally":
			var cra: float = float(gm.player.kit.cast_range(inp.targeting, null))
			o.draw_arc(pp, cra, 0, TAU, 96, Color(0.4, 1.6, 0.6, 0.35), 1.5)
			var ua = inp._ally_at(mp)
			if ua != null:
				o.draw_arc(ua.position, ua.radius + 12.0, 0, TAU, 24, Color(0.5, 2.4, 0.8), 3.0)
			else:
				o.draw_arc(mp, 16.0, 0, TAU, 24, Color(0.4, 1.6, 0.6, 0.6), 2.0)
		"unit":
			var cr: float = float(gm.player.kit.cast_range(inp.targeting, null))
			o.draw_arc(pp, cr, 0, TAU, 96, Color(col.r, col.g, col.b, 0.35), 1.5)
			var u2 = inp._unit_at(mp, true)
			if u2 != null:
				o.draw_arc(u2.position, u2.radius + 12.0, 0, TAU, 24, Color(2.4, 0.5, 0.6), 3.0)
			else:
				o.draw_arc(mp, 16.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.6), 2.0)
		_:
			var cr2: float = float(gm.player.kit.cast_range(inp.targeting, null))
			var rr: float = float(gm.player.kit.skill_radius(inp.targeting))
			o.draw_arc(pp, cr2, 0, TAU, 96, Color(0.8, 0.4, 1.0, 0.35), 1.5)
			o.draw_circle(mp, rr, Color(0.6, 0.2, 0.9, 0.14))
			o.draw_arc(mp, rr, 0, TAU, 64, Color(1.6, 0.6, 2.0, 0.8), 2.0)

# ============================================================ fx helpers
func _burst(pos: Vector2, col: Color, amount := 14, spd := 300.0, life := 0.5, scl := 3.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = spd * 0.35
	p.initial_velocity_max = spd
	p.damping_min = spd * 0.9
	p.damping_max = spd * 1.4
	p.scale_amount_min = scl * 1.2
	p.scale_amount_max = scl * 2.4
	p.color = col
	p.color_ramp = fade_grad
	p.position = pos
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

func _ring(pos: Vector2, r0: float, r1: float, life: float, col: Color, width: float) -> void:
	var r := Ring.new()
	r.position = pos
	r.r0 = r0
	r.r1 = r1
	r.life = life
	r.col = col
	r.width = width
	fx.add_child(r)

func _bolt(a: Vector2, b: Vector2, col := Color(2.4, 2.2, 0.8)) -> void:
	var l := Line2D.new()
	l.width = 4.0
	l.default_color = col
	var n := 7
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if i > 0 and i < n:
			p += (b - a).orthogonal().normalized() * rng.randf_range(-14, 14)
		l.add_point(p)
	fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.22)
	tw.tween_callback(l.queue_free)

func _popup(pos: Vector2, text: String, style := "set", always := true, jitter := 0.0) -> void:
	if popups >= 50:
		return
	if not always and cam.get_screen_center_position().distance_to(pos) > 700.0:
		return
	var ls: LabelSettings = label_set
	match style:
		"big": ls = label_big
		"skill": ls = label_skill
		"crit": ls = _crit_ls()
		"chain": ls = _chain_ls()
		"gold": ls = _gold_ls()
		"heal":
			if _heal_label == null:
				_heal_label = _ls(20, Color(0.5, 1.0, 0.5))
			ls = _heal_label
	if jitter > 0.0:
		pos.x += rng.randf_range(-jitter, jitter)
	var l := Label.new()
	l.text = text
	l.label_settings = ls
	l.position = pos - Vector2(20, 10)
	fx.add_child(l)
	popups += 1
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 50.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.25)
	tw.chain().tween_callback(_popup_done.bind(l))

func _popup_done(l: Label) -> void:
	popups -= 1
	l.queue_free()

# ============================================================ lifecycle handlers (split from match code)
func _v_world_cleared() -> void:
	for c in fx.get_children():
		c.queue_free()
	popups = 0

func _v_match_started() -> void:
	popups = 0
	cam.position = gm.player.position
	cam.reset_smoothing()
	floor_layer.queue_redraw()

func grid_pulse(v: float) -> void:
	grid.pulse = v

# ============================================================ world nodes & per-frame presentation
## nodes drawn below the match units (grid, arena floor)
func build_below(world: Node2D) -> void:
	rng.randomize()
	grid = Grid.new()
	world.add_child(grid)
	floor_layer = Node2D.new()
	world.add_child(floor_layer)
	floor_layer.draw.connect(_draw_floor)

## nodes drawn above the match units (effects, overlay, camera)
func build_above(world: Node2D) -> void:
	fx = Node2D.new()
	world.add_child(fx)
	overlay = Node2D.new()
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	world.add_child(cam)
	cam.make_current()

## background animation while a menu is open
func menu_frame(delta: float) -> void:
	grid.cam_pos += Vector2(40, 20) * delta
	cam.position = grid.cam_pos
	grid.pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.002)
	grid.queue_redraw()

## camera, shake and redraws after the simulation stepped
## which team the screen shows the world for (the player's; team 0 when spectating)
func _viewer() -> int:
	return gm.player.team if gm.player != null else 0

## brush: enemies the viewer's team can't see are not drawn at all
func _seen(h) -> bool:
	return gm.visible_to(h, _viewer())

func frame(delta: float) -> void:
	if gm.terrain != null:
		var vt := _viewer()
		for h in gm.heroes:
			var vis: bool = gm.visible_to(h, vt)
			h.visible = vis and not h.dead
			# own heroes hiding in brush are drawn translucent
			h.modulate.a = 0.55 if (h.team == vt and not h.dead and gm.terrain.brush_at(h.position) >= 0) else 1.0
	_update_camera(delta)
	cam.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * gm.shake
	grid.cam_pos = cam.get_screen_center_position()
	grid.half = Vector2(1000, 640) / cam.zoom.x
	grid.pulse = maxf(0.0, grid.pulse - delta * 1.5)
	grid.queue_redraw()
	overlay.queue_redraw()
	if gm.mode != C.M.SURVIVAL:
		hd.minimap.queue_redraw()

# ============================================================ round mode drawing
func _draw_rounds_floor() -> void:
	var o := floor_layer
	o.draw_circle(Vector2.ZERO, C.ARENA_R, Color(0.05, 0.03, 0.12, 0.55))
	o.draw_arc(Vector2.ZERO, C.ARENA_R, 0, TAU, 160, Color(0.6, 1.2, 2.4, 0.9), 6.0)
	o.draw_arc(Vector2.ZERO, C.ARENA_R + 14.0, 0, TAU, 160, Color(1.6, 0.4, 2.0, 0.5), 2.0)
	if gm.terrain != null:
		# shadows of the obstacles on the floor (the solid blocks are drawn in the overlay)
		for pl in gm.terrain.circles:
			o.draw_circle(pl[0] + Vector2(10, 14), float(pl[1]), Color(0, 0, 0, 0.45))
		for rc in gm.terrain.rects:
			o.draw_rect(Rect2(rc.position + Vector2(10, 14), rc.size), Color(0, 0, 0, 0.45))
	for tm in 2:
		var hp := gm.home_pos(tm)
		var c := Color(0.3, 1.6, 1.2) if tm == 0 else Color(2.0, 0.4, 0.4)
		o.draw_circle(hp, 170.0, Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.35))
		o.draw_arc(hp, 40.0, 0, TAU, 32, c, 4.0)

## the core: locked (grey) / open (pulsing) with each team's capture arc; spawn walls during the buy phase
func _draw_terrain(o: Node2D, tick: float) -> void:
	var t = gm.terrain
	# brush: soft green patches with swaying blade strokes (drawn over units, so hiding reads clearly)
	for i in t.brush.size():
		var bc: Vector2 = t.brush[i][0]
		var br: float = t.brush[i][1]
		o.draw_circle(bc, br, Color(0.12, 0.55, 0.25, 0.30))
		o.draw_arc(bc, br, 0, TAU, 48, Color(0.3, 1.6, 0.6, 0.55), 2.0)
		var n := int(br / 9.0)
		for k in n:
			var a := TAU * k / float(n) + float(i) * 0.7
			var rr: float = br * (0.25 + 0.7 * fmod(k * 0.618, 1.0))
			var base := bc + Vector2.from_angle(a) * rr
			var sway := sin(tick * 1.8 + k * 1.3) * 3.0
			o.draw_line(base, base + Vector2(sway, -14.0), Color(0.35, 1.5, 0.6, 0.45), 2.0)
	# pillars and walls: solid blocks with a neon rim
	for pl in t.circles:
		o.draw_circle(pl[0], float(pl[1]), Color(0.10, 0.09, 0.20, 1.0))
		o.draw_circle(pl[0], float(pl[1]) * 0.6, Color(0.16, 0.14, 0.30, 1.0))
		o.draw_arc(pl[0], float(pl[1]), 0, TAU, 48, Color(0.8, 1.0, 2.4, 0.95), 3.0)
	for rc in t.rects:
		o.draw_rect(rc, Color(0.10, 0.09, 0.20, 1.0))
		o.draw_rect((rc as Rect2).grow(-10.0), Color(0.16, 0.14, 0.30, 1.0))
		o.draw_rect(rc, Color(0.8, 1.0, 2.4, 0.95), false, 3.0)

func _draw_rounds_overlay(o: Node2D, tick: float) -> void:
	var r = gm.rounds
	if gm.terrain != null:
		_draw_terrain(o, tick)
	var p: Vector2 = r.core_pos()
	var rad: float = r.CORE_R
	if r.core_open():
		var pulse := 0.5 + 0.5 * sin(tick * 4.0)
		o.draw_circle(p, rad, Color(1.4, 1.4, 1.8, 0.06 + 0.04 * pulse))
		o.draw_arc(p, rad, 0, TAU, 96, Color(2.2, 2.2, 2.6, 0.7 + 0.3 * pulse), 3.0)
	else:
		o.draw_circle(p, rad, Color(0.3, 0.3, 0.45, 0.08))
		for i in 24:
			var a0 := TAU * i / 24.0
			o.draw_arc(p, rad, a0, a0 + TAU / 48.0, 4, Color(0.6, 0.6, 0.9, 0.6), 2.0)
		if r.phase == "live":
			var k: float = clampf(r.phase_t / r.CORE_UNLOCK, 0.0, 1.0)
			o.draw_arc(p, rad * 0.35, -PI / 2, -PI / 2 + TAU * k, 48, Color(1.6, 1.6, 2.2, 0.8), 4.0)
	for tm in 2:
		var cap: float = r.capture[tm]
		if cap > 0.0:
			var col := Color(0.3, 1.8, 2.2) if tm == 0 else Color(2.4, 0.4, 0.4)
			o.draw_arc(p, rad + 10.0 + tm * 9.0, -PI / 2, -PI / 2 + TAU * cap, 96, col, 6.0)
	if r.phase == "buy":
		for tm in 2:
			var c := Color(0.3, 1.6, 1.2, 0.8) if tm == 0 else Color(2.0, 0.4, 0.4, 0.8)
			o.draw_arc(gm.home_pos(tm), r.SPAWN_R, 0, TAU, 64, c, 3.0)

