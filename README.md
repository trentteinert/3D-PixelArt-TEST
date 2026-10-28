# 3D PixelArt Test

Godot 4.3+ sandbox for third-person movement and shader experiments. Open the folder in Godot and press F5.

| Input | Action |
|---|---|
| WASD / left stick | Move (camera-relative) |
| Mouse / right stick | Orbit camera |
| Shift | Sprint |
| Space | Jump (hold for higher) |
| T / Y button | Cycle character shader: toon+outline, toon, plain |
| E / X button | Toggle edge highlight shader |
| Esc | Release / recapture mouse |

- `scenes/test_area.tscn` – main scene; every object is a node (edit under `Level/`), inside a SubViewport for pixelation
- `scenes/player.tscn` – CharacterBody3D, character mesh nodes, spring-arm camera
- `scripts/player.gd` – movement tuning via exported vars in the Inspector
- `scripts/character_model.gd` – toon materials + idle/walk/run/jump animation switching for `models/hero.fbx`
- `shaders/` – `toon`, `outline` (inverted hull), `grid` (world-space floor grid)
