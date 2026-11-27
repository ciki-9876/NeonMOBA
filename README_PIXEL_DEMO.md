# NEON DRIFT · 64-BIT PIXEL DEMO

This is a separate visual demo copy of the project. The original `NeonMOBA` folder was not changed.

## Open

Open `project.godot` in Godot 4.7, then run the main scene.

## Pixel-art pass

- A 640×360 screen-space pixel pass is enlarged to the existing 1280×720 world, while the HUD remains crisp and keeps its original coordinate system.
- Bloom and HDR are disabled so edges stay crisp and colors do not wash out.
- The arena floor now uses broad, low-contrast color planes; earlier 64×64 Aseprite and Blender studies remain in `art/` as editable references.
- Bushes, pillars, and walls use a small number of large color shapes so cover and lanes stand out from the ground.
- The bundled Fusion Pixel 12px proportional font includes Simplified Chinese and Latin glyphs, with its SIL Open Font License and upstream license files beside it.
- The rendering pass affects visuals only; match simulation and rules remain as in the source copy.

The art direction is inspired by 64-bit-era pixel games; “64-bit” here describes the visual reference, not the texture resolution or CPU architecture.
