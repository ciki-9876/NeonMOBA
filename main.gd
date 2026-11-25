extends Node2D
## NEON DRIFT v4 — 霓虹漂移
## 两种模式：30 分钟生存（选择英雄）/ 3V3 英雄竞技场（坦克/输出/辅助，玩家 + AI 队友 vs AI 对手）。
## 英雄逻辑在 hero.gd（通用）+ kit_*.gd（技能），AI 在 hero_ai.gd（通用、读取技能元数据）。

const Unit = preload("res://unit.gd")
const Hero = preload("res://hero.gd")
const HeroAI = preload("res://hero_ai.gd")
const TeamAI = preload("res://team_ai.gd")
const HeroesDB = preload("res://heroes_db.gd")
const ItemsDB = preload("res://items_db.gd")

const PIX := 3.0
const CELL := 64.0
const GAME_LEN := 1800.0
const MAX_ENEMIES := 140
const ICON_COLS := 10
const ARENA_R := 1250.0
const FOUNTAIN_R := 250.0
const ARENA_KILLS := 15
const TEAM_SIZE := 3
const RUNE_SPOTS := [Vector2(0, -760), Vector2(0, 760)]
const ARENA_LEN := 900.0

enum S { MENU, SELECT, PLAY, END }
enum M { SURVIVAL, ARENA }

const ATLAS_ROWS := [
	["player", 16, 16, 2], ["heart", 7, 7, 2], ["chaser", 16, 16, 2], ["dasher", 16, 16, 2],
	["splitter", 16, 16, 2], ["mini", 10, 10, 2], ["shooter", 16, 16, 2], ["tank", 26, 26, 2],
	["bullet", 10, 4, 1], ["ebullet", 8, 8, 1], ["spark", 3, 3, 1], ["blade_fx", 12, 12, 1],
]
const ATLAS2_ROWS := [
	["sentry", 18, 18, 2], ["colossus", 32, 32, 2], ["frenzy", 20, 20, 2], ["aegis", 20, 20, 2],
	["mender", 18, 18, 2], ["bomber", 12, 12, 2], ["hexer", 18, 18, 2],
	["icon_q", 32, 32, 1], ["icon_w", 32, 32, 1], ["icon_e", 32, 32, 1], ["icon_r", 32, 32, 1], ["icon_attr", 32, 32, 1],
	["shell", 8, 8, 1], ["stun", 9, 9, 1], ["charge", 7, 7, 1], ["silence", 16, 16, 1],
]
const HERO_ROWS2 := [
	["aegis", 18, 18, 2], ["anchor", 18, 18, 2], ["lumen", 18, 18, 2], ["seer", 18, 18, 2],
	["aegis_q", 32, 32, 1], ["aegis_w", 32, 32, 1], ["aegis_e", 32, 32, 1], ["aegis_r", 32, 32, 1],
	["anchor_q", 32, 32, 1], ["anchor_w", 32, 32, 1], ["anchor_e", 32, 32, 1], ["anchor_r", 32, 32, 1],
	["lumen_q", 32, 32, 1], ["lumen_w", 32, 32, 1], ["lumen_e", 32, 32, 1], ["lumen_r", 32, 32, 1],
	["seer_q", 32, 32, 1], ["seer_w", 32, 32, 1], ["seer_e", 32, 32, 1], ["seer_r", 32, 32, 1],
]
const HERO_ROWS3 := [
	["frost", 18, 18, 2], ["ember", 18, 18, 2], ["tide", 18, 18, 2],
	["frost_q", 32, 32, 1], ["frost_w", 32, 32, 1], ["frost_e", 32, 32, 1], ["frost_r", 32, 32, 1],
	["ember_q", 32, 32, 1], ["ember_w", 32, 32, 1], ["ember_e", 32, 32, 1], ["ember_r", 32, 32, 1],
	["tide_q", 32, 32, 1], ["tide_w", 32, 32, 1], ["tide_e", 32, 32, 1], ["tide_r", 32, 32, 1],
]
const HERO_ROWS := [
	["blade", 18, 18, 2], ["b_icon_q", 32, 32, 1], ["b_icon_w", 32, 32, 1], ["b_icon_e", 32, 32, 1], ["b_icon_r", 32, 32, 1],
	["mark", 9, 9, 1],
]

const EDEF := {
	"grunt": {"name": "爬行者", "spr": "chaser", "hp": 60.0, "spd": 190.0, "r": 18.0, "dmg": 10.0, "rate": 1.2, "range": 34.0, "xp": 4.0, "armor": 0.0, "mr": 0.0, "gold": 5.0, "col": Color(1.0, 0.25, 0.35), "desc": "近战小怪，数量最多。"},
	"dasher": {"name": "突袭者", "spr": "dasher", "hp": 120.0, "spd": 150.0, "r": 18.0, "dmg": 30.0, "rate": 2.0, "range": 34.0, "xp": 6.0, "armor": 1.0, "mr": 0.0, "gold": 8.0, "col": Color(1.0, 0.85, 0.25), "desc": "原地蓄力后高速冲锋，冲锋会造成重击。"},
	"splitter": {"name": "分裂体", "spr": "splitter", "hp": 160.0, "spd": 165.0, "r": 20.0, "dmg": 16.0, "rate": 1.2, "range": 36.0, "xp": 6.0, "armor": 1.0, "mr": 0.0, "gold": 7.0, "col": Color(0.35, 1.0, 0.5), "desc": "死亡时分裂成两个小体。"},
	"mini": {"name": "分裂小体", "spr": "mini", "hp": 45.0, "spd": 250.0, "r": 12.0, "dmg": 8.0, "rate": 1.0, "range": 30.0, "xp": 2.0, "armor": 0.0, "mr": 0.0, "gold": 2.0, "col": Color(0.35, 1.0, 0.5), "desc": "分裂体的碎片，速度很快。"},
	"shooter": {"name": "游击手", "spr": "shooter", "hp": 130.0, "spd": 180.0, "r": 18.0, "dmg": 20.0, "rate": 2.4, "range": 380.0, "xp": 7.0, "armor": 0.0, "mr": 0.0, "gold": 9.0, "col": Color(0.25, 0.6, 1.0), "desc": "射击单位，保持距离射击并边打边退。"},
	"sentry": {"name": "炮台", "spr2": "sentry", "hp": 260.0, "spd": 120.0, "r": 22.0, "dmg": 55.0, "rate": 2.8, "range": 680.0, "xp": 10.0, "armor": 3.0, "mr": 0.1, "gold": 16.0, "col": Color(1.0, 0.55, 0.15), "desc": "长程站桩：架设后炮击你所在的位置，看到地面预警就快走开。"},
	"colossus": {"name": "巨像", "spr2": "colossus", "hp": 1500.0, "spd": 110.0, "r": 44.0, "dmg": 45.0, "rate": 2.2, "range": 60.0, "xp": 32.0, "armor": 8.0, "mr": 0.15, "gold": 45.0, "col": Color(1.0, 0.4, 0.3), "desc": "大体型肉盾：8 点护甲、15% 魔抗。会蓄力砸地，造成范围伤害和减速。"},
	"frenzy": {"name": "狂怒信标", "spr2": "frenzy", "hp": 420.0, "spd": 125.0, "r": 26.0, "dmg": 0.0, "rate": 99.0, "range": 0.0, "xp": 16.0, "armor": 2.0, "mr": 0.1, "gold": 30.0, "col": Color(1.0, 0.2, 0.35), "aura": "frenzy", "desc": "光环（半径 280）：周围对手移速和攻击力 +40%。优先消灭！"},
	"aegis": {"name": "护盾信标", "spr2": "aegis", "hp": 420.0, "spd": 125.0, "r": 26.0, "dmg": 0.0, "rate": 99.0, "range": 0.0, "xp": 16.0, "armor": 2.0, "mr": 0.1, "gold": 30.0, "col": Color(0.3, 0.65, 1.0), "aura": "aegis", "desc": "光环（半径 280）：周围对手护甲 +6、魔法抗性 +30%。物理和魔法输出都会被削弱。"},
	"mender": {"name": "治愈者", "spr2": "mender", "hp": 300.0, "spd": 160.0, "r": 22.0, "dmg": 0.0, "rate": 3.0, "range": 0.0, "xp": 12.0, "armor": 1.0, "mr": 0.1, "gold": 22.0, "col": Color(0.35, 1.0, 0.6), "desc": "每 3 秒为半径 260 内的对手恢复 15% 最大生命。"},
	"bomber": {"name": "自爆虫", "spr2": "bomber", "hp": 60.0, "spd": 330.0, "r": 15.0, "dmg": 110.0, "rate": 99.0, "range": 70.0, "xp": 5.0, "armor": 0.0, "mr": 0.0, "gold": 6.0, "col": Color(1.0, 0.8, 0.2), "desc": "冲到你身边后引爆，爆炸也会炸伤其他对手。"},
	"hexer": {"name": "缄默者", "spr2": "hexer", "hp": 280.0, "spd": 150.0, "r": 22.0, "dmg": 0.0, "rate": 6.0, "range": 520.0, "xp": 12.0, "armor": 1.0, "mr": 0.35, "gold": 22.0, "col": Color(0.75, 0.4, 1.0), "desc": "施放沉默领域：身处其中会被沉默 2.5 秒，无法释放技能。"},
	"boss": {"name": "典狱长", "hp": 9000.0, "spd": 95.0, "r": 92.0, "dmg": 60.0, "rate": 1.5, "range": 100.0, "xp": 600.0, "armor": 5.0, "mr": 0.25, "gold": 0.0, "col": Color(1.0, 0.2, 0.8), "desc": "Boss：发射弹幕环；生命减半后释放螺旋弹幕。"},
}

const EVENTS := [
	[120.0, "swarm"], [300.0, "swarm"], [480.0, "swarm"], [585.0, "warn1"], [600.0, "boss1"],
	[780.0, "swarm"], [960.0, "swarm"], [1140.0, "swarm"], [1185.0, "warn2"], [1200.0, "boss2"],
	[1380.0, "swarm"], [1560.0, "swarm"], [1605.0, "warn3"], [1620.0, "boss3"], [1740.0, "swarm"],
]

# ============================================================ classes
class Enemy extends "res://unit.gd":
	var speed := 100.0
	var dmg := 10.0
	var rate := 1.0
	var arange := 30.0
	var xp := 1.0
	var aura := ""
	var vel := Vector2.ZERO
	var timer := 0.0
	var aux_t := 0.0
	var spin := 0.0
	var phase := 0
	var atk_cd := 0.0
	var aim := Vector2.RIGHT
	var tier := 0
	var elite := false
	var frenzy := false
	var shield := false
	var gold := 0.0
	var spr: Node2D
	func armor_val() -> float:
		var a := armor + (6.0 if shield else 0.0)
		if deso_t > 0.0: a -= deso_v
		return a - ac_v
	func mr_val() -> float:
		return clampf(mr + (0.3 if shield else 0.0), 0.0, 0.9)

class HeroShot extends Node2D:
	var owner_h: Object = null
	var target: Object = null
	var dmg := 0.0
	var info := {}
	var speed := 1100.0
	var dead := false
	var last_pos := Vector2.ZERO

class EShot extends Node2D:
	var vel := Vector2.ZERO
	var dmg := 10.0
	var dtype := "magic"
	var evadable := false
	var life := 5.0
	var dead := false

class Grid extends Node2D:
	var cam_pos := Vector2.ZERO
	var pulse := 0.0
	var tint := Color(0.2, 0.4, 1.0)
	func _draw() -> void:
		var step := 64.0
		var half := Vector2(1000, 640)
		var col := Color(tint.r, tint.g, tint.b, 0.16 + pulse * 0.3)
		var x := floorf((cam_pos.x - half.x) / step) * step
		while x < cam_pos.x + half.x:
			var major := posmod(int(roundf(x / step)), 4) == 0
			draw_line(Vector2(x, cam_pos.y - half.y), Vector2(x, cam_pos.y + half.y), col * Color(1, 1, 1, 2.0 if major else 1.0), 2.0 if major else 1.0)
			x += step
		var y := floorf((cam_pos.y - half.y) / step) * step
		while y < cam_pos.y + half.y:
			var major := posmod(int(roundf(y / step)), 4) == 0
			draw_line(Vector2(cam_pos.x - half.x, y), Vector2(cam_pos.x + half.x, y), col * Color(1, 1, 1, 2.0 if major else 1.0), 2.0 if major else 1.0)
			y += step

class Ring extends Node2D:
	var r0 := 10.0
	var r1 := 120.0
	var life := 0.35
	var t := 0.0
	var col := Color.WHITE
	var width := 6.0
	func _process(d: float) -> void:
		t += d
		queue_redraw()
		if t >= life:
			queue_free()
	func _draw() -> void:
		var k := clampf(t / life, 0.0, 1.0)
		var rr := lerpf(r0, r1, 1.0 - pow(1.0 - k, 3.0))
		var c := col
		c.a = 1.0 - k
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, c, width * (1.0 - k) + 1.0)

# ============================================================ state
var state := S.MENU
var mode := M.SURVIVAL
var paused := false
var rng := RandomNumberGenerator.new()
var TEX := {}
var SND := {}
var boss_frames: SpriteFrames
var gem_frames: SpriteFrames
var fade_grad: Gradient
var ui_font: SystemFont
var label_set: LabelSettings
var label_skill: LabelSettings
var label_big: LabelSettings

var world: Node2D
var grid: Grid
var floor_layer: Node2D
var layer_runes: Node2D
var layer_trails: Node2D
var layer_enemies: Node2D
var layer_heroes: Node2D
var layer_shots: Node2D
var fx: Node2D
var overlay: Node2D
var cam: Camera2D

var player: Hero = null
var heroes: Array = []
var enemies: Array = []
var hshots: Array = []
var eshots: Array = []
var zones: Array = []
var runes: Array = []
var cells := {}
var bosses: Array = []
var seen_kinds := {}
var team0: Array = []

# player control
var targeting := ""
var selected: Node2D = null
var right_held := false
var right_t := 0.0
var marker_pos := Vector2.ZERO
var marker_t := 0.0
var marker_col := Color.GREEN
var god := false
var autopilot := false
var shop_open := false
var shop_tab := "consumable"
var shop_hover := ""
var sfx_origin := Vector2.INF

# run
var t := 0.0
var kills := 0
var best := 0.0
var spawn_acc := 0.0
var event_i := 0
var next_rune := 120.0
var shake := 0.0
var hitstop := 0.0
var popups := 0
var snd_cd := {}
var dead_timer := 0.0
var team_kills := [0, 0]
var first_blood := false
var winner := -1
var difficulty := 1
var brains := {}
var _heal_label: LabelSettings
var last_cfg := {}
var sel_mode := M.SURVIVAL

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
var shop: PanelContainer
var shop_grid: GridContainer
var shop_detail: RichTextLabel
var shop_gold: Label
var shop_tabs := {}
var gold_lbl: Label
var inv_slots: Array = []
var score_rt: RichTextLabel
var board: PanelContainer
var board_rt: RichTextLabel
var minimap: Control
var respawn_lbl: Label
var menu_root: Control
var menu_main: VBoxContainer
var menu_surv: Control
var menu_arena: Control
var arena_opts: Array = []
var diff_opt: OptionButton

var sfx_players: Array = []
var sfx_i := 0
var music: AudioStreamPlayer

# ============================================================ setup
func _ready() -> void:
	rng.randomize()
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	ui_font.font_weight = 600
	ThemeDB.fallback_font = ui_font
	_load_assets()
	_build_env()
	_build_world()
	_build_ui()
	_build_menu()
	_build_audio()
	_load_best()
	_show_menu()

