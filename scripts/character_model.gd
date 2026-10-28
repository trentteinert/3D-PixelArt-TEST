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
	"attack": "res://models/animations/attack.fbx",
	"roll": "res://models/animations/roll.fbx",
}
const LIBRARY := "locomotion"
const SWORD_SCENE := preload("res://scenes/sword.tscn")
## Hand-bone axes (read from the Mixamo rig): +Y points along the fingers, +X toward the thumb,
## +Z out of the palm. This puts the blade along the thumb side with the edge along the fingers.
const GRIP_BASIS := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))

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
@export var run_anim_speed := 4.5

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

@export_group("Sword")
## Held in the hand bone whose name ends with this.
@export var sword_bone_suffix := "RightHand"
## Offset in meters from the wrist bone: x = thumb side, y = along the fingers, z = out of the palm.
@export var sword_offset := Vector3(0.0, 0.09, 0.03)
## Extra rotation (degrees) applied on top of the default grip. Y spins the sword around its blade.
@export var sword_rotation_degrees := Vector3.ZERO
@export var sword_scale := 1.0

@export_group("Attack")
@export var attack_speed_scale := 1.5
## Seconds into the attack animation (after speed scaling is NOT applied) when the blade starts and stops hurting.
@export var hit_start_time := 0.35
@export var hit_end_time := 0.75
## After this many seconds into the swing, moving or jumping cancels the recovery and goes
## straight back to running. Set it above the clip length to always play the whole swing.
@export var attack_cancel_time := 0.8
## While moving, play the swing on the upper body only so the legs keep running (no sliding).
@export var attack_blend_when_moving := true
## Only use the upper-body swing when moving faster than this (m/s). If you slow below 60% of it
## mid-swing, the swing hands over to the full-body version (legs included) so it doesn't look odd.
@export var overlay_min_speed := 3.0
@export var overlay_fade_in := 0.08
@export var overlay_fade_out := 0.2

@export_group("Roll")
## Skips the falling part at the start of the roll clip. Raise until the roll starts as you want.
@export var roll_start_time := 0.0
@export_range(0.5, 3.0) var roll_speed_scale := 1.6

var style: Style = Style.TOON_OUTLINE
var is_attacking := false
var is_rolling := false

@onready var _hero: Node3D = $Hero

var _meshes: Array[MeshInstance3D] = []
var _toon_outline: Array[Material] = []
var _toon: Array[Material] = []
var _plain: Array[Material] = []
var _anim: AnimationPlayer
var _state := ""
var _sword: Node3D
var _sword_attachment: BoneAttachment3D
var _swing_active := false
var _overlay: AttackOverlay
var _overlay_attack := false
var _overlay_fading := false
var _attack_time := 0.0
var _attack_length := 1.0
var _last_speed := 0.0


func _ready() -> void:
	_hero.rotation.y = deg_to_rad(facing_offset_degrees)
	_setup_materials()
	_setup_animations()
	_attach_sword()


## Starts the sword swing. Returns false if busy or the clip is missing.
func attack() -> bool:
	if _anim == null or is_attacking or is_rolling or not _anim.has_animation(LIBRARY + "/attack"):
		return false
	is_attacking = true
	_swing_active = false
	if attack_blend_when_moving and _overlay != null and _last_speed > overlay_min_speed:
		# Upper body only: the locomotion animation keeps playing underneath.
		_overlay_attack = true
		_attack_time = 0.0
		return true
	_overlay_attack = false
	_state = "attack"
	_anim.get_animation(LIBRARY + "/attack").loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = attack_speed_scale
	_anim.play(LIBRARY + "/attack", 0.1)
	return true


## Starts the roll. Returns how long it lasts in seconds, or 0.0 if it can't roll right now.
func roll() -> float:
	if _anim == null or is_rolling or not _anim.has_animation(LIBRARY + "/roll"):
		return 0.0
	_end_attack()
	is_rolling = true
	_state = "roll"
	var clip := _anim.get_animation(LIBRARY + "/roll")
	clip.loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = roll_speed_scale
	_anim.play(LIBRARY + "/roll", 0.1)
	if roll_start_time > 0.0:
		_anim.seek(roll_start_time, true)
	return maxf(clip.length - roll_start_time, 0.1) / roll_speed_scale


func end_roll() -> void:
	if is_rolling:
		is_rolling = false
		_state = ""


