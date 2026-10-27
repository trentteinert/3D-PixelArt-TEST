class_name CharacterModel
extends Node3D
## Wraps the imported hero model: applies the toon shader to its meshes, handles the
## shader-style switch (T key) and a simple bob while moving. Faces -Z.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

enum Style { TOON_OUTLINE, TOON, PLAIN }

## Base color of the toon material (the model has no materials of its own).
@export var albedo := Color("c9d3e8")
## Turn the model around if it walks backwards. glTF models usually face +Z, so 180 is the default.
@export_range(-180.0, 180.0) var facing_offset_degrees := 180.0

var style: Style = Style.TOON_OUTLINE

@onready var _hero: Node3D = $Hero

var _meshes: Array[MeshInstance3D] = []
var _toon_outline: Array[Material] = []
var _toon: Array[Material] = []
var _plain: Array[Material] = []
var _phase := 0.0


func _ready() -> void:
	_hero.rotation.y = deg_to_rad(facing_offset_degrees)
	for child in _hero.find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		var toon := ShaderMaterial.new()
		toon.shader = TOON
		toon.set_shader_parameter("albedo", albedo)
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		var with_outline := toon.duplicate() as ShaderMaterial
		with_outline.next_pass = outline
		var plain := StandardMaterial3D.new()
		plain.albedo_color = albedo
		_meshes.append(mi)
		_toon_outline.append(with_outline)
		_toon.append(toon)
		_plain.append(plain)
		mi.material_override = with_outline


## speed is horizontal speed in m/s, run_speed is the speed that counts as a full run.
func animate(delta: float, speed: float, on_floor: bool, _vertical_speed: float, run_speed: float) -> void:
	var amount := clampf(speed / run_speed, 0.0, 1.0)
	_phase += delta * (6.0 + speed * 1.6)
	var bob := absf(sin(_phase)) * 0.06 * amount if on_floor else 0.0
	_hero.position.y = lerpf(_hero.position.y, bob, 1.0 - exp(-delta * 16.0))


func cycle_style() -> void:
	style = ((style + 1) % Style.size()) as Style
	var materials: Array = [_toon_outline, _toon, _plain][style]
	for i in _meshes.size():
		_meshes[i].material_override = materials[i]
	print("Character style: ", Style.keys()[style])