func _slice(path: String, rows: Array) -> void:
	var atlas: Texture2D = load(path)
	var y := 0
	for r in rows:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(0, y, r[1] * r[3], r[2])
		TEX[r[0]] = at
		if r[3] == 2:
			var f0 := AtlasTexture.new()
			f0.atlas = atlas
			f0.region = Rect2(0, y, r[1], r[2])
			TEX[r[0] + "_0"] = f0
		y += r[2] + 1

func _load_assets() -> void:
	_slice("res://art/sprites.png", ATLAS_ROWS)
	_slice("res://art/sprites2.png", ATLAS2_ROWS)
	_slice("res://art/heroes.png", HERO_ROWS)
	_slice("res://art/heroes2.png", HERO_ROWS2)
	_slice("res://art/heroes3.png", HERO_ROWS3)
	var icons: Texture2D = load("res://art/items.png")
	var order: Array = ItemsDB.ORDER
	for i in order.size():
		var at := AtlasTexture.new()
		at.atlas = icons
		at.region = Rect2((i % ICON_COLS) * 24, (i / ICON_COLS) * 24, 24, 24)
		TEX["it_" + str(order[i])] = at
	gem_frames = SpriteFrames.new()
	for i in 8:
		gem_frames.add_frame("default", load("res://art/gem_%d.png" % i))
	gem_frames.set_animation_speed("default", 10.0)
	boss_frames = SpriteFrames.new()
	for i in 16:
		boss_frames.add_frame("default", load("res://art/boss_%02d.png" % i))
	boss_frames.set_animation_speed("default", 14.0)
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

func _build_world() -> void:
	world = Node2D.new()
	add_child(world)
	grid = Grid.new()
	world.add_child(grid)
	floor_layer = Node2D.new()
	world.add_child(floor_layer)
	floor_layer.draw.connect(_draw_floor)
	layer_runes = Node2D.new()
	world.add_child(layer_runes)
	layer_trails = Node2D.new()
	world.add_child(layer_trails)
	layer_enemies = Node2D.new()
	world.add_child(layer_enemies)
	layer_heroes = Node2D.new()
	world.add_child(layer_heroes)
	layer_shots = Node2D.new()
	world.add_child(layer_shots)
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

func _label(size: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.label_settings = _ls(size, col)
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
	score_rt = _rt(30)
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
	minimap.draw.connect(_draw_minimap)
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
	var keys := ["q", "w", "e", "r"]
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
	silence_icon.texture = TEX["silence"]
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

	_build_ui_v3()
	# ---- scoreboard (Tab)
	board = PanelContainer.new()
	_place(board, Control.PRESET_CENTER, -420, -250, 840, 420)
	board.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.02, 0.08, 0.95), Color(0.3, 0.8, 1.0, 0.8)))
	board.visible = false
	hud.add_child(board)
	board_rt = _rt(15)
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
	icon.texture = TEX["icon_attr"] if key == "attr" else TEX["icon_" + key]
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
	kl.text = key.to_upper() if key != "attr" else ""
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
	plus.pressed.connect(_learn.bind(key))
	box.add_child(plus)
	slots[key] = {"box": box, "icon": icon, "cd": cdr, "cdl": cdl, "mana": ml, "pips": pips, "plus": plus, "size": size}

## re-skin the skill bar for the player's hero
func _setup_hud() -> void:
	var icons: Dictionary = player.def["icons"]
	for key in slots:
		var sl: Dictionary = slots[key]
		var size: float = sl["size"]
		var n := 10
		if key != "attr":
			(sl["icon"] as TextureRect).texture = TEX[icons[key]]
			n = int(player.sdef[key]["max"])
			(sl["box"] as Control).tooltip_text = str(player.kit.tip(key))
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

# ============================================================ menus
func _menu_btn(text: String, w: float, h: float, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6))
	b.add_theme_stylebox_override("normal", _panel_style(Color(0.05, 0.04, 0.12, 0.92), Color(0.3, 0.8, 1.0, 0.7)))
	b.add_theme_stylebox_override("hover", _panel_style(Color(0.12, 0.08, 0.22, 0.95), Color(1.0, 0.85, 0.3)))
	b.add_theme_stylebox_override("pressed", _panel_style(Color(0.2, 0.14, 0.05, 0.95), Color(1.0, 0.85, 0.3)))
	return b

