class_name CharacterModel
extends Node3D
## Low-poly character built from a handful of capsules/spheres, animated procedurally.
## Faces -Z. Cycle the shader style with cycle_style() to compare looks.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

const SKIN := Color("f2c29b")
const SHIRT := Color("3f7fd9")
const PANTS := Color("33384d")
const SHOES := Color("e8e8e8")

enum Style { TOON_OUTLINE, TOON, PLAIN }

var style: Style = Style.TOON_OUTLINE

var _parts: Array[MeshInstance3D] = []
var _colors: Array[Color] = []
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _body: Node3D
var _phase := 0.0


func _ready() -> void:
	_body = Node3D.new()
	_body.position.y = 1.0
	add_child(_body)

	_add_capsule(_body, Vector3(0, 0.0, 0), 0.26, 0.85, SHIRT)              # torso
	_add_sphere(_body, Vector3(0, 0.62, 0), 0.24, SKIN)                     # head
	_add_sphere(_body, Vector3(-0.09, 0.66, -0.2), 0.04, PANTS)        # eyes
	_add_sphere(_body, Vector3(0.09, 0.66, -0.2), 0.04, PANTS)

	_left_arm = _add_limb(_body, Vector3(-0.34, 0.25, 0), 0.09, 0.55, SKIN)
	_right_arm = _add_limb(_body, Vector3(0.34, 0.25, 0), 0.09, 0.55, SKIN)
	_left_leg = _add_limb(self, Vector3(-0.13, 0.85, 0), 0.11, 0.7, PANTS)
	_right_leg = _add_limb(self, Vector3(0.13, 0.85, 0), 0.11, 0.7, PANTS)
	_add_sphere(_left_leg, Vector3(0, -0.72, -0.04), 0.13, SHOES)
	_add_sphere(_right_leg, Vector3(0, -0.72, -0.04), 0.13, SHOES)

	apply_style()


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
	apply_style()
	print("Character style: ", Style.keys()[style])


func apply_style() -> void:
	for i in _parts.size():
		_parts[i].material_override = _make_material(_colors[i])


func _make_material(color: Color) -> Material:
	if style == Style.PLAIN:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		return m
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter("albedo", color)
	if style == Style.TOON_OUTLINE:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		mat.next_pass = outline
	return mat


func _register(mi: MeshInstance3D, parent: Node3D, pos: Vector3, color: Color) -> void:
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	_parts.append(mi)
	_colors.append(color)


func _add_capsule(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_register(mi, parent, pos, color)


func _add_sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_register(mi, parent, pos, color)


## A limb pivots at its top so rotating the pivot swings it like a joint.
func _add_limb(parent: Node3D, pivot_pos: Vector3, radius: float, length: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	_add_capsule(pivot, Vector3(0, -length * 0.5, 0), radius, length, color)
	return pivot
