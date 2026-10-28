class_name CharacterModel
extends Node3D
## Wraps the imported Mixamo hero: applies the toon shader to its meshes, plays idle / walk /
## run / jump animations, and handles the shader-style switch (T key). Faces -Z.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

## Animation files exported from Mixamo on the same skeleton as the hero.
const ANIMATION_FILES := {
	"run": "res://models/animations/run.fbx",
	"jump": "res://models/animations/jump.fbx",
}
const LIBRARY := "locomotion"

enum Style { TOON_OUTLINE, TOON, PLAIN }

## Base color of the toon material.
@export var albedo := Color("c9d3e8")
## Turn the model around if it walks backwards. Mixamo models face +Z, so 180 is the default.
@export_range(-180.0, 180.0) var facing_offset_degrees := 180.0
## Speeds (m/s) that switch between idle, walk and run.
@export var walk_threshold := 0.5
@export var run_threshold := 7.0
@export var blend_time := 0.2
## Walking reuses the run animation at this playback speed (1.0 = same as running).
@export_range(0.1, 1.5) var walk_speed_scale := 1
## Scale the run/walk animation with actual ground speed so the feet don't skate.
@export var sync_animation_to_speed := true
## Ground speed (m/s) at which the run animation looks right at normal playback speed.
@export var run_anim_speed := 7.0

@export_group("Lean")
## Constant forward tilt (degrees) at full speed.
@export var speed_lean_degrees := 4.0
## Extra tilt (degrees) per m/s² of acceleration: leans forward when speeding up, back when braking.
@export var accel_lean_degrees := 0.6
## Sideways banking (degrees) per m/s² of sideways acceleration, i.e. into turns.
@export var turn_lean_degrees := 0.7
@export var max_lean_degrees := 12.0
## How quickly the lean follows (higher = snappier).
@export var lean_smoothing := 10.0

@export_group("Jump Timing")
## Where in the jump animation (seconds) to start when you leave the ground. Skip the crouch by raising this.
@export var jump_start_time := 0.3
## Playback speed of the jump animation.
@export_range(0.1, 3.0) var jump_speed_scale := 1.0
## Freeze the jump pose at this time (seconds) while still in the air. 0 = play to the end, then hold.
@export var jump_hold_time := 0.0

var style: Style = Style.TOON_OUTLINE

@onready var _hero: Node3D = $Hero

var _meshes: Array[MeshInstance3D] = []
var _toon_outline: Array[Material] = []
var _toon: Array[Material] = []
var _plain: Array[Material] = []
var _anim: AnimationPlayer
var _state := ""


func _ready() -> void:
	_hero.rotation.y = deg_to_rad(facing_offset_degrees)
	_setup_materials()
	_setup_animations()


## speed is horizontal speed in m/s. run_speed is unused (kept so player.gd's call stays the same).
func animate(_delta: float, speed: float, on_floor: bool, _vertical_speed: float, _run_speed: float) -> void:
	if _anim == null:
		return
	if not on_floor:
		_play("jump", "jump", false, jump_speed_scale, jump_start_time)
		if jump_hold_time > 0.0 and _anim.current_animation_position >= jump_hold_time:
			_anim.pause()
	elif speed > run_threshold:
		_play("run", "run")
		_sync_speed(speed, 1.0)
	elif speed > walk_threshold:
		_play("walk", "run", true, walk_speed_scale)
		_sync_speed(speed, walk_speed_scale)
	else:
		_play("idle", "idle")


func _sync_speed(speed: float, fallback: float) -> void:
	_anim.speed_scale = clampf(speed / run_anim_speed, 0.4, 2.0) if sync_animation_to_speed else fallback


## Tilts the whole model. local_accel is horizontal acceleration in the model's own frame
## (x = right, z = back); speed_fraction is 0..1 of top speed.
func lean(delta: float, local_accel: Vector3, speed_fraction: float) -> void:
	var limit := deg_to_rad(max_lean_degrees)
	# Negative pitch tips the head toward -Z (forward).
	var pitch := deg_to_rad(-speed_lean_degrees * speed_fraction + accel_lean_degrees * local_accel.z)
	# Negative roll tips the head toward +X (right).
	var roll := deg_to_rad(-turn_lean_degrees * local_accel.x)
	var t := 1.0 - exp(-lean_smoothing * delta)
	rotation.x = lerpf(rotation.x, clampf(pitch, -limit, limit), t)
	rotation.z = lerpf(rotation.z, clampf(roll, -limit, limit), t)


func cycle_style() -> void:
	style = ((style + 1) % Style.size()) as Style
	var materials: Array = [_toon_outline, _toon, _plain][style]
	for i in _meshes.size():
		_meshes[i].material_override = materials[i]
	print("Character style: ", Style.keys()[style])


## state is what we're doing; anim_name is which clip plays for it (walk reuses "run").
func _play(state: String, anim_name: String, loop := true, speed := 1.0, start_time := 0.0) -> void:
	if _state == state:
		return
	_state = state
	var full := "%s/%s" % [LIBRARY, anim_name]
	if _anim.has_animation(full):
		_anim.get_animation(full).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		_anim.speed_scale = speed
		_anim.play(full, blend_time)
		if start_time > 0.0:
			_anim.seek(start_time, true)


func _setup_materials() -> void:
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


# The hero file carries the idle animation; walk/run/jump come from separate Mixamo files.
# Their tracks are re-pointed at the hero's skeleton and their forward root motion is removed,
# since the character controller does the moving.
func _setup_animations() -> void:
	_anim = _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := _hero.find_child("Skeleton3D", true, false) as Skeleton3D
	if _anim == null or skeleton == null:
		push_warning("CharacterModel: hero has no AnimationPlayer/Skeleton3D, animations disabled")
		_anim = null
		return

	var skeleton_path := _anim.get_node(_anim.root_node).get_path_to(skeleton)
	var library := AnimationLibrary.new()

	var idle := _first_animation(_anim)
	if idle:
		library.add_animation("idle", _retarget(idle.duplicate(), skeleton, skeleton_path))
	for anim_name in ANIMATION_FILES:
		var scene := load(ANIMATION_FILES[anim_name]) as PackedScene
		if scene == null:
			push_warning("CharacterModel: could not load " + ANIMATION_FILES[anim_name])
			continue
		var inst := scene.instantiate()
		var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var source := _first_animation(player) if player else null
		if source:
			library.add_animation(anim_name, _retarget(source.duplicate(), skeleton, skeleton_path))
		inst.free()

	_anim.add_animation_library(LIBRARY, library)
	_play("idle", "idle")


func _first_animation(player: AnimationPlayer) -> Animation:
	for n in player.get_animation_list():
		if n != "RESET":
			return player.get_animation(n)
	return null


func _retarget(anim: Animation, skeleton: Skeleton3D, skeleton_path: NodePath) -> Animation:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var bone := String(anim.track_get_path(i).get_concatenated_subnames())
		if bone == "" or skeleton.find_bone(bone) == -1:
			anim.remove_track(i)
			continue
		anim.track_set_path(i, NodePath("%s:%s" % [skeleton_path, bone]))
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and bone.ends_with("Hips"):
			_strip_horizontal_motion(anim, i)
	return anim


func _strip_horizontal_motion(anim: Animation, track: int) -> void:
	var count := anim.track_get_key_count(track)
	if count == 0:
		return
	var first: Vector3 = anim.track_get_key_value(track, 0)
	for k in count:
		var v: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(first.x, v.y, first.z))
