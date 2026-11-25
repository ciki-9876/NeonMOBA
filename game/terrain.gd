extends RefCounted
## Terrain of a map: collision, grid pathfinding, line of sight, brush (草丛) lookup, cover points.
## Pure geometry, deterministic, no nodes: used by game/match.gd (movement, LoS, visibility) and the AI.

const CELL := 40.0
const AGENT_R := 24.0           # obstacles are inflated by this for pathfinding (hero radius + margin)

var circles: Array = []         # [[center: Vector2, r: float], ...]
var rects: Array = []           # [Rect2, ...]
var brush: Array = []           # [[center, r], ...]
var covers: Array = []          # [Vector2, ...]
var stages: Array = []
var arena_r := 1250.0
var astar: AStarGrid2D
var _half := 0

func setup(def: Dictionary, arena_radius: float) -> void:
	arena_r = arena_radius
	circles = def.get("pillars", []).duplicate(true)
	rects = def.get("walls", []).duplicate()
	brush = def.get("brush", []).duplicate(true)
	stages = def.get("stages", []).duplicate()
	_make_covers()
	_build_grid()

## staging spots for a team (team 0 spawns at x < 0, the definitions are written for that side)
func stages_for(tm: int) -> Array:
	var out := []
	for p in stages:
		out.append(p if tm == 0 else Vector2(-p.x, p.y))
	return out

func is_empty() -> bool:
	return circles.is_empty() and rects.is_empty()

# ------------------------------------------------------------ collision
## is a circle (p, r) overlapping any obstacle?
func blocked(p: Vector2, r := 0.0) -> bool:
	for c in circles:
		if p.distance_to(c[0]) < float(c[1]) + r:
			return true
	for rc in rects:
		if (rc as Rect2).grow(r).has_point(p):
			return true
	return false

## move a circle (p, r) out of every obstacle it overlaps (slides along walls)
func push_out(p: Vector2, r: float) -> Vector2:
	for _i in 3:
		var moved := false
		for c in circles:
			var dv: Vector2 = p - c[0]
			var need: float = float(c[1]) + r
			var dl := dv.length()
			if dl < need:
				p = c[0] + (dv / dl if dl > 0.001 else Vector2.RIGHT) * (need + 0.5)
				moved = true
		for rc in rects:
			var g: Rect2 = (rc as Rect2).grow(r)
			if g.has_point(p):
				var dl := p.x - g.position.x
				var dr := g.end.x - p.x
				var du := p.y - g.position.y
				var dd := g.end.y - p.y
				var m: float = minf(minf(dl, dr), minf(du, dd))
				if m == dl: p.x = g.position.x - 0.5
				elif m == dr: p.x = g.end.x + 0.5
				elif m == du: p.y = g.position.y - 0.5
				else: p.y = g.end.y + 0.5
				moved = true
		if not moved:
			break
	return p

# ------------------------------------------------------------ line of sight / sweeps
func _seg_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r

func _seg_rect(a: Vector2, b: Vector2, rc: Rect2) -> bool:
	if rc.has_point(a) or rc.has_point(b):
		return true
	# Liang–Barsky
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for k in 4:
		var p := 0.0
		var q := 0.0
		match k:
			0: p = -d.x; q = a.x - rc.position.x
			1: p = d.x; q = rc.end.x - a.x
			2: p = -d.y; q = a.y - rc.position.y
			3: p = d.y; q = rc.end.y - a.y
		if absf(p) < 0.00001:
			if q < 0.0:
				return false
		else:
			var r := q / p
			if p < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
			if t0 > t1:
				return false
	return true

## does the segment a->b (with thickness pad) touch an obstacle?  (line of sight when pad = 0)
func seg_blocked(a: Vector2, b: Vector2, pad := 0.0) -> bool:
	for c in circles:
		if _seg_circle(a, b, c[0], float(c[1]) + pad):
			return true
	for rc in rects:
		if _seg_rect(a, b, (rc as Rect2).grow(pad)):
			return true
	return false

func has_los(a: Vector2, b: Vector2) -> bool:
	return not seg_blocked(a, b, 0.0)

## furthest point along a->b a circle of radius r can travel before touching an obstacle (dashes)
func sweep(a: Vector2, b: Vector2, r: float) -> Vector2:
	if not seg_blocked(a, b, r):
		return b
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var mid := (lo + hi) * 0.5
		if seg_blocked(a, a.lerp(b, mid), r):
			hi = mid
		else:
			lo = mid
	return a.lerp(b, lo)

# ------------------------------------------------------------ brush
## index of the brush that contains p, -1 when none
func brush_at(p: Vector2) -> int:
	for i in brush.size():
		if p.distance_to(brush[i][0]) <= float(brush[i][1]):
			return i
	return -1

# ------------------------------------------------------------ pathfinding (AStarGrid2D on a 40px grid)
func _build_grid() -> void:
	_half = int(ceil(arena_r / CELL)) + 1
	astar = AStarGrid2D.new()
	astar.region = Rect2i(-_half, -_half, _half * 2 + 1, _half * 2 + 1)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2.ZERO
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in range(-_half, _half + 1):
		for x in range(-_half, _half + 1):
			var p := Vector2(x, y) * CELL
			if p.length() > arena_r - AGENT_R or blocked(p, AGENT_R):
				astar.set_point_solid(Vector2i(x, y), true)

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(round(p.x / CELL)), -_half, _half), clampi(int(round(p.y / CELL)), -_half, _half))

func _free_cell(p: Vector2) -> Vector2i:
	var c := _cell(p)
	if not astar.is_point_solid(c):
		return c
	for ring in range(1, 6):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var n := c + Vector2i(dx, dy)
				if astar.region.has_point(n) and not astar.is_point_solid(n):
					return n
	return c

## path from a to b for a unit of radius r, string-pulled (only the corners that matter)
func path(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not seg_blocked(a, b, r):
		out.append(b)
		return out
	var pts := astar.get_point_path(_free_cell(a), _free_cell(b))
	if pts.is_empty():
		out.append(b)
		return out
	pts[pts.size() - 1] = b
	var cur := a
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and seg_blocked(cur, pts[j], r):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out

# ------------------------------------------------------------ cover points (for the AI)
func _make_covers() -> void:
	covers = []
	for c in circles:
		for k in 8:
			var a := TAU * k / 8.0
			covers.append(c[0] + Vector2.from_angle(a) * (float(c[1]) + 34.0))
	for rc in rects:
		var r: Rect2 = rc
		var cy := r.get_center().y
		for x in [r.position.x - 34.0, r.end.x + 34.0]:
			covers.append(Vector2(x, cy))
		for x in [r.position.x + r.size.x * 0.25, r.get_center().x, r.position.x + r.size.x * 0.75]:
			covers.append(Vector2(x, r.position.y - 34.0))
			covers.append(Vector2(x, r.end.y + 34.0))

## best cover near p that hides from all `threats` (positions); Vector2.INF when none within max_d
func best_cover(p: Vector2, threats: Array, max_d: float, prefer: Vector2) -> Vector2:
	var best := Vector2.INF
	var bs := -1e9
	for cp in covers:
		var d: float = p.distance_to(cp)
		if d > max_d or blocked(cp, 18.0):
			continue
		var hidden := 0
		for tp in threats:
			if not has_los(tp, cp):
				hidden += 1
		if hidden == 0:
			continue
		var s: float = 300.0 * float(hidden) / float(maxi(threats.size(), 1)) - d * 0.6 - cp.distance_to(prefer) * 0.2
		if s > bs:
			bs = s
			best = cp
	return best
