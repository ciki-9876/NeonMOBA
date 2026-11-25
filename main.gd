extends Node2D
## NEON DRIFT / NeonMOBA — composition root.
## Builds the modules, wires them together and drives the fixed-step simulation loop.
##
##   game/match.gd          simulation of one match (units, combat, rules). Runs headless: see sim/sim_cli.gd
##   view/presenter.gd      effects, audio, camera, world drawing
##   ui/hud.gd              in-game HUD, scoreboard, end screen
##   ui/shop_ui.gd          shop & inventory UI
##   ui/menus.gd            menus and match setup
##   input/player_input.gd  player control and debug keys
## Architecture notes: docs/架构说明.md

const C = preload("res://game/consts.gd")
const MatchT = preload("res://game/match.gd")
const Presenter = preload("res://view/presenter.gd")
const Hud = preload("res://ui/hud.gd")
const ShopUI = preload("res://ui/shop_ui.gd")
const Menus = preload("res://ui/menus.gd")
const PlayerInput = preload("res://input/player_input.gd")

## at most this many simulation steps per rendered frame (prevents a spiral after a hitch)
const MAX_STEPS := 6

var world: Node2D
var gm: MatchT
var vw: Presenter
var hd: Hud
var shp: ShopUI
var mnu: Menus
var inp: PlayerInput
var acc := 0.0

func _ready() -> void:
	gm = MatchT.new()
	vw = Presenter.new()
	hd = Hud.new()
	shp = ShopUI.new()
	mnu = Menus.new()
	inp = PlayerInput.new()
	gm.vw = vw
	gm.hd = hd
	gm.shp = shp
	for m in [vw, hd, shp, mnu, inp]:
		m.gm = gm
		for f in ["vw", "hd", "shp", "mnu", "inp"]:
			if f in m and m.get(f) == null and get(f) != m:
				m.set(f, get(f))
		if "app" in m:
			m.app = self
	vw.ui_font = SystemFont.new()
	vw.ui_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	vw.ui_font.font_weight = 600
	ThemeDB.fallback_font = vw.ui_font
	world = Node2D.new()
	add_child(world)
	add_child(vw)
	vw._load_view_assets()
	vw._build_env()
	vw.build_below(world)
	world.add_child(gm)          # match _ready loads textures and creates the unit layers
	vw.build_above(world)
	add_child(inp)
	add_child(hd)
	add_child(shp)
	add_child(mnu)
	gm.world_cleared.connect(vw._v_world_cleared)
	gm.world_cleared.connect(hd._hud_world_cleared)
	gm.world_cleared.connect(inp._inp_world_cleared)
	gm.match_started.connect(vw._v_match_started)
	gm.match_started.connect(hd._hud_match_started)
	gm.match_started.connect(inp._inp_match_started)
	gm.match_ended.connect(hd._hud_match_ended)
	gm.match_ended.connect(inp._inp_match_ended)
	gm.round_started.connect(hd._hud_round_started)
	gm.round_live.connect(hd._hud_round_live)
	gm.round_ended.connect(hd._hud_round_ended)
	hd._build_ui()
	mnu._build_menu()
	vw._build_audio()
	hd._load_best()
	mnu._show_menu()

func _process(delta: float) -> void:
	hd._update_fx_ui(delta)
	if gm.state == C.S.MENU or gm.state == C.S.SELECT:
		vw.menu_frame(delta)
		return
	if gm.paused or shp.shop_open:
		vw.overlay.queue_redraw()
		return
	if gm.hitstop > 0.0:
		gm.hitstop -= delta
		return
	if gm.state == C.S.PLAY:
		inp._hold_move(delta)
	acc = minf(acc + delta, MatchT.DT * MAX_STEPS)
	while acc >= MatchT.DT:
		acc -= MatchT.DT
		gm.step(MatchT.DT)
	inp._inp_tick()
	vw.frame(delta)
