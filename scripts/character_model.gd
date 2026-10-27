class_name CharacterModel
extends Node3D
## Procedural animation + shader-style switching for the character nodes in player.tscn.
## Faces -Z. Cycle the shader style with cycle_style() to compare looks.

enum Style { TOON_OUTLINE, TOON, PLAIN }

## Shader look of the character. TOON_OUTLINE adds the dark outline; PLAIN is an unshaded-style standard material.
@export var style: Style = Style.TOON_OUTLINE:
	set(value):
		style = value
		_apply_style()
## The soft white edge glow from the toon shader.
@export var rim_light := true:
	set(value):
		rim_light = value
		_apply_rim()

@onready var _body: Node3D = $Body
@onready var _left_arm: Node3D = $Body/LeftArm
@onready var _right_arm: Node3D = $Body/RightArm
@onready var _left_leg: Node3D = $LeftLeg
@onready var _right_leg: Node3D = $RightLeg

var _meshes: Array[MeshInstance3D] = []
var _toon_outline: Array[Material] = []
var _toon: Array[Material] = []
var _plain: Array[Material] = []
var _phase := 0.0
var _rim_strength := 0.25


func _ready() -> void:
	# Build the three style variants from the materials set up in the scene.
	for child in find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		var with_outline := mi.material_override as ShaderMaterial
		var no_outline := with_outline.duplicate() as ShaderMaterial
		no_outline.next_pass = null
		var plain := StandardMaterial3D.new()
		plain.albedo_color = with_outline.get_shader_parameter("albedo")
		_meshes.append(mi)
		_toon_outline.append(with_outline)
		_toon.append(no_outline)
		_plain.append(plain)
	_rim_strength = (_toon_outline[0] as ShaderMaterial).get_shader_parameter("rim_strength")
	_apply_style()
	_apply_rim()


## speed is horizontal speed in m/s, run_speed is the speed that counts as a full stride.
func animate(delta: float, speed: float, on_floor: bool, vertical_speed: float, run_speed: float) -> void:
	var amount := clampf(speed / run_speed, 0.0, 1.0)
	_phase += delta * (6.0 + speed * 1.6)
	var swing := sin(_phase) * 0.9 * amount
	var bob := absf(sin(_phase)) * 0.06 * amount

	var l_arm := swing
	var r_arm := -swing
	var l_leg := -swing
	var r_leg := swing
	if not on_floor:
		var air := clampf(vertical_speed * 0.08, -0.6, 0.6)
		l_arm = -1.6 + air
		r_arm = -1.6 + air
		l_leg = 0.5
		r_leg = -0.3
		bob = 0.0

	var t := 1.0 - exp(-delta * 16.0)
	_left_arm.rotation.x = lerpf(_left_arm.rotation.x, l_arm, t)
	_right_arm.rotation.x = lerpf(_right_arm.rotation.x, r_arm, t)
	_left_leg.rotation.x = lerpf(_left_leg.rotation.x, l_leg, t)
	_right_leg.rotation.x = lerpf(_right_leg.rotation.x, r_leg, t)
	_body.position.y = lerpf(_body.position.y, 1.0 + bob, t)
	_body.rotation.x = lerpf(_body.rotation.x, -0.15 * amount, t)  # lean into the run


func cycle_style() -> void:
	style = ((style + 1) % Style.size()) as Style
	print("Character style: ", Style.keys()[style])


func _apply_style() -> void:
	if _meshes.is_empty():
		return  # not ready yet; _ready applies it
	var materials: Array = [_toon_outline, _toon, _plain][style]
	for i in _meshes.size():
		_meshes[i].material_override = materials[i]


func _apply_rim() -> void:
	if _meshes.is_empty():
		return
	var strength := _rim_strength if rim_light else 0.0
	for m in _toon_outline + _toon:
		(m as ShaderMaterial).set_shader_parameter("rim_strength", strength)