func _build_menu() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(menu_root)
	# main
	menu_main = VBoxContainer.new()
	menu_main.add_theme_constant_override("separation", 14)
	_place(menu_main, Control.PRESET_CENTER, -200, 10, 400, 260)
	menu_root.add_child(menu_main)
	var b1 := _menu_btn("生存模式  ·  30 分钟   [1]", 400, 64, 24)
	b1.pressed.connect(_open_select.bind(M.SURVIVAL))
	menu_main.add_child(b1)
	var b2 := _menu_btn("3V3 英雄竞技场   [2]", 400, 64, 24)
	b2.pressed.connect(_open_select.bind(M.ARENA))
	menu_main.add_child(b2)
	var hint := _label(15, Color(0.75, 0.75, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "右键 移动/攻击   A 攻击指令   QWER 技能   Ctrl+QWER 学习\nB 商店（打开时暂停）   C 属性   Tab 计分板   Esc 暂停"
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
	_place(scroll, Control.PRESET_CENTER, -630, -300, 1260, 590)
	menu_surv.add_child(scroll)
	scroll.add_child(cards)
	for id in HeroesDB.ORDER:
		cards.add_child(_hero_card(str(id)))
	var scroll_hint := _label(14, Color(0.7, 0.7, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	scroll_hint.text = "鼠标滚轮上下翻页，共 %d 名英雄" % HeroesDB.ORDER.size()
	_place(scroll_hint, Control.PRESET_CENTER_BOTTOM, -200, -100, 400, 24)
	menu_surv.add_child(scroll_hint)
	var back1 := _menu_btn("返回", 160, 44, 18)
	_place(back1, Control.PRESET_CENTER_BOTTOM, -80, -58, 160, 44)
	back1.pressed.connect(_show_menu)
	menu_surv.add_child(back1)
	# arena: 5v5 setup
	menu_arena = Control.new()
	menu_arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(menu_arena)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 60)
	_place(cols, Control.PRESET_CENTER, -400, -170, 800, 330)
	menu_arena.add_child(cols)
	arena_opts = []
	for tm in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.custom_minimum_size = Vector2(370, 0)
		cols.add_child(col)
		var head := _label(24, Color(0.4, 1.8, 1.0) if tm == 0 else Color(2.0, 0.5, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
		head.text = "霓虹队（我方）" if tm == 0 else "赤潮队（对方 AI）"
		col.add_child(head)
		for i in TEAM_SIZE:
			var row := HBoxContainer.new()
			col.add_child(row)
			var who := _label(17, Color(1, 1, 0.6) if (tm == 0 and i == 0) else Color(0.8, 0.8, 0.95))
			who.text = "你" if (tm == 0 and i == 0) else ("AI 队友 %d" % i if tm == 0 else "AI 对手 %d" % (i + 1))
			who.custom_minimum_size = Vector2(110, 0)
			row.add_child(who)
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(250, 40)
			ob.add_theme_font_override("font", ui_font)
			ob.add_theme_font_size_override("font_size", 17)
			for id in HeroesDB.ORDER:
				ob.add_item("%s  ·  %s" % [HeroesDB.HEROES[id]["name"], HeroesDB.ROLE_NAMES[HeroesDB.HEROES[id]["role"]]])
			ob.add_item("随机（按职业补位）")
			ob.select(HeroesDB.ORDER.find("drift") if (tm == 0 and i == 0) else HeroesDB.ORDER.size())
			row.add_child(ob)
			arena_opts.append(ob)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	_place(bottom, Control.PRESET_CENTER_BOTTOM, -330, -150, 660, 50)
	menu_arena.add_child(bottom)
	var dl := _label(18, Color(0.8, 0.8, 1.0))
	dl.text = "AI 难度"
	bottom.add_child(dl)
	diff_opt = OptionButton.new()
	diff_opt.focus_mode = Control.FOCUS_NONE
	diff_opt.custom_minimum_size = Vector2(120, 40)
	diff_opt.add_theme_font_override("font", ui_font)
	diff_opt.add_theme_font_size_override("font_size", 17)
	for nm in ["简单", "普通", "困难"]:
		diff_opt.add_item(nm)
	diff_opt.select(1)
	bottom.add_child(diff_opt)
	var go := _menu_btn("开始对战", 200, 48, 22)
	go.pressed.connect(_start_arena_from_menu)
	bottom.add_child(go)
	var back2 := _menu_btn("返回", 120, 48, 18)
	back2.pressed.connect(_show_menu)
	bottom.add_child(back2)
	var rule := _label(15, Color(0.75, 0.75, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	rule.text = "坦克 · 输出 · 辅助 三职业 3V3 · 先拿到 %d 次击倒的队伍获胜（%d 分钟后击倒多者获胜）· 阵亡后在泉水复活 · 可选相同英雄" % [ARENA_KILLS, int(ARENA_LEN / 60.0)]
	_place(rule, Control.PRESET_CENTER_BOTTOM, -500, -90, 1000, 30)
	menu_arena.add_child(rule)

func _hero_card(id: String) -> Control:
	var d: Dictionary = HeroesDB.HEROES[id]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(398, 236)
	var col: Color = d["col"]
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.03, 0.1, 0.94), Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.9)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var tr := TextureRect.new()
	tr.texture = TEX[str(d["sprite"]) + "_0"]
	tr.custom_minimum_size = Vector2(56, 56)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate = Color(1.6, 1.6, 1.6)
	top.add_child(tr)
	var nv := VBoxContainer.new()
	top.add_child(nv)
	var nm := _label(24, Color(1.0, 0.9, 0.5))
	nm.text = "%s   [%s]" % [d["name"], HeroesDB.ROLE_NAMES[d["role"]]]
	nv.add_child(nm)
	var tl := _label(14, Color(0.7, 0.95, 1.0))
	tl.text = str(d["title"])
	nv.add_child(tl)
	var body := _rt(13)
	var b: Dictionary = d["base"]
	var gn: Dictionary = d["gain"]
	var prim: String = d["primary"]
	var star := {"str": "", "agi": "", "int": ""}
	star[prim] = "★"
	var txt: String = "[color=#d8d8ff]%s[/color]\n" % d["blurb"]
	txt += "[color=#ff7a6a]力量%s %d(+%s)[/color]  [color=#6aff8a]敏捷%s %d(+%s)[/color]  [color=#6ab0ff]智力%s %d(+%s)[/color]  %s\n" % [
		star["str"], int(b["str"]), _num(gn["str"]), star["agi"], int(b["agi"]), _num(gn["agi"]), star["int"], int(b["int"]), _num(gn["int"]), "近战" if bool(d["melee"]) else "射手"]
	for s in ["q", "w", "e", "r"]:
		txt += "[color=#ffd23f]%s[/color] %s  " % [s.to_upper(), d["skills"][s]["name"]]
	txt += "\n[color=#a0ffa0]%s[/color]" % d["combo"]
	body.text = txt
	body.custom_minimum_size = Vector2(380, 0)
	v.add_child(body)
	var pick := _menu_btn("选择 %s" % d["name"], 380, 38, 17)
	pick.pressed.connect(_start_survival.bind(id))
	v.add_child(pick)
	return p

func _show_menu() -> void:
	state = S.MENU
	_clear_world()
	overlay.queue_redraw()
	floor_layer.queue_redraw()
	hud.visible = false
	menu_root.visible = true
	menu_main.visible = true
	menu_surv.visible = false
	menu_arena.visible = false
	_close_shop()
	center_lbl.text = "NEON DRIFT"
	center_lbl.label_settings.font_size = 104
	center_lbl.label_settings.font_color = Color(0.4, 1.0, 1.0)
	center_lbl.modulate.a = 1.0
	sub_lbl.modulate.a = 1.0
	sub_lbl.text = "霓 虹 漂 移\n\n生存最长  %s" % _fmt(best)

func _open_select(m: int) -> void:
	state = S.SELECT
	sel_mode = m
	menu_main.visible = false
	menu_surv.visible = m == M.SURVIVAL
	menu_arena.visible = m == M.ARENA
	center_lbl.label_settings.font_size = 56
	center_lbl.text = "选择英雄" if m == M.SURVIVAL else "3V3 英雄竞技场"
	sub_lbl.text = ""
	sfx("select", 1.2, -6.0)

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
	if sfx_origin != Vector2.INF:
		var dist := sfx_origin.distance_to(cam.get_screen_center_position())
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

func _load_best() -> void:
	if FileAccess.file_exists("user://neondrift2.save"):
		var f := FileAccess.open("user://neondrift2.save", FileAccess.READ)
		best = float(f.get_var())

func _save_best() -> void:
	var f := FileAccess.open("user://neondrift2.save", FileAccess.WRITE)
	f.store_var(best)

func _fmt(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]

# ============================================================ flow
func _clear_world() -> void:
	for arr in [enemies, hshots, eshots, runes, heroes]:
		for n in arr:
			if is_instance_valid(n):
				n.queue_free()
		arr.clear()
	for c in layer_trails.get_children():
		c.queue_free()
	zones.clear()
	bosses.clear()
	seen_kinds.clear()
	team0.clear()
	for c in fx.get_children():
		c.queue_free()
	for c in feed_box.get_children():
		c.queue_free()
	for c in toast_box.get_children():
		c.queue_free()
	player = null
	brains = {}
	autopilot = false
	selected = null
	targeting = ""

func _make_hero(id: String, tm: int, is_player: bool, diff: int) -> Hero:
	var h := Hero.new()
	layer_heroes.add_child(h)
	h.setup(self, id, tm, is_player)
	layer_trails.add_child(h.trail)
	heroes.append(h)
	if not is_player:
		var ai := HeroAI.new()
		ai.setup(h, self, diff)
		h.ai = ai
	return h

func _begin_common() -> void:
	t = 0.0
	kills = 0
	spawn_acc = 0.0
	event_i = 0
	next_rune = 120.0 if mode == M.SURVIVAL else 30.0
	popups = 0
	shake = 0.0
	hitstop = 0.0
	team_kills = [0, 0]
	first_blood = false
	winner = -1
	state = S.PLAY
	paused = false
	menu_root.visible = false
	hud.visible = true
	board.visible = false
	stats_panel.visible = false
	center_lbl.text = ""
	sub_lbl.text = ""
	respawn_lbl.text = ""
	_close_shop()
	_setup_hud()
	_refresh_inv()
	selected = player
	cam.position = player.position
	cam.reset_smoothing()
	var arena := mode == M.ARENA
	minimap.visible = arena
	score_rt.visible = arena
	time_lbl.visible = not arena
	kills_lbl.visible = not arena
	floor_layer.queue_redraw()
	sfx("levelup", 0.8, -4.0)

func _start_survival(id: String) -> void:
	_clear_world()
	mode = M.SURVIVAL
	last_cfg = {"mode": M.SURVIVAL, "hero": id}
	player = _make_hero(id, 0, true, 1)
	player.position = Vector2.ZERO
	player.face = -PI / 2
	_begin_common()
	toast("你有 1 个技能点：按 Ctrl+Q/W/E 或点击技能上方的「+」学习", Color(1.0, 0.9, 0.4), 7.0)
	toast("右键移动，对手靠近时会自动攻击。攻击前摇是青色光环，后摇是灰色光环（移动可取消后摇）", Color(0.7, 0.95, 1.0), 8.0)
	toast("按 B 打开商店（游戏暂停）：消灭对手获得金钱，购买装备强化英雄", Color(1.0, 0.85, 0.3), 8.0)
	toast("连招：%s" % player.def["combo"], Color(0.7, 1.0, 0.7), 9.0)

func _start_arena_from_menu() -> void:
	var a := []
	var b := []
	var n: int = HeroesDB.ORDER.size()
	for i in TEAM_SIZE * 2:
		var ob: OptionButton = arena_opts[i]
		var k := ob.selected
		var lst: Array = a if i < TEAM_SIZE else b
		var id: String = str(HeroesDB.ORDER[k]) if k < n else ""
		lst.append(id)
	_fill_random(a)
	_fill_random(b)
	_start_arena(a, b, diff_opt.selected)

## "随机" slots pick a hero for the role the team is still missing (tank / carry / support)
func _fill_random(lst: Array) -> void:
	var have := {}
	for id in lst:
		if id != "":
			have[HeroesDB.HEROES[id]["role"]] = true
	for i in lst.size():
		if lst[i] != "":
			continue
		var want := ""
		for r in ["tank", "support", "carry"]:
			if not have.has(r):
				want = r
				break
		var pool := []
		for id in HeroesDB.ORDER:
			if want == "" or HeroesDB.HEROES[id]["role"] == want:
				pool.append(id)
		var pick: String = str(pool[rng.randi() % pool.size()])
		lst[i] = pick
		have[HeroesDB.HEROES[pick]["role"]] = true

func _start_arena(a: Array, b: Array, diff: int) -> void:
	_clear_world()
	mode = M.ARENA
	difficulty = diff
	last_cfg = {"mode": M.ARENA, "a": a, "b": b, "diff": diff}
	for tm in 2:
		var ids: Array = a if tm == 0 else b
		for i in ids.size():
			var h := _make_hero(str(ids[i]), tm, tm == 0 and i == 0, diff)
			h.hp_mult = 1.15
			h.regen_bonus = 0.5
			h.recalc()
			h.hp = h.max_hp
			var home := home_pos(tm)
			h.position = home + Vector2(0, (i - 1) * 60.0)
			h.face = (Vector2.ZERO - home).angle()
			if tm == 0 and i == 0:
				player = h
	brains = {0: TeamAI.new(), 1: TeamAI.new()}
	brains[0].setup(self, 0)
	brains[1].setup(self, 1)
	_begin_common()
	toast("3V3 竞技场：先拿到 %d 次击倒获胜。阵亡后在泉水复活，泉水会快速回复并灼烧来犯的对手。" % ARENA_KILLS, Color(0.7, 0.95, 1.0), 9.0)
	toast("你有 1 个技能点：Ctrl+Q/W/E 学习。B 打开商店（游戏暂停），Tab 查看计分板。", Color(1.0, 0.9, 0.4), 9.0)
	toast("连招：%s" % player.def["combo"], Color(0.7, 1.0, 0.7), 9.0)

func _restart() -> void:
	if last_cfg.get("mode", -1) == M.ARENA:
		_start_arena(last_cfg["a"], last_cfg["b"], int(last_cfg["diff"]))
	else:
		_start_survival(str(last_cfg.get("hero", "drift")))

func _end(win: bool) -> void:
	state = S.END
	dead_timer = 0.0
	targeting = ""
	_close_shop()
	center_lbl.modulate.a = 1.0
	sub_lbl.modulate.a = 1.0
	center_lbl.label_settings.font_size = 92
	respawn_lbl.text = ""
	if win:
		center_lbl.label_settings.font_color = Color(1.0, 0.9, 0.4)
		center_lbl.text = "VICTORY"
		sfx("levelup", 0.7)
		_flash(Color(1, 1, 1, 0.6))
	else:
		center_lbl.label_settings.font_color = Color(1.0, 0.35, 0.6)
		center_lbl.text = "DEFEAT" if mode == M.ARENA else "SIGNAL LOST"
		sfx("boom", 0.8)
		shake = 20.0
	if mode == M.SURVIVAL:
		var new_best := t > best
		if new_best:
			best = t
			_save_best()
		sub_lbl.text = "%s存活 %s     等级 %d     消灭 %d\n\n最长存活 %s\n\n[ R 再来一局    Esc 返回菜单 ]" % [
			("你在霓虹尸潮中坚持了 30 分钟！\n\n" if win else ("★ 新纪录 ★\n" if new_best else "")), _fmt(t), player.level, kills, _fmt(best)]
	else:
		sub_lbl.text = "霓虹队  %d  :  %d  赤潮队     用时 %s\n\n你：%s  等级 %d   %d / %d / %d\n\n[ R 再来一局    Esc 返回菜单 ]" % [
			team_kills[0], team_kills[1], _fmt(t), player.display_name(), player.level, player.kills, player.deaths, player.assists]

# ============================================================ hero API (used by hero.gd, kits and the AI)
func clamp_pos(p: Vector2, r := 16.0) -> Vector2:
	if mode == M.ARENA and p.length() > ARENA_R - r:
		return p.normalized() * (ARENA_R - r)
	return p

func home_pos(tm: int) -> Vector2:
	return Vector2(-1000.0 if tm == 0 else 1000.0, 0.0)

func near_home(h) -> bool:
	return mode == M.ARENA and h.position.distance_to(home_pos(h.team)) < FOUNTAIN_R

func in_enemy_fountain(p: Vector2, tm: int) -> bool:
	return mode == M.ARENA and p.distance_to(home_pos(1 - tm)) < FOUNTAIN_R + 80.0

func arena_center() -> Vector2:
	return Vector2.ZERO

func foes_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	if tm == 0 and not enemies.is_empty():
		for e in _query(p, r + 60.0) + _boss_list():
			if e.targetable() and p.distance_to(e.position) < r + e.radius:
				out.append(e)
	for h in heroes:
		if h.team != tm and h.targetable() and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

func foes_all(tm: int) -> Array:
	var out := []
	if tm == 0:
		for e in enemies:
			if e.targetable():
				out.append(e)
	for h in heroes:
		if h.team != tm and h.targetable():
			out.append(h)
	return out

func nearest_foe(tm: int, p: Vector2, max_d: float):
	var best_u = null
	var bd := max_d
	for u in foes_in(tm, p, max_d):
		var dd: float = p.distance_to(u.position) - u.radius
		if dd < bd:
			bd = dd
			best_u = u
	return best_u

func nearest_foe_hero(tm: int, p: Vector2):
	var best_u = null
	var bd := 1e9
	for h in heroes:
		if h.team == tm or not h.targetable():
			continue
		var dd: float = p.distance_to(h.position)
		if dd < bd:
			bd = dd
			best_u = h
	return best_u

func allies_of(hh) -> Array:
	var out := []
	for h in heroes:
		if h != hh and h.team == hh.team and not h.dead:
			out.append(h)
	return out

func team_focus(tm: int, u) -> int:
	var n := 0
	for h in heroes:
		if h.team != tm or h.dead:
			continue
		if h.cmd_target == u or (h.ai != null and h.ai.target == u):
			n += 1
	return n

func nearest_rune(p: Vector2, max_d: float):
	var best_p = null
	var bd := max_d
	for r in runes:
		var dd: float = p.distance_to(r.position)
		if dd < bd:
			bd = dd
			best_p = r.position
	return best_p

func _team_heroes(tm: int) -> Array:
	var out := []
	for h in heroes:
		if h.team == tm and h.targetable():
			out.append(h)
	return out

func add_shake(v: float, src) -> void:
	if src != null and is_instance_valid(src) and not src.is_player:
		if src.position.distance_to(cam.get_screen_center_position()) > 700.0:
			return
		v *= 0.5
	shake = maxf(shake, v)

func on_level_up(h) -> void:
	if h.is_player:
		sfx("levelup", 1.0, -3.0)
		_ring(h.position, 10, 180, 0.5, Color(1.8, 1.6, 0.4), 8)
		_popup(h.position + Vector2(-40, -60), "LEVEL %d" % h.level, label_big)
		if h.level in [6, 12, 18]:
			toast("等级 %d：大招「%s」可以升级了！" % [h.level, h.sdef["r"]["name"]], Color(1.0, 0.6, 1.0), 5.0)

func on_hero_cast(_h, _s: String) -> void:
	pass

func spawn_hero_shot(h, tgt, dmg: float, info: Dictionary) -> void:
	var s := HeroShot.new()
	s.position = h.position + Vector2.from_angle(h.face) * 20.0
	s.owner_h = h
	s.target = tgt
	s.dmg = dmg
	s.info = info
	s.speed = float(h.def["proj_speed"])
	s.last_pos = tgt.position
	var proc: bool = bool(info.get("proc", false))
	var spr := Sprite2D.new()
	spr.texture = TEX["bullet"]
	spr.scale = Vector2(PIX, PIX) * (1.4 if proc else 1.0)
	if proc:
		spr.modulate = Color(2.4, 2.2, 0.6)
	elif h.team == 1:
		spr.modulate = Color(2.6, 0.8, 0.8)
	else:
		spr.modulate = Color(1.6, 2.4, 2.6)
	s.add_child(spr)
	layer_shots.add_child(s)
	hshots.append(s)
	_burst(h.position + Vector2.from_angle(h.face) * 24.0, Color(0.8, 2.4, 2.8) if h.team == 0 else Color(2.6, 0.8, 0.8), 6, 160.0, 0.15, 2.0)
	sfx("attack", rng.randf_range(0.95, 1.08), -8.0, 0.04)

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
	gs.texture = TEX[str(h.def["sprite"]) + "_0"]
	gs.scale = Vector2(PIX, PIX)
	gs.rotation = h.face
	gs.position = p
	gs.modulate = col
	fx.add_child(gs)
	var tw := gs.create_tween()
	tw.tween_property(gs, "modulate:a", 0.0, 0.4)
	tw.tween_callback(gs.queue_free)

func item_chain(h, first, bounces: int, dmg: float) -> void:
	var hit := {}
	var cur = first
	var prev: Vector2 = first.position
	for i in bounces + 1:
		if cur == null:
			break
		hit[cur] = true
		_bolt(prev, cur.position, Color(0.8, 1.8, 2.8))
		if not cur.dead:
			damage(h, cur, dmg, "proc", "magic")
		prev = cur.position
		var nxt = null
		var bd := 500.0
		for o in foes_in(h.team, prev, 500.0):
			if hit.has(o):
				continue
			var dd: float = prev.distance_to(o.position)
			if dd < bd:
				bd = dd
				nxt = o
		cur = nxt
	sfx("zap", rng.randf_range(1.1, 1.4), -10.0, 0.08)

func armor_mult(a: float) -> float:
	return 1.0 - (0.06 * a) / (1.0 + 0.06 * absf(a))

func brain(tm: int):
	return brains.get(tm, null)

func allies_in(tm: int, p: Vector2, r: float) -> Array:
	var out := []
	for h in heroes:
		if h.team == tm and not h.dead and p.distance_to(h.position) < r + h.radius:
			out.append(h)
	return out

func heal(src, tgt, amount: float) -> void:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or amount <= 0.0:
		return
	var before: float = tgt.hp
	tgt.hp = minf(tgt.max_hp, tgt.hp + amount)
	var done: float = tgt.hp - before
	if src != null and is_instance_valid(src) and src.is_hero:
		src.heal_done += done
		var show: bool = src.is_player or tgt.is_player or cam.get_screen_center_position().distance_to(tgt.position) < 700.0
		if show and done >= 1.0 and popups < 50:
			if _heal_label == null:
				_heal_label = _ls(20, Color(0.5, 1.0, 0.5))
			_popup(tgt.position + Vector2(rng.randf_range(-10, 10), -tgt.radius - 10.0), "+%d" % int(done), _heal_label)

## forced movement (hooks, vortex pulls). Heroes are carried by their dash; creeps snap.
func displace(u, dest: Vector2, speed: float) -> void:
	if u == null or not is_instance_valid(u) or u.dead:
		return
	if u.is_hero:
		u.start_dash(dest, speed, Callable())
	else:
		u.position = dest

## the one damage entry point for every source (heroes, creeps, zones, items)
func damage(src, tgt, amount: float, kind: String, dtype := "magic", kb := Vector2.ZERO, is_attack := false) -> float:
	if tgt == null or not is_instance_valid(tgt) or tgt.dead or tgt.invuln > 0.0:
		return 0.0
	var src_hero: bool = src != null and is_instance_valid(src) and src.is_hero
	var a := amount
	if tgt.is_hero and is_attack:
		var eva: float = float(tgt.ST.get("eva", 0.0))
		var true_strike: bool = src_hero and not (src.sp().get("mkb", []) as Array).is_empty()
		if eva > 0.0 and not true_strike and rng.randf() < eva:
			if popups < 50 and (tgt.is_player or (src_hero and src.is_player)):
				_popup(tgt.position + Vector2(-20, -40), "闪避", label_set)
			return 0.0
	if dtype == "phys":
		a *= armor_mult(tgt.armor_val())
	elif dtype == "magic":
		if src_hero:
			a *= 1.0 + float(src.ST.get("amp", 0.0))
		a *= 1.0 - tgt.mr_val()
	a *= tgt.dmg_taken_mult()
	if tgt.barrier > 0.0:
		var absorbed: float = minf(a, tgt.barrier)
		tgt.barrier -= absorbed
		a -= absorbed
		if a <= 0.0:
			tgt.flash = 0.04
			return 0.0
	var show: bool = kind not in ["dot", "enemy"] and popups < 50 and src_hero and src.is_player
	if show:
		var ls := label_set
		var txt := str(int(a))
		if kind == "skill": ls = label_skill
		elif kind == "chain" or kind == "proc": ls = _chain_ls()
		elif kind == "crit":
			ls = _crit_ls()
			txt += "!"
		_popup(tgt.position + Vector2(rng.randf_range(-12, 12), -tgt.radius), txt, ls)
	if tgt.is_hero:
		if tgt.god or (tgt.is_player and god):
			return 0.0
		tgt.hp -= a
		tgt.log_damage(src)
		tgt.last_hurt = t
		if kind != "dot":
			tgt.flash = 0.06
		if tgt.is_player and tgt.hurt_cd <= 0.0 and kind != "dot":
			tgt.hurt_cd = 0.35
			sfx("hurt", rng.randf_range(0.9, 1.1), -8.0)
			if a > tgt.max_hp * 0.04:
				_flash(Color(1.0, 0.1, 0.25, 0.1 + minf(0.2, a / tgt.max_hp)))
				shake = maxf(shake, 5.0)
		if tgt.hp <= 0.0:
			_hero_died(tgt, src)
		return a
	tgt.hp -= a
	if kind != "dot":
		tgt.flash = 0.07
	if not tgt.boss and tgt.kind != "colossus":
		tgt.knock += kb * 140.0
	if tgt.hp <= 0.0:
		_kill(tgt, src)
	return a

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

# ============================================================ hero death & arena rules
func _hero_died(v, killer) -> void:
	if v.dead:
		return
	v.hp = 0.0
	var c: Color = v.team_color()
	_burst(v.position, c, 50, 480.0, 0.9, 4.0)
	_ring(v.position, 20, 360, 0.7, c, 10)
	sfx("boom", 0.9, -4.0)
	v.die()
	v.deaths += 1
	if targeting != "" and v.is_player:
		targeting = ""
	if mode == M.SURVIVAL:
		if v.is_player:
			shake = 26.0
			_end(false)
		return
	var victim_streak: int = v.streak
	v.streak = 0
	v.respawn_t = minf(40.0, 6.0 + v.level * 1.6)
	var k = null
	if killer != null and is_instance_valid(killer) and killer.is_hero and killer.team != v.team:
		k = killer
	var helpers := []
	var newest := -1.0
	for key in v.dmg_log:
		var entry: Array = v.dmg_log[key]
		var hh = entry[0]
		if not is_instance_valid(hh) or t - float(entry[1]) > 12.0:
			continue
		if k == null and float(entry[1]) > newest:
			newest = float(entry[1])
		if hh != k:
			helpers.append(hh)
	if k == null and not helpers.is_empty():
		for hh in helpers:
			if float(v.dmg_log[hh.get_instance_id()][1]) >= newest:
				k = hh
		helpers.erase(k)
	v.dmg_log = {}
	var kt: int = 1 - int(v.team)
	team_kills[kt] += 1
	var bounty: float = 90.0 + v.level * 6.0 + minf(victim_streak, 6) * 40.0
	if team_kills[1 - kt] - team_kills[kt] >= 5:
		bounty *= 1.5  # comeback bounty for the team that is behind
	if k != null:
		k.kills += 1
		k.streak += 1
		k.gold += bounty
		if k.is_player and popups < 50:
			_popup(v.position + Vector2(-20, -50), "+%d" % int(bounty), _gold_ls())
	for hh in helpers:
		hh.assists += 1
		hh.gold += 40.0 + v.level * 5.0
	# shared xp
	var share := []
	for h in heroes:
		if h.team == kt and not h.dead and (h == k or helpers.has(h) or h.position.distance_to(v.position) < 1300.0):
			share.append(h)
	var xp_total: float = 40.0 + v.level * 15.0
	if team_kills[1 - kt] > team_kills[kt]:
		xp_total *= 1.5
	for h in share:
		h.gain_xp(xp_total / float(share.size()) * 1.4 + xp_total * 0.15)
	# feed
	var kname: String = k.display_name() if k != null else "泉水"
	var who_k: String = ("你" if k != null and k.is_player else kname)
	var who_v: String = ("你" if v.is_player else v.display_name())
	var fc := Color(0.5, 1.6, 1.8) if kt == 0 else Color(2.0, 0.55, 0.55)
	_feed("%s %s 击倒了 %s %s" % [("霓虹" if kt == 0 else "赤潮"), who_k, ("赤潮" if kt == 0 else "霓虹"), who_v], fc)
	if not first_blood:
		first_blood = true
		_announce("第一滴血！", Color(1.0, 0.3, 0.35), 1.4)
	elif k != null and k.streak in [3, 5, 7]:
		_announce({3: "%s 势不可挡！", 5: "%s 主宰比赛！", 7: "%s 超神了！"}[k.streak] % who_k, fc, 1.4)
	if v.is_player:
		_flash(Color(0.6, 0.0, 0.1, 0.35))
		shake = 14.0
	if team_kills[kt] >= ARENA_KILLS:
		winner = kt
		_end(kt == 0)

func _update_arena(d: float) -> void:
	for h in heroes:
		if h.dead:
			h.respawn_t -= d
			if h.respawn_t <= 0.0:
				var home := home_pos(h.team)
				h.respawn(home + Vector2(rng.randf_range(-60, 60), rng.randf_range(-80, 80)))
				h.face = (Vector2.ZERO - home).angle()
				_ring(h.position, 10, 140, 0.5, h.team_color(), 8)
				if h.is_player:
					sfx("rune", 1.0, -4.0)
			continue
		h.gold += 4.0 * d
		h.gain_xp(4.5 * d)
		var own: float = h.position.distance_to(home_pos(h.team))
		if own < FOUNTAIN_R:
			h.hp = minf(h.max_hp, h.hp + h.max_hp * 0.06 * d)
			h.mana = minf(h.mana_max, h.mana + h.mana_max * 0.06 * d)
		if h.position.distance_to(home_pos(1 - h.team)) < FOUNTAIN_R:
			damage(null, h, 320.0 * d, "dot", "pure")
	if t >= next_rune:
		next_rune = t + 60.0
		for spot in RUNE_SPOTS:
			var taken := false
			for r in runes:
				if r.position.distance_to(spot) < 10.0:
					taken = true
			if not taken:
				_spawn_rune_at(spot)
	if t >= ARENA_LEN:
		if team_kills[0] != team_kills[1]:
			winner = 0 if team_kills[0] > team_kills[1] else 1
			_end(winner == 0)
		elif int(t) % 30 == 0 and t - d < floorf(t):
			_announce("加时：下一次击倒决定胜负", Color(1.0, 0.85, 0.3), 1.2)

func _separate_heroes() -> void:
	for i in heroes.size():
		var a = heroes[i]
		if a.dead or not a.dash.is_empty():
			continue
		for j in range(i + 1, heroes.size()):
			var b = heroes[j]
			if b.dead or not b.dash.is_empty():
				continue
			var dv: Vector2 = a.position - b.position
			var dl := dv.length()
			var minl: float = (a.radius + b.radius) * 0.85
			if dl < minl and dl > 0.01:
				var push := dv / dl * (minl - dl) * 0.5
				a.position = clamp_pos(a.position + push, a.radius)
				b.position = clamp_pos(b.position - push, b.radius)

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

# ============================================================ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode
		if state == S.MENU:
			if k == KEY_1: _open_select(M.SURVIVAL)
			elif k == KEY_2: _open_select(M.ARENA)
			return
		if state == S.SELECT:
			if k == KEY_ESCAPE: _show_menu()
			return
		if state == S.END:
			if dead_timer > 0.6:
				if k == KEY_R or k == KEY_SPACE or k == KEY_ENTER: _restart()
				elif k == KEY_ESCAPE: _show_menu()
			return
		if k == KEY_ESCAPE:
			if shop_open:
				_close_shop()
			elif stats_panel.visible:
				stats_panel.visible = false
			elif targeting != "":
				targeting = ""
			else:
				paused = not paused
				center_lbl.label_settings.font_size = 72
				center_lbl.label_settings.font_color = Color(0.4, 1.0, 1.0)
				center_lbl.modulate.a = 1.0
				center_lbl.text = "暂停" if paused else ""
				sub_lbl.text = "[ Esc 继续    Q 退出到菜单 ]" if paused else ""
			return
		if paused:
			if k == KEY_Q:
				paused = false
				_show_menu()
			return
		if k == KEY_B:
			if shop_open: _close_shop()
			else: _open_shop()
			return
		if k == KEY_TAB:
			if mode == M.ARENA:
				board.visible = not board.visible
				_update_board()
			return
		if k == KEY_C:
			stats_panel.visible = not stats_panel.visible
			return
		if shop_open:
			return
		var key_map := {KEY_Q: "q", KEY_W: "w", KEY_E: "e", KEY_R: "r"}
		if key_map.has(k):
			var s: String = key_map[k]
			if ev.ctrl_pressed or ev.meta_pressed:
				_learn(s)
			else:
				_begin_target(s)
		elif k == KEY_A:
			targeting = "attack"
		elif k == KEY_S:
			player.order_stop()
			targeting = ""
		elif k == KEY_H:
			player.order_hold()
			targeting = ""
		elif k == KEY_O and (ev.ctrl_pressed or ev.meta_pressed):
			_learn("attr")
		elif k == KEY_F6:
			autopilot = not autopilot
			if autopilot and player.ai == null:
				var ai := HeroAI.new()
				ai.setup(player, self, maxi(difficulty, 1))
				player.ai = ai
			toast("AI 托管：%s（F6 切换）" % ("开" if autopilot else "关"), Color(0.6, 1.0, 1.0), 2.5)
		elif k == KEY_F10 and OS.is_debug_build():
			god = not god  # dev shortcut: invulnerable hero for testing
			toast("测试免疫伤害：%s" % ("开" if god else "关"), Color(1, 1, 0.5), 2.0)
		elif k == KEY_F7 and OS.is_debug_build():
			player.gold += 3000.0  # dev shortcut: +3000 gold
		elif k == KEY_F8 and OS.is_debug_build() and mode == M.SURVIVAL:
			_spawn_boss(clampi(bosses.size() + 1, 1, 3))  # dev shortcut: summon a boss
		elif k == KEY_F9 and OS.is_debug_build():
			t += 60.0  # dev shortcut: fast-forward one minute (skips scheduled events)
			while event_i < EVENTS.size() and EVENTS[event_i][0] <= t:
				event_i += 1
			next_rune = maxf(next_rune, t + 5.0)
			for h in heroes:
				h.gain_xp(h.xp_need())
	elif ev is InputEventMouseButton:
		if state != S.PLAY or paused or shop_open or player == null:
			return
		var mp := get_global_mouse_position()
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			right_held = ev.pressed
			if ev.pressed:
				if targeting != "":
					targeting = ""
					return
				_right_click(mp)
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_left_click(mp)

func _unit_at(p: Vector2, foes_only: bool):
	var best_u = null
	var bd := 1e9
	for e in enemies:
		if not e.targetable(): continue
		var d: float = p.distance_to(e.position)
		if d < e.radius + 14.0 and d < bd:
			bd = d
			best_u = e
	for h in heroes:
		if h.dead or h == player: continue
		if foes_only and (h.team == player.team or not h.targetable()): continue
		var d2: float = p.distance_to(h.position)
		if d2 < h.radius + 18.0 and d2 < bd:
			bd = d2
			best_u = h
	return best_u

func _right_click(p: Vector2) -> void:
	if player.dead: return
	var e = _unit_at(p, true)
	if e != null:
		player.order_attack(e)
		_marker(e.position, Color(1.0, 0.3, 0.3))
	else:
		player.order_move(p)
		player.cmd_pos = p
		_marker(p, Color(0.3, 1.0, 0.4))

func _left_click(p: Vector2) -> void:
	if targeting == "attack":
		targeting = ""
		if player.dead: return
		var e = _unit_at(p, true)
		if e == null:
			e = nearest_foe(player.team, p, 480.0)
		if e != null:
			player.order_attack(e)
			_marker(e.position, Color(1.0, 0.3, 0.3))
		else:
			player.order_amove(p)
			_marker(p, Color(1.0, 0.3, 0.3))
		return
	if targeting in ["q", "w", "e", "r"]:
		var s := targeting
		targeting = ""
		if player.dead: return
		var typ: String = player.sdef[s]["type"]
		var tgt = _ally_at(p) if typ == "ally" else _unit_at(p, true)
		if typ == "ally" and tgt == null:
			_deny("需要选择一个友方英雄（可以选自己）")
			return
		if tgt == null and (typ == "unit" or typ == "unit_or_point"):
			tgt = nearest_foe(player.team, p, 90.0 if typ == "unit" else 36.0)
		var err: String = player.order_cast(s, tgt, p)
		if err != "":
			_deny(err)
		return
	var u = _unit_at(p, false)
	if u != null:
		selected = u
		sfx("select", 1.4, -12.0)
	else:
		selected = player

func _ally_at(p: Vector2):
	var best_u = null
	var bd := 1e9
	for h in heroes:
		if h.dead or h.team != player.team:
			continue
		var dd: float = p.distance_to(h.position)
		if dd < h.radius + 70.0 and dd < bd:
			bd = dd
			best_u = h
	return best_u

func _marker(p: Vector2, col: Color) -> void:
	marker_pos = p
	marker_t = 0.45
	marker_col = col

func _deny(msg: String) -> void:
	deny_lbl.text = msg
	deny_lbl.modulate.a = 1.0
	var tw := deny_lbl.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(deny_lbl, "modulate:a", 0.0, 0.4)
	sfx("deny", 1.0, -6.0, 0.15)

func _begin_target(s: String) -> void:
	if player.dead: return
	var st: Dictionary = player.sdef[s]
	var typ: String = st["type"]
	var err: String = player.cast_error(s, player if typ == "ally" else null) if typ != "unit" else ""
	if typ == "unit":
		var base_err: String = player.cast_error(s, player)
		if base_err != "需要选择一个对方单位":
			err = base_err
	if err != "":
		_deny(err)
		return
	if typ == "no_target":
		var e2: String = player.order_cast(s, null, player.position)
		if e2 != "": _deny(e2)
		return
	targeting = s

func _learn(s: String) -> void:
	if state != S.PLAY or player == null: return
	if not player.learn(s):
		if player.skill_points <= 0: _deny("没有技能点")
		elif s == "r": _deny("大招需要等级 6 / 12 / 18")
		else: _deny("需要更高的英雄等级")
		return
	sfx("learn")
	_ring(player.position, 10, 90, 0.35, Color(1.6, 1.4, 0.4), 4)

# ============================================================ main loop
func _process(delta: float) -> void:
	_update_fx_ui(delta)
	if state == S.MENU or state == S.SELECT:
		grid.cam_pos += Vector2(40, 20) * delta
		cam.position = grid.cam_pos
		grid.pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.002)
		grid.queue_redraw()
		return
	if paused or shop_open:
		overlay.queue_redraw()
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	var d := delta
	if state == S.PLAY:
		t += d
		if mode == M.SURVIVAL:
			_update_timeline()
			_update_spawns(d)
			if not player.dead:
				player.gold += 1.6 * d
			if t >= GAME_LEN:
				_end(true)
		else:
			_update_arena(d)
	else:
		dead_timer += d
		d *= 0.3
	team0 = _team_heroes(0)
	_rebuild_hash()
	_apply_auras()
	if state == S.PLAY:
		_hold_move(d)
		for tm in brains:
			brains[tm].update(d)
		for h in heroes:
			if h.ai != null and (not h.is_player or autopilot):
				h.ai.update(d)
	for h in heroes:
		sfx_origin = h.position if not h.is_player else Vector2.INF
		h.update(d)
		h.kit.tick_world(d)
	sfx_origin = Vector2.INF
	_separate_heroes()
	_update_enemies(d)
	_update_hshots(d)
	_update_eshots(d)
	_update_zones(d)
	_update_runes(d)
	_cleanup()
	if not player.dead:
		cam.position = player.position + Vector2(0, 70)
	cam.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake
	grid.cam_pos = cam.get_screen_center_position()
	grid.pulse = maxf(0.0, grid.pulse - delta * 1.5)
	grid.queue_redraw()
	overlay.queue_redraw()
	if mode == M.ARENA:
		minimap.queue_redraw()

func _hold_move(d: float) -> void:
	if not right_held or targeting != "" or player.dead:
		return
	right_t -= d
	if right_t > 0.0:
		return
	right_t = 0.12
	var mp := get_global_mouse_position()
	if _unit_at(mp, true) == null:
		if player.cmd == Hero.C.MOVE:
			player.cmd_pos = mp
		elif player.cmd != Hero.C.ATTACK:
			player.order_move(mp)

# ============================================================ survival timeline & spawning
func _hp_mult() -> float:
	var m := t / 60.0
	return 1.0 + m * 0.11 + pow(m / 10.0, 2.0) * 0.5

func _dmg_mult() -> float:
	return 1.0 + t / 60.0 * 0.06

func _update_timeline() -> void:
	while event_i < EVENTS.size() and t >= EVENTS[event_i][0]:
		var ev: String = EVENTS[event_i][1]
		event_i += 1
		match ev:
			"swarm": _swarm()
			"warn1", "warn2", "warn3":
				_announce("⚠ Boss 即将降临 ⚠", Color(1.0, 0.3, 0.85))
				sfx("warning")
			"boss1": _spawn_boss(1)
			"boss2": _spawn_boss(2)
			"boss3": _spawn_boss(3)
	if t >= next_rune:
		next_rune += 120.0
		_spawn_rune_at(player.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(260.0, 420.0))

func _update_spawns(d: float) -> void:
	var x := t / GAME_LEN
	var rate := 0.4 + 2.2 * x + 2.4 * x * x
	if not bosses.is_empty():
		rate *= 0.6
	spawn_acc += d * rate
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < MAX_ENEMIES:
			_spawn(_pick_kind(), _edge_pos())

func _count(kind: String) -> int:
	var n := 0
	for e in enemies:
		if e.kind == kind and not e.dead: n += 1
	return n

func _pick_kind() -> String:
	var m := t / 60.0
	var pool := [["grunt", maxf(4.0, 10.0 - m * 0.25)]]
	if m >= 1.5: pool.append(["dasher", 2.5])
	if m >= 2.5: pool.append(["splitter", 2.5])
	if m >= 3.5: pool.append(["shooter", 2.5])
	if m >= 5.0 and _count("sentry") < (3 if m < 20 else 5): pool.append(["sentry", 1.4])
	if m >= 5.0 and _count("frenzy") < 2: pool.append(["frenzy", 0.5])
	if m >= 7.0 and _count("colossus") < 4: pool.append(["colossus", 0.7])
	if m >= 7.0 and _count("mender") < 2: pool.append(["mender", 0.6])
	if m >= 9.0: pool.append(["bomber", 1.8])
	if m >= 12.0 and _count("aegis") < 2: pool.append(["aegis", 0.5])
	if m >= 15.0 and _count("hexer") < 3: pool.append(["hexer", 0.8])
	var total := 0.0
	for p in pool: total += p[1]
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0.0: return p[0]
	return "grunt"

func _edge_pos() -> Vector2:
	var a := rng.randf() * TAU
	return player.position + Vector2.RIGHT.rotated(a) * rng.randf_range(760.0, 860.0)

func _swarm() -> void:
	var m := t / 60.0
	var n := 10 + int(m * 0.8)
	_announce("包 围 ！", Color(1.0, 0.35, 0.45), 1.2)
	var gap := rng.randi() % n
	for i in n:
		if absi(i - gap) <= 1 or absi(i - gap) >= n - 1:
			continue
		var kind := "grunt" if m < 8 or i % 3 != 0 else "splitter"
		_spawn(kind, player.position + Vector2.RIGHT.rotated(TAU * i / n) * 620.0)

func _spawn(kind: String, pos: Vector2, force_elite := false) -> Enemy:
	var def: Dictionary = EDEF[kind]
	var e := Enemy.new()
	e.kind = kind
	e.team = 1
	e.position = pos
	var hm := _hp_mult()
	e.max_hp = def["hp"] * hm
	e.speed = def["spd"] * rng.randf_range(0.92, 1.08)
	e.radius = def["r"]
	e.dmg = def["dmg"] * _dmg_mult()
	e.rate = def["rate"]
	e.arange = def["range"]
	e.armor = def.get("armor", 0.0)
	e.mr = def.get("mr", 0.0)
	e.gold = def.get("gold", 0.0)
	e.xp = def["xp"]
	e.aura = def.get("aura", "")
	e.base_col = def["col"]
	e.timer = rng.randf_range(0.5, 2.0)
	var m := t / 60.0
	if force_elite or (m >= 12.0 and kind not in ["mini", "bomber"] and rng.randf() < minf(0.2, 0.03 + (m - 12.0) * 0.01)):
		e.elite = true
		e.max_hp *= 3.5
		e.dmg *= 1.4
		e.xp *= 3.0
		e.armor += 4.0
		e.radius *= 1.3
	e.hp = e.max_hp
	var s := Sprite2D.new()
	if def.has("spr"):
		s.texture = TEX[def["spr"]]
	else:
		s.texture = TEX[def["spr2"]]
	s.hframes = 2
	s.scale = Vector2(PIX, PIX) * (1.3 if e.elite else 1.0)
	e.spr = s
	e.add_child(s)
	layer_enemies.add_child(e)
	enemies.append(e)
	if not seen_kinds.has(kind) and kind != "mini":
		seen_kinds[kind] = true
		if kind != "grunt":
			toast("新对手：%s — %s" % [def["name"], def["desc"]], def["col"].lightened(0.3), 7.0)
	return e

func _spawn_boss(tier: int) -> void:
	var e := Enemy.new()
	e.kind = "boss"
	e.team = 1
	e.boss = true
	e.tier = tier
	e.position = player.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * 640.0
	e.max_hp = [9000.0, 24000.0, 60000.0][tier - 1]
	e.hp = e.max_hp
	e.speed = 95.0 + tier * 10.0
	e.radius = 92.0 * (1.0 + 0.12 * (tier - 1))
	e.dmg = 60.0 * _dmg_mult()
	e.xp = 600.0 * tier
	e.armor = 4.0 + 3.0 * tier
	e.mr = 0.25
	e.base_col = EDEF["boss"]["col"]
	e.timer = 2.0
	var a := AnimatedSprite2D.new()
	a.sprite_frames = boss_frames
	a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	a.scale = Vector2.ONE * (1.25 + 0.15 * (tier - 1))
	if tier == 3:
		a.self_modulate = Color(1.4, 1.1, 0.5)
	a.play()
	e.spr = a
	e.add_child(a)
	layer_enemies.add_child(e)
	enemies.append(e)
	bosses.append(e)
	sfx("boss")
	_announce(["典狱长 降临", "典狱长·至尊 降临", "奇点之心 苏醒"][tier - 1], Color(1.0, 0.3, 0.85), 2.0)
	shake = 14.0

func _spawn_rune_at(pos: Vector2) -> void:
	var r := Node2D.new()
	r.position = pos
	var kind: String = ["heal", "haste", "dd"][rng.randi() % 3]
	r.set_meta("kind", kind)
	r.set_meta("life", 60.0 if mode == M.SURVIVAL else 9999.0)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = gem_frames
	a.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	a.scale = Vector2(1.3, 1.3)
	a.modulate = {"heal": Color(0.6, 2.0, 0.8), "haste": Color(2.2, 0.6, 0.6), "dd": Color(0.6, 1.0, 2.4)}[kind]
	a.play()
	r.add_child(a)
	layer_runes.add_child(r)
	runes.append(r)
	if mode == M.SURVIVAL:
		toast("神符出现了：%s（右键走过去拾取）" % {"heal": "回复神符", "haste": "极速神符", "dd": "双倍伤害神符"}[kind], Color(0.7, 1.0, 0.8), 5.0)
	sfx("rune", 0.8, -6.0)

func _update_runes(d: float) -> void:
	var keep := []
	for r in runes:
		var life: float = r.get_meta("life") - d
		r.set_meta("life", life)
		var taker = null
		if state == S.PLAY:
			for h in heroes:
				if not h.dead and r.position.distance_to(h.position) < 44.0:
					taker = h
					break
		if taker != null:
			var kind: String = r.get_meta("kind")
			match kind:
				"heal":
					taker.hp = minf(taker.max_hp, taker.hp + taker.max_hp * 0.4)
					taker.mana = minf(taker.mana_max, taker.mana + taker.mana_max * 0.4)
				"haste": taker.haste_t = 20.0
				"dd": taker.dd_t = 20.0
			_ring(r.position, 10, 160, 0.5, Color(1.6, 2.0, 1.2), 8)
			var nm: String = {"heal": "回复神符：生命和魔法 +40%", "haste": "极速神符：移速大幅提升 20 秒", "dd": "双倍伤害神符：攻击伤害 ×2，持续 20 秒"}[kind]
			if taker.is_player:
				sfx("rune")
				toast(nm, Color(1.0, 1.0, 0.6), 3.0)
			elif mode == M.ARENA:
				_feed("%s 拿到了%s" % [taker.display_name(), nm.substr(0, 4)], Color(0.9, 0.9, 0.6))
			r.queue_free()
		elif life <= 0.0:
			r.queue_free()
		else:
			keep.append(r)
	runes = keep

# ============================================================ creeps (survival)
func _kill(e, src) -> void:
	e.dead = true
	kills += 1
	var c: Color = e.base_col * 2.2
	c.a = 1.0
	_burst(e.position, c, 14 if e.radius < 30 else 40, 300.0 if e.radius < 30 else 500.0, 0.45, 3.0)
	_ring(e.position, 6, e.radius * 2.4, 0.25, c, 5)
	sfx("explode", rng.randf_range(0.85, 1.2) * (0.7 if e.radius > 30 else 1.0), -9.0, 0.03)
	var bounty: float = e.gold * (1.0 + t / 1800.0 * 0.5) * (2.5 if e.elite else 1.0)
	if e.boss:
		bounty = 800.0 * e.tier
	var hh = src if (src != null and is_instance_valid(src) and src.is_hero) else player
	if hh != null and not hh.dead:
		hh.gain_xp(e.xp * (1.0 + t / 900.0))
		hh.gold += bounty
		if hh.is_player and popups < 50 and bounty >= 1.0:
			_popup(e.position + Vector2(-10, -e.radius - 30), "+%d" % int(bounty), _gold_ls())
	if e.kind == "splitter":
		for k in 2:
			var mm := _spawn("mini", e.position + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)))
			mm.knock = Vector2.RIGHT.rotated(rng.randf() * TAU) * 260.0
	if e.boss:
		bosses.erase(e)
		_burst(e.position, Color(2.2, 0.5, 2.0), 80, 700.0, 1.2, 5.0)
		_ring(e.position, 20, 800, 1.0, Color(2.4, 0.6, 2.2), 16)
		_flash(Color(1, 0.6, 1, 0.6))
		sfx("boom")
		shake = 34.0
		hitstop = 0.3
		for s in eshots: s.dead = true
		for h in heroes:
			if not h.dead:
				h.hp = h.max_hp
				h.mana = h.mana_max
		_announce("%s 已击破" % _ename(e), Color(1.0, 0.6, 0.95))
		if e.tier == 3:
			_end(true)
	if selected == e:
		selected = player

func _ename(e) -> String:
	if e.is_hero:
		return e.display_name()
	if e.boss:
		return ["典狱长", "典狱长·至尊", "奇点之心"][e.tier - 1]
	return EDEF[e.kind]["name"]

func _rebuild_hash() -> void:
	cells.clear()
	for e in enemies:
		if e.dead or e.boss: continue
		var k := Vector2i(floori(e.position.x / CELL), floori(e.position.y / CELL))
		if cells.has(k): cells[k].append(e)
		else: cells[k] = [e]

func _query(p: Vector2, r: float) -> Array:
	var out := []
	var rc := int(ceil(r / CELL))
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for x in range(c.x - rc, c.x + rc + 1):
		for y in range(c.y - rc, c.y + rc + 1):
			var k := Vector2i(x, y)
			if cells.has(k): out.append_array(cells[k])
	return out

func _boss_list() -> Array:
	var out := []
	for b in bosses:
		if not b.dead: out.append(b)
	return out

func _apply_auras() -> void:
	for e in enemies:
		e.frenzy = false
		e.shield = false
		e.ac_v = 0.0
		e.shiva_v = 0.0
	for h in heroes:
		h.ac_v = 0.0
		h.shiva_v = 0.0
	for h in heroes:
		if h.dead: continue
		var spx: Dictionary = h.sp()
		var acv: float = float(spx.get("ac_aura", 0.0))
		var shv: float = float(spx.get("shiva", 0.0))
		if acv <= 0.0 and shv <= 0.0: continue
		for u in foes_in(h.team, h.position, 900.0):
			u.ac_v = maxf(u.ac_v, acv)
			u.shiva_v = maxf(u.shiva_v, shv)
	for src in enemies:
		if src.dead or src.aura == "": continue
		for e in _query(src.position, 300.0) + _boss_list():
			if e.dead or e.position.distance_to(src.position) > 280.0: continue
			if src.aura == "frenzy": e.frenzy = true
			else: e.shield = true

func _creep_target(e):
	var tt = e.buff_src("taunt")
	if tt != null and not tt.dead:
		return tt
	var best_h = null
	var bd := 1e9
	for h in team0:
		var dd: float = e.position.distance_to(h.position)
		if dd < bd:
			bd = dd
			best_h = h
	return best_h

func _creep_hit(th, amount: float, dtype := "phys", evadable := false) -> void:
	if state != S.PLAY: return
	damage(null, th, amount, "enemy", dtype, Vector2.ZERO, evadable)

func _update_enemies(d: float) -> void:
	var tick := Time.get_ticks_msec() * 0.001
	for e in enemies:
		if e.dead: continue
		e.atk_cd -= d
		e.tick_status(d)
		var th = _creep_target(e)
		var to: Vector2 = (th.position - e.position) if th != null else Vector2.ZERO
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		var spd: float = e.speed * (1.4 if e.frenzy else 1.0) * ((1.0 - e.slow_pct) if e.slow > 0.0 else 1.0)
		var dm: float = e.dmg * (1.4 if e.frenzy else 1.0)
		if e.stun > 0.0:
			e.vel = Vector2.ZERO
		elif th != null and state == S.PLAY:
			_enemy_ai(e, th, d, to, dist, dir, spd, dm)
			if e.has_buff("root"):
				e.vel = Vector2.ZERO
		else:
			e.vel = e.vel.move_toward(Vector2.ZERO, 400.0 * d)
		if not e.boss:
			for o in _query(e.position, e.radius + 30.0):
				if o == e or o.dead: continue
				var dv: Vector2 = e.position - o.position
				var dl := dv.length()
				var minl: float = (e.radius + o.radius) * 0.9
				if dl < minl and dl > 0.01:
					e.position += dv / dl * (minl - dl) * 0.3
		e.position += (e.vel + e.knock + e.pull) * d
		e.knock = e.knock.move_toward(Vector2.ZERO, 1200.0 * d)
		e.pull = Vector2.ZERO
		if th != null and dist > 1500.0 and not e.boss:
			e.position = th.position - dir * 820.0
		var spr: Node2D = e.spr
		if spr is Sprite2D:
			(spr as Sprite2D).frame = int(tick * 6.0 + e.get_instance_id()) % 2
			if e.kind in ["dasher", "sentry"]:
				spr.rotation = e.aim.angle()
			elif e.kind in ["frenzy", "aegis"]:
				spr.rotation = 0.0
			else:
				spr.rotation += d * (2.5 if e.radius < 30 else 0.5)
		var col: Color = e.base_col * 1.35
		col.a = 1.0
		if e.boss: col = Color(1.2, 1.2, 1.2)
		if e.elite: col = col.lerp(Color(2.2, 1.8, 0.6), 0.35)
		if e.kind == "dasher" and e.phase == 1 and int(tick * 24.0) % 2 == 0: col = Color(3.0, 2.6, 1.0)
		if e.kind == "bomber" and e.phase == 1 and int(tick * 20.0) % 2 == 0: col = Color(3.0, 1.5, 0.6)
		if e.charged > 0.0 and int(tick * 8.0) % 2 == 0: col = col.lerp(Color(0.6, 2.0, 2.4), 0.4)
		if e.mark > 0.0: col = col.lerp(Color(2.4, 0.3, 0.4), 0.3)
		if e.flash > 0.0: col = Color(2.4, 2.4, 2.4)
		if e.stun > 0.0: col = col * Color(0.7, 0.7, 0.8)
		spr.modulate = col

func _rate(e) -> float:
	return e.rate * (1.0 + e.shiva_v)

func _melee(e, th, dist: float, dm: float) -> void:
	if dist < e.arange + e.radius + th.radius and e.atk_cd <= 0.0:
		e.atk_cd = _rate(e)
		_creep_hit(th, dm, "phys", true)

func _enemy_ai(e, th, d: float, to: Vector2, dist: float, dir: Vector2, spd: float, dm: float) -> void:
	var hr: float = th.radius
	match e.kind:
		"grunt", "splitter", "mini":
			e.vel = dir * spd if dist > e.radius + hr else Vector2.ZERO
			_melee(e, th, dist, dm)
		"dasher":
			e.timer -= d
			if e.phase == 0:
				e.vel = dir * spd
				e.aim = dir
				if e.timer <= 0.0 and dist < 420.0:
					e.phase = 1
					e.timer = 0.6
				_melee(e, th, dist, dm * 0.5)
			elif e.phase == 1:
				e.vel = Vector2.ZERO
				e.aim = dir
				if e.timer <= 0.0:
					e.phase = 2
					e.timer = 0.4
			else:
				e.vel = e.aim * 720.0
				if dist < e.radius + hr + 8.0 and e.atk_cd <= 0.0:
					e.atk_cd = 1.0
					_creep_hit(th, dm, "phys", true)
				if e.timer <= 0.0:
					e.phase = 0
					e.timer = rng.randf_range(2.0, 3.0)
		"shooter":
			var strafe := dir.orthogonal() * (1.0 if e.get_instance_id() % 2 == 0 else -1.0)
			if dist > e.arange: e.vel = dir * spd
			elif dist < e.arange * 0.65: e.vel = -dir * spd
			else: e.vel = strafe * spd * 0.6
			if e.atk_cd <= 0.0 and dist < e.arange + 60.0:
				e.atk_cd = _rate(e)
				_eshot(e.position, dir * 380.0, dm, "phys", true)
		"sentry":
			e.aim = dir
			if e.phase == 0:
				e.vel = dir * spd if dist > 560.0 else Vector2.ZERO
				if dist <= 600.0:
					e.phase = 1
					e.timer = 0.8
			else:
				e.vel = Vector2.ZERO
				e.timer -= d
				if dist > e.arange + 120.0:
					e.phase = 0
				elif e.timer <= 0.0:
					e.timer = e.rate
					var lead: Vector2 = th.position + th.vel * 0.7
					zones.append({"type": "artillery", "pos": lead, "r": 95.0, "t": 0.0, "delay": 1.25, "dmg": dm, "src": e.position})
					sfx("whistle", rng.randf_range(0.9, 1.1), -10.0, 0.3)
		"colossus":
			e.timer -= d
			if e.phase == 0:
				e.vel = dir * spd if dist > e.radius + hr else Vector2.ZERO
				if e.timer <= 0.0 and dist < 190.0:
					e.phase = 1
					e.timer = 1.0
					zones.append({"type": "slam", "pos": e.position, "r": 170.0, "t": 0.0, "delay": 1.0, "dmg": dm * 1.4, "owner": e})
				else:
					_melee(e, th, dist, dm)
			else:
				e.vel = Vector2.ZERO
				if e.timer <= 0.0:
					e.phase = 0
					e.timer = rng.randf_range(3.5, 5.0)
		"frenzy", "aegis":
			e.vel = dir * spd if dist > 300.0 else (-dir * spd * 0.5 if dist < 220.0 else Vector2.ZERO)
		"mender":
			e.vel = dir * spd if dist > 380.0 else (-dir * spd if dist < 280.0 else dir.orthogonal() * spd * 0.4)
			e.timer -= d
			if e.timer <= 0.0:
				e.timer = e.rate
				var healed := 0
				for o in _query(e.position, 280.0) + _boss_list():
					if o.dead or o.position.distance_to(e.position) > 260.0: continue
					if o.hp < o.max_hp:
						o.hp = minf(o.max_hp, o.hp + o.max_hp * (0.15 if not o.boss else 0.01))
						healed += 1
				if healed > 0:
					_ring(e.position, 20, 260, 0.6, Color(0.5, 2.2, 0.9), 6)
					sfx("mend", 1.0, -12.0, 0.4)
		"bomber":
			if e.phase == 0:
				e.vel = dir * spd
				if dist < e.arange:
					e.phase = 1
					e.timer = 0.7
					sfx("fuse", 1.0, -6.0, 0.1)
			else:
				e.vel = Vector2.ZERO
				e.timer -= d
				if e.timer <= 0.0:
					_bomber_explode(e, dm)
		"hexer":
			e.vel = dir * spd if dist > 480.0 else (-dir * spd if dist < 360.0 else dir.orthogonal() * spd * 0.4)
			e.timer -= d
			if e.timer <= 0.0 and dist < e.arange + 80.0:
				e.timer = e.rate
				zones.append({"type": "silence", "pos": th.position, "r": 150.0, "t": 0.0, "delay": 0.9, "dmg": 0.0})
				sfx("silence", 1.2, -10.0, 0.5)
		"boss":
			_boss_ai(e, th, d, dir, dist, spd, dm)

func _bomber_explode(e, dm: float) -> void:
	var r := 140.0
	for th in team0:
		if th.position.distance_to(e.position) < r + th.radius:
			_creep_hit(th, dm, "magic")
	for o in _query(e.position, r + 40.0):
		if o != e and not o.dead and o.position.distance_to(e.position) < r:
			damage(null, o, dm * 0.5, "enemy", "pure")
	_ring(e.position, 10, r, 0.35, Color(2.4, 1.4, 0.4), 10)
	_burst(e.position, Color(2.4, 1.4, 0.4), 30, 420.0, 0.5, 3.0)
	sfx("explode", 0.8, -2.0)
	shake = maxf(shake, 8.0)
	e.hp = 0.0
	e.dead = true
	kills += 1
	if player != null and not player.dead:
		player.gain_xp(e.xp * (1.0 + t / 900.0) * 0.5)

func _boss_ai(e, th, d: float, dir: Vector2, dist: float, spd: float, dm: float) -> void:
	e.vel = dir * (spd if dist > e.radius + 140.0 else 10.0)
	e.aim = dir
	if dist < e.radius + th.radius and e.atk_cd <= 0.0:
		e.atk_cd = 1.2
		_creep_hit(th, dm, "phys", true)
	e.timer -= d
	var enraged: bool = e.hp < e.max_hp * 0.5
	if e.timer <= 0.0:
		var n: int = 14 + e.tier * 4 + (6 if enraged else 0)
		var off: float = e.phase * 0.23
		for i in n:
			_eshot(e.position, Vector2.RIGHT.rotated(off + TAU * i / n) * (200.0 + 20.0 * e.tier), dm * 0.5)
		e.phase += 1
		e.timer = (1.8 if not enraged else 1.2) - 0.15 * (e.tier - 1)
		sfx("zap", 0.55, -4.0)
		grid.pulse = 0.6
		if e.tier >= 2 and e.phase % 4 == 0:
			var kinds := ["frenzy", "aegis", "mender"] if e.tier == 2 else ["bomber", "bomber", "bomber", "hexer"]
			for k in kinds:
				_spawn(k, e.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * 140.0)
	if enraged or e.tier == 3:
		e.aux_t -= d
		if e.aux_t <= 0.0:
			e.aux_t = 0.12
			e.spin += 0.42
			for k in (3 if e.tier < 3 else 4):
				_eshot(e.position, Vector2.RIGHT.rotated(e.spin + TAU * k / 3.0) * 220.0, dm * 0.35)

func _eshot(pos: Vector2, v: Vector2, dmg: float, dtype := "magic", evadable := false) -> void:
	var b := EShot.new()
	b.position = pos
	b.vel = v
	b.dmg = dmg
	b.dtype = dtype
	b.evadable = evadable
	var s := Sprite2D.new()
	s.texture = TEX["ebullet"]
	s.scale = Vector2(PIX, PIX)
	s.modulate = Color(2.4, 0.8, 2.2)
	b.add_child(s)
	layer_shots.add_child(b)
	eshots.append(b)

# ============================================================ projectiles & zones
func _update_hshots(d: float) -> void:
	for s in hshots:
		if s.dead: continue
		var tv = s.target
		if tv == null or not is_instance_valid(tv) or tv.dead or tv.invuln > 0.0:
			# DOTA: the projectile still flies to the last known position, then fizzles
			s.position = s.position.move_toward(s.last_pos, s.speed * d)
			if s.position.distance_to(s.last_pos) < 4.0: s.dead = true
			continue
		s.last_pos = tv.position
		var to: Vector2 = tv.position - s.position
		s.rotation = to.angle()
		if to.length() < s.speed * d + tv.radius * 0.5:
			s.dead = true
			var ow = s.owner_h
			if ow != null and is_instance_valid(ow):
				ow.attack_hit(tv, s.dmg, s.info)
			_burst(tv.position - to.normalized() * tv.radius * 0.5, Color(1.5, 2.4, 2.6), 4, 180.0, 0.2, 2.0)
			sfx("ahit", rng.randf_range(0.9, 1.2), -12.0, 0.04)
		else:
			s.position += to.normalized() * s.speed * d

func _update_eshots(d: float) -> void:
	for b in eshots:
		if b.dead: continue
		b.position += b.vel * d
		b.life -= d
		b.rotation += d * 6.0
		if b.life <= 0.0:
			b.dead = true
			continue
		if state != S.PLAY: continue
		for th in team0:
			if b.position.distance_to(th.position) < th.radius + 9.0:
				b.dead = true
				_creep_hit(th, b.dmg, b.dtype, b.evadable)
				break

func _update_zones(d: float) -> void:
	var keep := []
	for z in zones:
		z["t"] += d
		if z["type"] == "slam":
			var owner = z.get("owner")
			if owner == null or not is_instance_valid(owner) or owner.dead or owner.stun > 0.0:
				continue  # interrupted by stun / death
		if z["t"] < z["delay"]:
			keep.append(z)
			continue
		var p: Vector2 = z["pos"]
		var r: float = z["r"]
		var inside := []
		if state == S.PLAY:
			for th in team0:
				if th.position.distance_to(p) < r + th.radius * 0.5:
					inside.append(th)
		match z["type"]:
			"artillery":
				for th in inside: _creep_hit(th, z["dmg"], "phys")
				_ring(p, 10, r, 0.3, Color(2.4, 1.2, 0.3), 8)
				_burst(p, Color(2.4, 1.2, 0.4), 18, 300.0, 0.4, 3.0)
				sfx("explode", 1.2, -8.0, 0.05)
			"slam":
				for th in inside:
					_creep_hit(th, z["dmg"], "phys")
					th.slow = 2.0
					th.slow_pct = 0.4
				_ring(p, 20, r, 0.4, Color(2.4, 0.8, 0.5), 12)
				_burst(p, Color(1.8, 0.8, 0.5), 24, 360.0, 0.5, 3.0)
				sfx("slam", 1.0, -2.0)
				shake = maxf(shake, 8.0)
			"silence":
				for th in inside:
					th.silence = 2.5
					if th.cmd == Hero.C.CAST:
						th.cmd = Hero.C.IDLE
					if th.is_player:
						if targeting != "attack": targeting = ""
						_popup(th.position + Vector2(-30, -50), "沉默!", label_set)
				_ring(p, r, 20, 0.3, Color(1.8, 0.6, 2.4), 6)
	zones = keep

func _cleanup() -> void:
	for arr_name in ["enemies", "hshots", "eshots"]:
		var arr: Array = get(arr_name)
		var keep := []
		for n in arr:
			if not is_instance_valid(n): continue
			if n.dead: n.queue_free()
			else: keep.append(n)
		set(arr_name, keep)

# ============================================================ drawing
func _draw_floor() -> void:
	if mode != M.ARENA or state == S.MENU or state == S.SELECT:
		return
	var o := floor_layer
	o.draw_circle(Vector2.ZERO, ARENA_R, Color(0.05, 0.03, 0.12, 0.55))
	o.draw_arc(Vector2.ZERO, ARENA_R, 0, TAU, 160, Color(0.6, 1.2, 2.4, 0.9), 6.0)
	o.draw_arc(Vector2.ZERO, ARENA_R + 14.0, 0, TAU, 160, Color(1.6, 0.4, 2.0, 0.5), 2.0)
	o.draw_arc(Vector2.ZERO, 260.0, 0, TAU, 64, Color(0.6, 0.8, 1.6, 0.35), 2.0)
	for tm in 2:
		var hp := home_pos(tm)
		var c := Color(0.3, 1.6, 1.2) if tm == 0 else Color(2.0, 0.4, 0.4)
		o.draw_circle(hp, FOUNTAIN_R, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.35))
		o.draw_arc(hp, FOUNTAIN_R, 0, TAU, 64, Color(c.r, c.g, c.b, 0.8), 3.0)
		o.draw_arc(hp, 40.0, 0, TAU, 32, c, 4.0)
	for spot in RUNE_SPOTS:
		o.draw_arc(spot, 46.0, 0, TAU, 32, Color(1.4, 1.4, 0.6, 0.5), 2.0)

func _draw_minimap() -> void:
	if mode != M.ARENA or state == S.MENU:
		return
	var m := minimap
	var c := Vector2(92, 92)
	var k := 86.0 / ARENA_R
	m.draw_circle(c, 90.0, Color(0.03, 0.02, 0.08, 0.85))
	m.draw_arc(c, 88.0, 0, TAU, 64, Color(0.5, 1.0, 2.0, 0.8), 2.0)
	for tm in 2:
		m.draw_circle(c + home_pos(tm) * k, FOUNTAIN_R * k, Color(0.3, 1.4, 1.0, 0.4) if tm == 0 else Color(1.6, 0.3, 0.3, 0.4))
	for r in runes:
		m.draw_circle(c + r.position * k, 3.0, Color(1.6, 1.6, 0.6))
	for h in heroes:
		if h.dead: continue
		var col: Color = h.team_color()
		m.draw_circle(c + h.position * k, 5.0 if h.is_player else 3.5, col)
		if h.is_player:
			m.draw_arc(c + h.position * k, 7.0, 0, TAU, 16, Color.WHITE, 1.5)
	var vr := Rect2(c + (cam.get_screen_center_position() - Vector2(640, 360)) * k, Vector2(1280, 720) * k)
	m.draw_rect(vr, Color(1, 1, 1, 0.5), false, 1.0)

func _draw_overlay() -> void:
	if state == S.MENU or state == S.SELECT: return
	var o := overlay
	var tick := Time.get_ticks_msec() * 0.001
	for z in zones:
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
			o.draw_texture_rect(TEX["shell"], Rect2(sp - Vector2(12, 12), Vector2(24, 24)), false, Color(2, 1.6, 1))
	for e in enemies:
		if e.dead: continue
		if e.aura != "":
			var ac := Color(1.0, 0.25, 0.35, 0.38) if e.aura == "frenzy" else Color(0.3, 0.65, 1.0, 0.38)
			o.draw_arc(e.position, 280.0, tick * 0.6, tick * 0.6 + TAU, 64, ac, 1.5)
			o.draw_circle(e.position, 280.0, Color(ac.r, ac.g, ac.b, 0.025))
		elif e.kind == "mender":
			o.draw_arc(e.position, 260.0, 0, TAU, 48, Color(0.4, 1.0, 0.6, 0.25), 1.5)
	for h in heroes:
		h.kit.draw(o)
	var view := Rect2(cam.get_screen_center_position() - Vector2(700, 420), Vector2(1400, 840))
	# heroes: team rings, windup / backswing / cast feedback, bars
	for h in heroes:
		if h.dead or not view.has_point(h.position): continue
		_draw_hero(o, h, tick)
	if selected != null and is_instance_valid(selected) and selected != player and not selected.dead:
		o.draw_arc(selected.position, selected.radius + 10.0, 0, TAU, 32, Color(1.0, 0.85, 0.3, 0.9), 2.5)
	if player != null and not player.dead and player.cmd == Hero.C.ATTACK and player.is_foe(player.cmd_target):
		var ct = player.cmd_target
		o.draw_arc(ct.position, ct.radius + 14.0, tick * 4.0, tick * 4.0 + TAU * 0.75, 24, Color(1.0, 0.3, 0.3, 0.8), 2.0)
	for e in enemies:
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
	if marker_t > 0.0:
		var mk := marker_t / 0.45
		o.draw_arc(marker_pos, 18.0 * mk + 4.0, 0, TAU, 24, Color(marker_col.r, marker_col.g, marker_col.b, mk), 2.5)
	if state == S.PLAY and targeting != "" and player != null and not player.dead:
		_draw_targeting(o)

func _draw_status(o: Node2D, u, top: Vector2, w: float, tick: float) -> void:
	var x := w + 3.0
	if u.charged > 0.0:
		o.draw_texture_rect(TEX["charge"], Rect2(top + Vector2(x, -4), Vector2(14, 14)), false, Color(1.6, 2.2, 2.4))
		x += 16.0
	if u.mark > 0.0:
		o.draw_texture_rect(TEX["mark"], Rect2(top + Vector2(x, -5), Vector2(16, 16)), false, Color(2.4, 0.6, 0.7))
		x += 18.0
	if u.silence > 0.0:
		o.draw_texture_rect(TEX["silence"], Rect2(top + Vector2(x, -6), Vector2(16, 16)), false)
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
			o.draw_texture_rect(TEX["stun"], Rect2(u.position + Vector2(cos(a) * 16.0 - 9.0, -u.radius - 34.0 + sin(a) * 5.0), Vector2(18, 18)), false)

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
		if h.is_foe(h.atk_target):
			o.draw_line(nose, h.atk_target.position, Color(wc.r, wc.g, wc.b, (0.12 + 0.4 * k) * alpha), 1.5)
	elif h.atk_phase == 2:
		var k2: float = clampf(h.atk_t / maxf(h.atk_bs_total, 0.01), 0.0, 1.0)
		o.draw_arc(pos, h.radius + 18.0, -PI / 2.0, -PI / 2.0 + TAU * k2, 40, Color(0.75, 0.75, 0.85, 0.5 * alpha), 2.0)
	if h.cmd == Hero.C.CAST and h.cast_t > 0.0:
		var kc: float = clampf(1.0 - h.cast_t / maxf(h.cast_point_total(), 0.01), 0.0, 1.0)
		var cc: Color = h.def["col"]
		o.draw_arc(pos, h.radius + 22.0, -PI / 2.0, -PI / 2.0 + TAU * kc, 40, cc, 4.0)
		o.draw_circle(nose, 3.0 + 9.0 * kc, Color(cc.r, cc.g, cc.b, 0.5 + 0.5 * kc))
		if not h.is_player:
			o.draw_string(ui_font, pos + Vector2(-40, h.radius + 40.0), str(h.sdef[h.cast_skill]["name"]), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(cc.r, cc.g, cc.b, 0.9))
	var rad: Array = h.sp().get("radiance", [])
	if not rad.is_empty():
		o.draw_arc(pos, float(rad[1]), 0, TAU, 96, Color(1.6, 0.9, 0.3, 0.2), 2.0)
	if h.is_player and mode == M.SURVIVAL:
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
	var pp: Vector2 = player.position
	if targeting == "attack":
		o.draw_arc(pp, player.atk_range(), 0, TAU, 96, Color(1.0, 0.3, 0.3, 0.35), 1.5)
		o.draw_arc(mp, 14.0, 0, TAU, 24, Color(1.0, 0.3, 0.3, 0.9), 2.0)
		o.draw_line(mp + Vector2(-20, 0), mp + Vector2(20, 0), Color(1.0, 0.3, 0.3, 0.9), 2.0)
		o.draw_line(mp + Vector2(0, -20), mp + Vector2(0, 20), Color(1.0, 0.3, 0.3, 0.9), 2.0)
		return
	var st: Dictionary = player.sdef[targeting]
	var col: Color = player.def["col"]
	var ind: String = st.get("ind", "circle")
	var cast_b: float = float(player.ST.get("cast", 0.0))
	match ind:
		"line":
			var dir := (mp - pp).normalized()
			var n: Vector2 = dir.orthogonal() * float(st["width"]) / 2.0
			var ln: float = 0.0 if st.get("range", 0.0) is Array else float(st.get("range", 0.0))
			if ln <= 0.0:
				ln = float(player.kit.ai_meta(targeting).get("reach", 800.0))
			var b: Vector2 = pp + dir * ln
			o.draw_colored_polygon(PackedVector2Array([pp + n, b + n, b - n, pp - n]), Color(col.r * 0.3, col.g * 0.4, col.b * 0.4, 0.18))
			o.draw_polyline(PackedVector2Array([pp + n, b + n, b - n, pp - n, pp + n]), Color(col.r, col.g, col.b, 0.8), 2.0)
		"blink":
			var maxd: float = player.sv(targeting, "dist") + cast_b
			var dest := pp + (mp - pp).limit_length(maxd)
			var r: float = float(st["radius"])
			o.draw_arc(pp, maxd, 0, TAU, 96, Color(1.0, 0.4, 0.9, 0.35), 1.5)
			o.draw_circle(dest, r, Color(1.0, 0.3, 0.9, 0.12))
			o.draw_arc(dest, r, 0, TAU, 64, Color(1.8, 0.5, 1.6, 0.8), 2.0)
		"dash":
			var maxd2: float = player.sv(targeting, "dist") + cast_b
			var u = _unit_at(mp, true)
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
			var cra: float = float(player.kit.cast_range(targeting, null))
			o.draw_arc(pp, cra, 0, TAU, 96, Color(0.4, 1.6, 0.6, 0.35), 1.5)
			var ua = _ally_at(mp)
			if ua != null:
				o.draw_arc(ua.position, ua.radius + 12.0, 0, TAU, 24, Color(0.5, 2.4, 0.8), 3.0)
			else:
				o.draw_arc(mp, 16.0, 0, TAU, 24, Color(0.4, 1.6, 0.6, 0.6), 2.0)
		"unit":
			var cr: float = float(player.kit.cast_range(targeting, null))
			o.draw_arc(pp, cr, 0, TAU, 96, Color(col.r, col.g, col.b, 0.35), 1.5)
			var u2 = _unit_at(mp, true)
			if u2 != null:
				o.draw_arc(u2.position, u2.radius + 12.0, 0, TAU, 24, Color(2.4, 0.5, 0.6), 3.0)
			else:
				o.draw_arc(mp, 16.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.6), 2.0)
		_:
			var cr2: float = float(player.kit.cast_range(targeting, null))
			var rr: float = float(player.kit.skill_radius(targeting))
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

