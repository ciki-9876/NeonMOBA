extends Node2D
## (moved out of main.gd)

var owner_h: Object = null
var target: Object = null
var dmg := 0.0
var info := {}
var speed := 1100.0
var dead := false
var last_pos := Vector2.ZERO
