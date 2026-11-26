extends RefCounted
## Global combat tuning knobs (no dependencies, safe to preload from hero.gd / kit scripts).

## combat feel (2026-11-26 hit-rate pass): global multipliers on top of the hero data, so the data keeps
## its relative values. Faster projectiles + bigger bodies + slower movement = easier to hit.
const BOLT_SPEED_MULT := 1.35     # basic-attack bolts (hero proj_speed incl. item bonuses)
const SHOT_SPEED_MULT := 1.3      # skill shots of data heroes (kit_data "shot")
const HERO_RADIUS_MULT := 1.3     # hero collision / hit radius (the sprite is scaled with it)
const MS_MULT := 0.88             # hero move speed