func _popup(pos: Vector2, text: String, ls: LabelSettings) -> void:
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
	shake = maxf(0.0, shake - delta * 40.0)
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 2.0)
	marker_t -= delta
	if (state != S.PLAY and state != S.END) or player == null:
		return
	var p := player
	if mode == M.SURVIVAL:
		time_lbl.text = "%s  /  30:00" % _fmt(t)
		kills_lbl.text = "消灭 %d" % kills
		var nxt := ""
		for i in range(event_i, EVENTS.size()):
			var ev: Array = EVENTS[i]
			if str(ev[1]).begins_with("boss"):
				var names := {"boss1": "Boss · 典狱长", "boss2": "Boss · 典狱长·至尊", "boss3": "最终 Boss · 奇点之心"}
				nxt = "%s  ·  %s" % [names[ev[1]], _fmt(ev[0])]
				break
		event_lbl.text = nxt if nxt != "" else "坚持到 30:00！"
		if not bosses.is_empty():
			var bz = bosses[0]
			if is_instance_valid(bz) and not bz.dead:
				event_lbl.text = "%s   %d / %d   (%d%%)" % [_ename(bz), int(bz.hp), int(bz.max_hp), int(100.0 * bz.hp / bz.max_hp)]
	else:
		score_rt.text = "[center][color=#5fe8ff]霓虹  %d[/color]   [color=#8a92b8]%s[/color]   [color=#ff6a6a]%d  赤潮[/color][/center]" % [team_kills[0], _fmt(t), team_kills[1]]
		var b0 = brain(0)
		var call_txt := ""
		if b0 != null:
			call_txt = "   ·   队伍指令：" + str({"group": "集结推进", "fight": "开团！", "hold": "等待队友复活", "retreat": "撤退"}.get(b0.intent, ""))
		event_lbl.text = ("先拿到 %d 次击倒获胜" % ARENA_KILLS if t < ARENA_LEN else "加时赛：下一次击倒决定胜负") + call_txt
		respawn_lbl.text = ("阵亡 · %d 秒后复活" % int(ceil(p.respawn_t))) if (p.dead and state == S.PLAY) else ""
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
	_update_ui_v3(delta)
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
		if s == targeting:
			icon.modulate = Color(1.8, 1.8, 1.2)
		var pips := sl["pips"] as HBoxContainer
		for i in pips.get_child_count():
			(pips.get_child(i) as ColorRect).color = Color(1.0, 0.85, 0.3) if i < lv else Color(0.25, 0.25, 0.3)
		(sl["plus"] as Button).visible = p.can_learn(s)
	# selection panel
	var sel = selected
	if sel != null and is_instance_valid(sel) and sel != p and not sel.dead:
		sel_panel.visible = true
		var extra := ""
		if sel.charged > 0.0: extra += "  ·  感电"
		if sel.mark > 0.0: extra += "  ·  血印"
		if sel.stun > 0.0: extra += "  ·  晕眩"
		var arm: float = sel.armor_val()
		if sel.is_hero:
			sel_name.text = "%s  Lv.%d  %s" % [sel.display_name(), sel.level, ("（队友）" if sel.team == p.team else "（对方）")]
			sel_hp.text = "生命 %d / %d%s\n护甲 %.1f（物理减伤 %d%%）   魔抗 %d%%\n%d / %d / %d   攻击力 %d" % [int(sel.hp), int(sel.max_hp), extra, arm, int(round((1.0 - armor_mult(arm)) * 100.0)), int(round(sel.mr_val() * 100.0)), sel.kills, sel.deaths, sel.assists, int(sel.atk_dmg())]
			var names := []
			for id in sel.inv:
				names.append(ItemsDB.DB[id]["name"])
			sel_desc.text = "装备：" + ("、".join(PackedStringArray(names)) if not names.is_empty() else "无")
		else:
			sel_name.text = ("精英 " if sel.elite else "") + _ename(sel)
			if sel.frenzy: extra += "  ·  狂怒"
			if sel.shield: extra += "  ·  护盾"
			sel_hp.text = "生命 %d / %d%s\n护甲 %.1f（物理减伤 %d%%）   魔抗 %d%%" % [int(sel.hp), int(sel.max_hp), extra, arm, int(round((1.0 - armor_mult(arm)) * 100.0)), int(round(sel.mr_val() * 100.0))]
			sel_desc.text = EDEF[sel.kind]["desc"]
	else:
		sel_panel.visible = false

