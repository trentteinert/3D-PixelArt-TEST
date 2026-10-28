class_name CharacterModel
extends Node3D
## Wraps the imported Mixamo hero: applies the toon shader to its meshes, plays idle / walk /
## run / jump animations, and handles the shader-style switch (T key). Faces -Z.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

## Animation files exported from Mixamo on the same skeleton as the hero.
const ANIMATION_FILES := {
	"walk": "res://models/animations/walk.fbx",
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
		_play("jump", false)
	elif speed > run_threshold:
		_play("run")
	elif speed > walk_threshold:
		_play("walk")
	else:
		_play("idle")


func cycle_style() -> void:
	style = ((style + 1) % Style.size()) as Style
	var materials: Array = [_toon_outline, _toon, _plain][style]
	for i in _meshes.size():
		_meshes[i].material_override = materials[i]
	print("Character style: ", Style.keys()[style])


func _play(anim_name: String, loop := true) -> void:
	if _state == anim_name:
		return
	_state = anim_name
	var full := "%s/%s" % [LIBRARY, anim_name]
	if _anim.has_animation(full):
		_anim.get_animation(full).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		_anim.play(full, blend_time)


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
	_play("idle")


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
