# 3D PixelArt Test

Godot 4.3+ sandbox for third-person movement and shader experiments. Open the folder in Godot and press F5.

| Input | Action |
|---|---|
| WASD / left stick | Move (camera-relative) |
| Mouse / right stick | Orbit camera |
| Shift | Sprint |
| Space | Jump (hold for higher) |
| T / Y button | Cycle character shader: toon+outline, toon, plain |
| Esc | Release / recapture mouse |

- `scenes/test_area.tscn` – main scene; layout is built in `scripts/test_area.gd`
- `scenes/player.tscn` – CharacterBody3D, spring-arm camera
- `scripts/player.gd` – movement tuning via exported vars in the Inspector
- `scripts/character_model.gd` – procedural low-poly character
- `shaders/` – `toon`, `outline` (inverted hull), `grid` (world-space floor grid)
