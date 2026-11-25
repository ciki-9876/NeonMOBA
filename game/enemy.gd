extends "res://unit.gd"
## (moved out of main.gd)

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