func _update_board() -> void:
	var txt := "[center][b][color=#ffd23f]计分板[/color][/b]   [color=#8a92b8]%s · 先拿到 %d 次击倒获胜[/color][/center]\n" % [_fmt(t), ARENA_KILLS]
	for tm in 2:
		var hc := "#5fe8ff" if tm == 0 else "#ff6a6a"
		txt += "\n[color=%s][b]%s  %d[/b][/color]\n" % [hc, ("霓虹队" if tm == 0 else "赤潮队"), team_kills[tm]]
		for h in heroes:
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

# ============================================================ shop & inventory (works for any hero)
func _plan_cost(id: String, avail: Array) -> int:
	var it: Dictionary = ItemsDB.DB[id]
	var comps: Array = it["comps"]
	if comps.is_empty():
		return int(it["cost"])
	var c: int = int(it["recipe"])
	for comp in comps:
		var i := avail.find(comp)
		if i >= 0:
			avail.remove_at(i)
		else:
			c += _plan_cost(comp, avail)
	return c

func shop_price_for(h, id: String) -> int:
	if ItemsDB.DB[id]["cat"] == "consumable":
		return int(ItemsDB.DB[id]["cost"])
	return _plan_cost(id, h.inv.duplicate())

func inv_after(h, id: String) -> int:
	var avail: Array = h.inv.duplicate()
	_plan_cost(id, avail)
	return avail.size() + 1