## speed is horizontal speed in m/s. run_speed is unused (kept so player.gd's call stays the same).
func animate(delta: float, speed: float, on_floor: bool, _vertical_speed: float, _run_speed: float) -> void:
	_update_sword_grip()
	_last_speed = speed
	if _anim == null:
		return
	if _overlay_fading:
		# Handing over to the full-body swing: the upper body stays on the overlay until the
		# player's own attack clip has blended in underneath, then the overlay fades away.
		_overlay.time = minf(_anim.current_animation_position, _attack_length)
		_overlay.weight = maxf(_overlay.weight - delta / maxf(blend_time, 0.01), 0.0)
		_overlay_fading = _overlay.weight > 0.0
	if is_rolling:
		return
	if is_attacking and _overlay_attack:
		_attack_time += delta * attack_speed_scale
		_overlay.time = minf(_attack_time, _attack_length)
		_overlay.weight = clampf(minf(_attack_time / maxf(overlay_fade_in, 0.001),
				(_attack_length - _attack_time) / maxf(overlay_fade_out, 0.001)), 0.0, 1.0)
		_update_swing_window(_attack_time)
		if _attack_time >= _attack_length:
			_end_attack()
		elif speed < overlay_min_speed * 0.6 and on_floor:
			_hand_over_to_full_body()
			return  # don't let the locomotion code below start idle/walk over the swing
		# no return: the locomotion code below keeps the legs moving
	elif is_attacking:
		var t := _anim.current_animation_position
		if t >= attack_cancel_time and (speed > walk_threshold or not on_floor):
			_end_attack()  # cancel the recovery, fall through to normal movement animations
		else:
			_update_swing_window(t)
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
	if library.has_animation("attack"):
		var attack_clip := library.get_animation("attack")
		_attack_length = attack_clip.length
		_overlay = AttackOverlay.new()
		_overlay.name = "AttackOverlay"
		skeleton.add_child(_overlay)
		_overlay.setup(attack_clip)
	_anim.animation_finished.connect(_on_animation_finished)
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


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == LIBRARY + "/attack":
		_end_attack()
	elif anim_name == LIBRARY + "/roll":
		end_roll()


## Slowed to a near stop mid-swing: continue the same swing as the full-body clip, from the
## same point, so the legs join in instead of the torso swinging over idle legs.
func _hand_over_to_full_body() -> void:
	_overlay_attack = false
	_overlay_fading = true
	_state = "attack"
	_anim.get_animation(LIBRARY + "/attack").loop_mode = Animation.LOOP_NONE
	_anim.speed_scale = attack_speed_scale
	_anim.play(LIBRARY + "/attack", blend_time)
	_anim.seek(_attack_time, true)


func _update_swing_window(t: float) -> void:
	var active := t >= hit_start_time and t <= hit_end_time
	if active == _swing_active:
		return
	_swing_active = active
	if _sword and active:
		_sword.begin_swing()
	elif _sword:
		_sword.end_swing()


func _end_attack() -> void:
	if not is_attacking:
		return
	is_attacking = false
	if _overlay_attack:
		_overlay.weight = 0.0  # locomotion kept playing, so don't restart it
	else:
		_state = ""
	if _overlay:
		_overlay.weight = 0.0
	_overlay_attack = false
	_overlay_fading = false
	if _swing_active and _sword:
		_sword.end_swing()
	_swing_active = false


## Parents the sword to the hand bone so it follows the animation.
func _attach_sword() -> void:
	var skeleton := _hero.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var bone_name := ""
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(sword_bone_suffix):
			bone_name = skeleton.get_bone_name(i)
			break
	if bone_name == "":
		push_warning("CharacterModel: no bone ending in '%s', sword not attached" % sword_bone_suffix)
		return
	_sword_attachment = BoneAttachment3D.new()
	_sword_attachment.name = "SwordAttachment"
	skeleton.add_child(_sword_attachment)
	_sword_attachment.bone_name = bone_name
	_sword = SWORD_SCENE.instantiate()
	_sword_attachment.add_child(_sword)


# The imported rig may carry a unit scale (e.g. centimeters), so counter it each frame to keep
# the sword's offset in meters and its size at sword_scale.
func _update_sword_grip() -> void:
	if _sword == null:
		return
	var unit := _sword_attachment.global_basis.get_scale().x
	if unit < 0.0001:
		return
	var grip := GRIP_BASIS * Basis.from_euler(Vector3(
		deg_to_rad(sword_rotation_degrees.x), deg_to_rad(sword_rotation_degrees.y), deg_to_rad(sword_rotation_degrees.z)))
	_sword.basis = grip.scaled(Vector3.ONE * sword_scale / unit)
	_sword.position = sword_offset / unit
