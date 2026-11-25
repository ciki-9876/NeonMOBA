extends RefCounted
## Shared constants (split out of the old main.gd).

const Hero = preload("res://hero.gd")

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

enum M { SURVIVAL, ARENA, ROUNDS }

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