func sell_cheapest(h) -> void:
	var bi := -1
	var bc := 1e9
	for i in h.inv.size():
		var c := float(ItemsDB.DB[h.inv[i]]["cost"])
		if c < bc:
			bc = c
			bi = i
	if bi >= 0:
		sell_for(h, bi)

## returns "" on success, otherwise the reason
func buy_for(h, id: String, verbose: bool) -> String:
	var it: Dictionary = ItemsDB.DB[id]
	if it["cat"] == "consumable":
		var spc: Dictionary = it["special"]
		if spc.has("shard") and h.shard_owned:
			return "已经使用过魔晶"
		if spc.has("moon") and h.moon_used:
			return "银月之晶只能使用一次"
		if h.gold < float(it["cost"]):
			return "金钱不足"
		h.gold -= float(it["cost"])
		_consume(h, spc)
		if verbose:
			sfx("pickup", 1.3, -4.0)
			var note: String = it["note"]
			if spc.has("shard"):
				note = str(h.def["shard_note"])
			toast("使用 %s：%s" % [it["name"], note], Color(0.6, 1.0, 0.6), 3.0)
	else:
		var avail: Array = h.inv.duplicate()
		var cost := _plan_cost(id, avail)
		if avail.size() + 1 > 6:
			return "物品栏已满（右键物品可出售）"
		if h.gold < float(cost):
			return "金钱不足（还差 %d）" % int(cost - h.gold)
		h.gold -= float(cost)
		var used: int = h.inv.size() - avail.size()
		h.inv = avail
		h.inv.append(id)
		h.recalc()
		if verbose:
			sfx("rune", 1.1, -6.0)
			toast(("合成 %s" if used > 0 else "购买 %s") % it["name"], Color(1.0, 0.85, 0.3), 3.0)
	return ""

