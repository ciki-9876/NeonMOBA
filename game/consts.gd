extends RefCounted
## Shared constants (split out of the old main.gd).

const Hero = preload("res://hero.gd")

const PIX := 3.0

const ICON_COLS := 10

const ARENA_R := 1250.0

const TEAM_SIZE := 3

enum S { MENU, SELECT, PLAY, END }

enum M { ROUNDS }   # survival and the old kill-race arena were retired in stage 1.5

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



