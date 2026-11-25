extends Node2D
## Training dummy for the 3C experiment: wanders on its own, never attacks.
## kinds: walker (slow wander), runner (fast zig-zag), dodger (side-steps when the charged laser stays on it),
##        heavy (big, slow, lots of hp)

const KINDS := {
	"walker": {"name": "漫步桩", "hp": 520.0, "r": 22.0, "speed": 95.0, "col": Color(0.5, 1.6, 1.0)},
	"runner": {"name": "疾走桩", "hp": 420.0, "r": 18.0, "speed": 230.0, "col": Color(1.8, 1.4, 0.4)},
	"dodger": {"name": "闪避桩", "hp": 460.0, "r": 20.0, "speed": 150.0, "col": Color(1.6, 0.6, 2.0)},
	"heavy": {"name": "重甲桩", "hp": 1500.0, "r": 36.0, "speed": 60.0, "col": Color(1.8, 0.6, 0.5)},
}

var kind := "walker"
var hp := 500.0
var max_hp := 500.0
var radius := 20.0
var speed := 100.0
var col := Color.WHITE
var dead := false
var respawn_t := 0.0
var vel := Vector2.ZERO
var goal := Vector2.ZERO
var turn_t := 0.0
var slow_t := 0.0
var knock := Vector2.ZERO
var idle_t := 0.0          # time since last hit: regenerates to full after 3 s
var flash := 0.0
var aimed_t := 0.0         # dodger: how long the charged laser has been on it
var dodge_cd := 0.0
var dodge_t := 0.0
var dodge_dir := Vector2.ZERO
var mark_t := 0.0          # R: marked by the overwatch eye
var arena                  # exp3c/arena.gd

func setup(k: String, a, p: Vector2) -> void:
	kind = k
	arena = a
	var d: Dictionary = KINDS[k]
	max_hp = d["hp"]
	hp = max_hp
	radius = d["r"]
	speed = d["speed"]
	col = d["col"]
	position = p
	goal = p
	dead = false
	visible = true

func hurt(dmg: float, from: Vector2, push := 0.0) -> void:
	if dead:
		return
	hp -= dmg
	idle_t = 0.0
	flash = 0.12
	if push > 0.0:
		knock += (position - from).normalized() * push
	if hp <= 0.0:
		dead = true
		visible = false
		respawn_t = 2.0

func step(d: float) -> void:
	if dead:
		return
	idle_t += d
	if idle_t > 3.0 and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * 0.8 * d)
	flash = maxf(0.0, flash - d)
	slow_t = maxf(0.0, slow_t - d)
	mark_t = maxf(0.0, mark_t - d)
	dodge_cd = maxf(0.0, dodge_cd - d)
	turn_t -= d
	var spd := speed * (0.6 if slow_t > 0.0 else 1.0)
	match kind:
		"runner":
			if turn_t <= 0.0:
				turn_t = randf_range(0.5, 1.1)
				vel = Vector2.from_angle(randf() * TAU) * spd
		_:
			if turn_t <= 0.0 or position.distance_to(goal) < 30.0:
				turn_t = randf_range(2.0, 4.0)
				goal = arena.random_point(position, 500.0)
			vel = (goal - position).normalized() * spd
	if kind == "dodger":
		_dodge_logic(d)
		if dodge_t > 0.0:
			dodge_t -= d
			vel = dodge_dir * 420.0
	position += (vel + knock) * d
	knock = knock.move_toward(Vector2.ZERO, 900.0 * d)
	var cl: Vector2 = arena.clamp_in(position, radius)
	if cl != position:
		position = cl
		turn_t = 0.0
	queue_redraw()

## side-step when the sniper's charged laser has been on me for a moment
func _dodge_logic(d: float) -> void:
	var s = arena.sniper
	if s.charging and s.charge > 0.2:
		var a: Vector2 = s.position
		var dir: Vector2 = s.aim_dir
		var rel := position - a
		var along := rel.dot(dir)
		var off := absf(rel.cross(dir))
		if along > 0.0 and off < radius + 40.0:
			aimed_t += d
		else:
			aimed_t = maxf(0.0, aimed_t - d)
		if aimed_t > 0.35 and dodge_cd <= 0.0:
			var side := dir.orthogonal()
			dodge_dir = side if rel.cross(dir) < 0.0 else -side
			if randf() < 0.3:
				dodge_dir = -dodge_dir
			dodge_t = 0.32
			dodge_cd = 2.2
			aimed_t = 0.0
	else:
		aimed_t = 0.0

func _draw() -> void:
	var c := col
	if flash > 0.0:
		c = Color(3.0, 3.0, 3.0)
	# training-target look: rings + cross, glowing rim
	draw_circle(Vector2.ZERO, radius, Color(0.06, 0.04, 0.12, 0.95))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, c, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.6, 0, TAU, 24, Color(c.r, c.g, c.b, 0.6), 2.0)
	draw_circle(Vector2.ZERO, radius * 0.22, c)
	draw_line(Vector2(-radius * 0.8, 0), Vector2(radius * 0.8, 0), Color(c.r, c.g, c.b, 0.35), 1.0)
	draw_line(Vector2(0, -radius * 0.8), Vector2(0, radius * 0.8), Color(c.r, c.g, c.b, 0.35), 1.0)
	if slow_t > 0.0:
		draw_arc(Vector2.ZERO, radius + 6.0, 0, TAU, 32, Color(0.6, 1.2, 2.4, 0.8), 2.0)
	if mark_t > 0.0:
		draw_arc(Vector2.ZERO, radius + 11.0, 0, TAU, 32, Color(2.4, 1.6, 0.4, 0.9), 2.0)
	if kind == "dodger" and aimed_t > 0.05:
		draw_string(ThemeDB.fallback_font, Vector2(-5, -radius - 26), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(2.4, 0.8, 2.4))
	# hp bar
	var w := maxf(44.0, radius * 2.4)
	var top := Vector2(-w / 2.0, -radius - 14.0)
	draw_rect(Rect2(top, Vector2(w, 5)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(top + Vector2(1, 1), Vector2((w - 2) * clampf(hp / max_hp, 0.0, 1.0), 3)), Color(1.0, 0.3, 0.3))
