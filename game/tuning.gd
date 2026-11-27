extends RefCounted
## Global combat tuning knobs (no dependencies, safe to preload from hero.gd / kit scripts).

## Global multipliers on top of hero data, so individual values keep their relative scale.
## Latest adjustment: 30% slower movement and 100% faster basic and skill projectiles.
const BOLT_SPEED_MULT := 2.7      # basic-attack bolts (hero proj_speed incl. item bonuses): 1.35 × 2
const SHOT_SPEED_MULT := 2.6      # skill shots of data heroes (kit_data "shot"): 1.3 × 2
const HERO_RADIUS_MULT := 1.3     # hero collision / hit radius (the sprite is scaled with it)
const MS_MULT := 0.616            # hero move speed: 0.88 × 0.7
const ATTACK_SPEED_MULT := 4.0    # global hero basic-attack rate
const ATTACK_DAMAGE_MULT := 0.5   # global hero attack power, including bonus attack damage