func _consume(h, spc: Dictionary) -> void:
	if spc.has("c_hp"): h.regen_buffs.append({"hp": float(spc["c_hp"][0]), "t": float(spc["c_hp"][1])})
	if spc.has("c_mp"): h.regen_buffs.append({"mp": float(spc["c_mp"][0]), "t": float(spc["c_mp"][1])})
	if spc.has("c_mana_now"): h.mana = minf(h.mana_max, h.mana + float(spc["c_mana_now"]))
	if spc.has("c_xp"): h.gain_xp(h.xp_need() * float(spc["c_xp"]))
	if spc.has("shard"): h.shard_owned = true
	if spc.has("moon"):
		h.moon_used = true
		h.recalc()

func sell_for(h, i: int) -> float:
	if i >= h.inv.size(): return 0.0
	var id: String = h.inv[i]
	var v := float(ItemsDB.DB[id]["cost"]) * 0.5
	h.gold += v
	h.inv.remove_at(i)
	h.recalc()
	return v

func _buy(id: String) -> void:
	if state != S.PLAY or player == null: return
	var err := buy_for(player, id, true)
	if err != "":
		_deny(err)
	_refresh_inv()
	_refresh_shop()

func _sell(i: int) -> void:
	if state != S.PLAY or player == null or i >= player.inv.size(): return
	var id: String = player.inv[i]
	var v := sell_for(player, i)
	sfx("select", 0.8, -6.0)
	toast("出售 %s（+%d 金）" % [ItemsDB.DB[id]["name"], int(v)], Color(1.0, 0.85, 0.3), 2.5)
	_refresh_inv()
	_refresh_shop()

func _on_inv_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_sell(i)

func _on_shop_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_buy(id)

const STAT_NAMES := {"str": "力量", "agi": "敏捷", "int": "智力", "all": "全属性", "dmg": "攻击力", "as": "攻击速度",
	"armor": "护甲", "ms": "移动速度", "ms_pct": "% 移动速度", "hp": "生命值", "mana": "魔法值", "hpr": "生命回复",
	"mpr": "魔法回复", "mr": "% 魔法抗性", "ls": "% 吸血", "eva": "% 闪避", "amp": "% 技能增强", "cdr": "% 冷却缩减",
	"cast": "施法距离", "range": "攻击距离"}

