extends RefCounted
## Map definitions for the round mode. A map = a win condition (mechanic) + terrain.
## Terrain pieces (all in world units, arena radius C.ARENA_R = 1250, spawns at (±1000, 0)):
##   pillars : [[center, radius], ...]        block movement, skillshots and line of sight
##   walls   : [Rect2, ...]                     same, axis aligned boxes
##   brush   : [[center, radius], ...]          草丛: units inside are hidden from the other team
##   lanes   : approach directions the team AI may pick each round (degrees, 0 = straight at the core)
## Cover points are generated from pillars and wall ends (game/terrain.gd).

const MAPS := {
	"core_pillars": {
		"name": "核心 · 立柱", "mechanic": "core",
		"desc": "四根立柱围住中央核心，上下两道长墙隔出侧翼通道，通道和出生口附近有草丛。",
		"pillars": [[Vector2(-400, -250), 58.0], [Vector2(400, -250), 58.0], [Vector2(-400, 250), 58.0], [Vector2(400, 250), 58.0]],
		"walls": [Rect2(-300, -580, 600, 60), Rect2(-300, 520, 600, 60)],
		"brush": [[Vector2(0, -800), 170.0], [Vector2(0, 800), 170.0],
			[Vector2(-640, -470), 115.0], [Vector2(-640, 470), 115.0], [Vector2(640, -470), 115.0], [Vector2(640, 470), 115.0]],
		# staging spots before the core opens, for the team whose spawn is on the left (x < 0); mirrored for the other.
		# 0 = centre, 1/2 = hide in the near flank brush and come in around the wall end
		"stages": [Vector2(-380, 0), Vector2(-640, -470), Vector2(-640, 470)],
	},
	"core_ring": {
		"name": "核心 · 环柱", "mechanic": "core",
		"desc": "六根立柱环绕核心，柱间可以穿插；四角各有一块草丛，适合绕后。",
		"pillars": [[Vector2(330, 0), 52.0], [Vector2(165, 286), 52.0], [Vector2(-165, 286), 52.0],
			[Vector2(-330, 0), 52.0], [Vector2(-165, -286), 52.0], [Vector2(165, -286), 52.0]],
		"walls": [],
		"brush": [[Vector2(-560, -620), 140.0], [Vector2(560, -620), 140.0], [Vector2(-560, 620), 140.0], [Vector2(560, 620), 140.0]],
		"stages": [Vector2(-520, 0), Vector2(-560, -620), Vector2(-560, 620)],
	},
	"core_gate": {
		"name": "核心 · 闸门", "mechanic": "core",
		"desc": "两侧出生口前各有一道短墙挡住正面，只能从上下两个缺口绕进核心；中路上下有大草丛。",
		"pillars": [[Vector2(0, -420), 64.0], [Vector2(0, 420), 64.0]],
		"walls": [Rect2(-620, -230, 60, 460), Rect2(560, -230, 60, 460)],
		"brush": [[Vector2(-300, -700), 150.0], [Vector2(300, -700), 150.0], [Vector2(-300, 700), 150.0], [Vector2(300, 700), 150.0]],
		"stages": [Vector2(-700, -360), Vector2(-700, 360), Vector2(-300, -700)],
	},
	"core_open": {
		"name": "核心 · 开阔", "mechanic": "core",
		"desc": "没有任何遮挡的圆形竞技场，正面对拼。",
		"pillars": [], "walls": [], "brush": [], "stages": [],
	},
}
const ORDER := ["core_pillars", "core_ring", "core_gate", "core_open"]
## the map pool of league series (BO3 map veto, docs/design/赛事层设计.md)
const POOL := ["core_pillars", "core_ring", "core_gate", "core_open"]
const DEFAULT := "core_pillars"