func _num(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else ("%.2f" % v).rstrip("0")

func _item_text(id: String, with_price: bool) -> String:
	var it: Dictionary = ItemsDB.DB[id]
	var cat_name: String = {"consumable": "消耗品", "basic": "基础", "advanced": "进阶"}[it["cat"]]
	var out := "[b][color=#ffd23f]%s[/color][/b]  [color=#8a92b8]%s[/color]   [color=#ffcc44]%d 金[/color]\n" % [it["name"], cat_name, int(it["cost"])]
	var stv: Dictionary = it["stats"]
	var parts := []
	for k in stv:
		var nm: String = STAT_NAMES.get(k, k)
		if k == "range" and player != null and bool(player.def["melee"]):
			nm += "（近战无效）"
		parts.append(("+%s%s" if nm.begins_with("%") else "+%s %s") % [_num(float(stv[k])), nm])
	if not parts.is_empty():
		out += "[color=#c8f0ff]" + "   ".join(PackedStringArray(parts)) + "[/color]\n"
	var spc: Dictionary = it["special"]
	var note: String = it["note"]
	for k in spc:
		var v = spc[k]
		match k:
			"crit": out += "[color=#ff8a7a]被动·暴击：%d%% 几率造成 %d%% 伤害[/color]\n" % [int(v[0] * 100), int(v[1] * 100)]
			"chain": out += "[color=#8ad8ff]被动·连锁闪电：攻击有 %d%% 几率释放闪电，弹跳 %d 次，每次 %d 魔法伤害[/color]\n" % [int(v[0] * 100), int(v[1]), int(v[2])]
			"deso": out += "[color=#ff8a7a]被动·腐蚀：攻击使目标护甲 -%d，持续 7 秒[/color]\n" % int(v)
			"skadi": out += "[color=#8ad8ff]被动·霜冻：攻击使目标减速 %d%%，持续 %s 秒[/color]\n" % [int(v[0] * 100), _num(v[1])]
			"mkb": out += "[color=#ffd23f]被动·必中：攻击无法被闪避，并有 %d%% 几率额外造成 %d 魔法伤害[/color]\n" % [int(v[0] * 100), int(v[1])]
			"radiance": out += "[color=#ffb060]被动·灼烧：每秒对 %d 范围内的对手造成 %d 魔法伤害[/color]\n" % [int(v[1]), int(v[0])]
			"ac_aura": out += "[color=#ffd23f]光环：900 范围内对手护甲 -%d[/color]\n" % int(v)
			"shiva": out += "[color=#8ad8ff]光环：900 范围内对手攻击间隔 +%d%%[/color]\n" % int(v * 100)
			"scepter": out += "[color=#6ab0ff]%s[/color]\n" % (str(player.def["scepter_note"]) if player != null else "")
			"heart": out += "[color=#ff8a8a]被动：每秒额外恢复 %s%% 最大生命[/color]\n" % _num(v)
			"shard":
				if player != null: note = str(player.def["shard_note"])
	if note != "":
		out += "[color=#a0ffa0]%s[/color]\n" % note
	var comps: Array = it["comps"]
	if not comps.is_empty() and player != null:
		var avail: Array = player.inv.duplicate()
		var cn := []
		for c in comps:
			var j := avail.find(c)
			var nm2: String = ItemsDB.DB[c]["name"]
			if j >= 0:
				avail.remove_at(j)
				cn.append("[color=#6aff8a]%s ✓[/color]" % nm2)
			else:
				cn.append("%s(%d)" % [nm2, int(ItemsDB.DB[c]["cost"])])
		if int(it["recipe"]) > 0:
			cn.append("卷轴(%d)" % int(it["recipe"]))
		out += "[color=#b0b0c8]合成：[/color]" + " + ".join(PackedStringArray(cn)) + "\n"
		if with_price:
			var need := shop_price_for(player, id)
			if need < int(it["cost"]):
				out += "[color=#ffcc44]已有部分配件，还需 %d 金[/color]\n" % need
	return out

func _strip_bb(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(text, "", true)

func _rt(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", ui_font)
	r.add_theme_font_override("bold_font", ui_font)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size + 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _small_btn(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 28)
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", _panel_style(Color(0.1, 0.08, 0.18, 0.95), Color(0.3, 0.8, 1.0, 0.6)))
	b.add_theme_stylebox_override("hover", _panel_style(Color(0.18, 0.12, 0.3, 0.95), Color(1.0, 0.85, 0.3)))
	b.add_theme_stylebox_override("pressed", _panel_style(Color(0.25, 0.18, 0.05, 0.95), Color(1.0, 0.85, 0.3)))
	return b

func _build_ui_v3() -> void:
	var ap := PanelContainer.new()
	_place(ap, Control.PRESET_BOTTOM_LEFT, 16, -168, 300, 160)
	ap.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.03, 0.09, 0.92), Color(0.3, 0.8, 1.0, 0.6)))
	hud.add_child(ap)
	attr_rt = _rt(15)
	ap.add_child(attr_rt)
	stats_panel = PanelContainer.new()
	_place(stats_panel, Control.PRESET_CENTER_LEFT, 16, -302, 360, 420)
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.02, 0.08, 0.95), Color(0.3, 0.8, 1.0, 0.8)))
	stats_panel.visible = false
	hud.add_child(stats_panel)
	stats_rt = _rt(15)
	stats_panel.add_child(stats_rt)
	var ip := PanelContainer.new()
	_place(ip, Control.PRESET_BOTTOM_RIGHT, -244, -168, 228, 160)
	ip.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.03, 0.09, 0.92), Color(1.0, 0.8, 0.3, 0.6)))
	hud.add_child(ip)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 4)
	ip.add_child(iv)
	var top := HBoxContainer.new()
	iv.add_child(top)
	gold_lbl = _label(20, Color(1.0, 0.82, 0.25))
	gold_lbl.custom_minimum_size = Vector2(110, 0)
	top.add_child(gold_lbl)
	var shop_btn := _small_btn("商店 (B)", 96)
	shop_btn.pressed.connect(func(): _close_shop() if shop_open else _open_shop())
	top.add_child(shop_btn)
	var igrid := GridContainer.new()
	igrid.columns = 3
	igrid.add_theme_constant_override("h_separation", 6)
	igrid.add_theme_constant_override("v_separation", 6)
	iv.add_child(igrid)
	for i in 6:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(66, 50)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_stylebox_override("normal", _panel_style(Color(0.08, 0.07, 0.14), Color(0.3, 0.3, 0.45)))
		b.add_theme_stylebox_override("hover", _panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.add_theme_stylebox_override("pressed", _panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.gui_input.connect(_on_inv_input.bind(i))
		igrid.add_child(b)
		inv_slots.append(b)
	shop = PanelContainer.new()
	_place(shop, Control.PRESET_BOTTOM_RIGHT, -620, -612, 604, 436)
	shop.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.02, 0.07, 0.96), Color(1.0, 0.8, 0.3, 0.9)))
	shop.visible = false
	hud.add_child(shop)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	shop.add_child(sv)
	var head := HBoxContainer.new()
	sv.add_child(head)
	var title := _label(22, Color(1.0, 0.85, 0.35))
	title.text = "商店"
	title.custom_minimum_size = Vector2(70, 0)
	head.add_child(title)
	for tab in [["consumable", "消耗品"], ["basic", "基础"], ["advanced", "进阶合成"]]:
		var tb := _small_btn(tab[1], 96)
		tb.pressed.connect(_set_shop_tab.bind(tab[0]))
		head.add_child(tb)
		shop_tabs[tab[0]] = tb
	shop_gold = _label(18, Color(1.0, 0.82, 0.25), HORIZONTAL_ALIGNMENT_RIGHT)
	shop_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(shop_gold)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(588, 214)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(sc)
	shop_grid = GridContainer.new()
	shop_grid.columns = 8
	shop_grid.add_theme_constant_override("h_separation", 6)
	shop_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(shop_grid)
	var hint := _label(12, Color(0.7, 0.7, 0.85))
	hint.text = "⏸ 商店打开时游戏暂停 · 左/右键购买 · 已有配件自动合成 · 右键物品栏出售（返还 50%）"
	sv.add_child(hint)
	shop_detail = _rt(14)
	shop_detail.custom_minimum_size = Vector2(588, 120)
	sv.add_child(shop_detail)

func _set_shop_tab(tab: String) -> void:
	shop_tab = tab
	sfx("select", 1.4, -12.0)
	_rebuild_shop_grid()

func _rebuild_shop_grid() -> void:
	for c in shop_grid.get_children():
		c.queue_free()
	for id in ItemsDB.ORDER:
		var it: Dictionary = ItemsDB.DB[id]
		if it["cat"] != shop_tab: continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(66, 70)
		b.icon = TEX["it_" + str(id)]
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = str(int(it["cost"]))
		b.add_theme_font_override("font", ui_font)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
		b.add_theme_stylebox_override("normal", _panel_style(Color(0.08, 0.07, 0.14), Color(0.3, 0.3, 0.45)))
		b.add_theme_stylebox_override("hover", _panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.add_theme_stylebox_override("pressed", _panel_style(Color(0.25, 0.18, 0.05), Color(1.0, 0.85, 0.3)))
		b.set_meta("id", id)
		b.pressed.connect(_buy.bind(str(id)))
		b.gui_input.connect(_on_shop_input.bind(str(id)))
		b.mouse_entered.connect(_shop_hover_set.bind(str(id)))
		shop_grid.add_child(b)
	for k in shop_tabs:
		(shop_tabs[k] as Button).modulate = Color(1.3, 1.2, 0.7) if k == shop_tab else Color(0.8, 0.8, 0.9)
	_refresh_shop()

func _shop_hover_set(id: String) -> void:
	shop_hover = id
	shop_detail.text = _item_text(id, true)

func _open_shop() -> void:
	if state != S.PLAY: return
	shop_open = true
	shop.visible = true
	targeting = ""
	right_held = false
	_rebuild_shop_grid()
	sfx("select", 1.2, -8.0)

func _close_shop() -> void:
	shop_open = false
	if shop:
		shop.visible = false

func _refresh_shop() -> void:
	if not shop_open or player == null: return
	shop_gold.text = "金钱 %d" % int(player.gold)
	for b in shop_grid.get_children():
		if not b.has_meta("id"): continue
		var id: String = b.get_meta("id")
		var price := shop_price_for(player, id)
		var it: Dictionary = ItemsDB.DB[id]
		var locked: bool = (it["special"].has("shard") and player.shard_owned) or (it["special"].has("moon") and player.moon_used)
		(b as Button).text = ("已用" if locked else str(price))
		(b as Button).modulate = Color(1, 1, 1) if (player.gold >= price and not locked) else Color(0.5, 0.5, 0.55)
	if shop_hover != "":
		shop_detail.text = _item_text(shop_hover, true)

func _refresh_inv() -> void:
	if player == null: return
	for i in 6:
		var b: Button = inv_slots[i]
		if i < player.inv.size():
			var id: String = player.inv[i]
			b.icon = TEX["it_" + id]
			b.tooltip_text = _strip_bb(_item_text(id, false)) + "\n右键出售（返还 %d 金）" % int(float(ItemsDB.DB[id]["cost"]) * 0.5)
		else:
			b.icon = null
			b.tooltip_text = "空栏位"

var _ui_t := 0.0
func _update_ui_v3(delta: float) -> void:
	var p := player
	gold_lbl.text = "金 %d" % int(p.gold)
	_ui_t -= delta
	if _ui_t > 0.0: return
	_ui_t = 0.25
	if shop_open:
		_refresh_shop()
	if autopilot:
		_refresh_inv()
	var g := func(k: String) -> float: return float(p.ST.get(k, 0.0))
	var bon := func(k: String) -> int: return int(round(float(p.ST.get(k, 0.0)) - float(p.ST.get(k + "_base", 0.0))))
	var prim: String = p.def["primary"]
	var star := {"str": "", "agi": "", "int": ""}
	star[prim] = " ★"
	var pname: String = {"str": "力量", "agi": "敏捷", "int": "智力"}[prim]
	attr_rt.text = "[color=#ff7a6a]力量%s[/color] %d [color=#6aff8a]+%d[/color]   [color=#6aff8a]敏捷%s[/color] %d [color=#6aff8a]+%d[/color]\n[color=#6ab0ff]智力%s[/color] %d [color=#6aff8a]+%d[/color]   [color=#8a92b8]（★ 主属性）[/color]\n攻击力 %d [color=#6aff8a]+%d[/color]    护甲 %.1f\n攻速 %d（%.2f 秒）  移速 %d\n魔抗 %d%%   吸血 %d%%   闪避 %d%%\n[color=#8a92b8]按 C 查看详细属性[/color]" % [
		star["str"], int(p.ST.get("str_base", 0.0)), bon.call("str"), star["agi"], int(p.ST.get("agi_base", 0.0)), bon.call("agi"),
		star["int"], int(p.ST.get("int_base", 0.0)), bon.call("int"),
		int(g.call("dmg_base")), int(g.call("dmg_bonus")), g.call("armor"),
		int(g.call("as")), p.atk_interval(), int(p.move_speed()),
		int(round(g.call("mr") * 100.0)), int(round(g.call("ls") * 100.0)), int(round(g.call("eva") * 100.0))]
	if stats_panel.visible:
		var crit: Array = p.sp().get("crit", [0.0, 1.0])
		var gn: Dictionary = p.def["gain"]
		stats_rt.text = "[b][color=#ffd23f]%s[/color][/b]   [color=#8a92b8]主属性：%s（每点 +1 攻击力）[/color]\n\n[color=#ff7a6a]力量 %d[/color]  → 生命 +22/点，生命回复 +0.1/点\n[color=#6aff8a]敏捷 %d[/color]  → 攻速 +1/点，护甲 +0.17/点\n[color=#6ab0ff]智力 %d[/color]  → 魔法 +12/点，魔法回复 +0.05/点，魔抗 +0.1%%/点\n[color=#8a92b8]成长：力量 +%s / 敏捷 +%s / 智力 +%s 每级[/color]\n\n攻击力  %d + [color=#6aff8a]%d[/color]%s\n攻击速度  %d（攻击间隔 %.2f 秒，基础攻击间隔 %.1f）\n攻击距离  %d%s\n护甲  %.1f（物理伤害减免 %d%%）\n魔法抗性  %d%%\n移动速度  %d\n生命  %d    回复 %.1f / 秒\n魔法  %d    回复 %.1f / 秒\n吸血  %d%%    闪避  %d%%\n技能增强  %d%%    冷却缩减  %d%%\n施法距离加成  +%d\n暴击  %s" % [
			p.def["name"], pname,
			int(g.call("str")), int(g.call("agi")), int(g.call("int")),
			_num(gn["str"]), _num(gn["agi"]), _num(gn["int"]),
			int(g.call("dmg_base")), int(g.call("dmg_bonus")), ("  [color=#ffd23f](双倍伤害神符)[/color]" if p.dd_t > 0.0 else ""),
			int(g.call("as")), p.atk_interval(), float(p.def["bat"]), int(p.atk_range()), ("（近战）" if bool(p.def["melee"]) else ""),
			g.call("armor"), int(round((1.0 - armor_mult(g.call("armor"))) * 100.0)),
			int(round(g.call("mr") * 100.0)), int(p.move_speed()),
			int(p.max_hp), p.hp_regen(), int(p.mana_max), p.mp_regen(),
			int(round(g.call("ls") * 100.0)), int(round(g.call("eva") * 100.0)),
			int(round(g.call("amp") * 100.0)), int(round(g.call("cdr") * 100.0)), int(g.call("cast")),
			("%d%% 几率 ×%s" % [int(crit[0] * 100), _num(crit[1])]) if crit[0] > 0.0 else "无"]
