extends CharacterBody3D
## Third-person controller: camera-relative movement, sprint, variable-height jump
## with coyote time + jump buffering, and an orbit camera on a SpringArm3D.

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 6.0
@export var acceleration := 35.0
@export var air_acceleration := 15.0
@export var friction := 40.0
## How fast the body turns to face the direction of travel.
@export var turn_speed := 16.0
## How fast (radians/second) your direction of travel swings toward the input on the ground.
## Higher = snappier direction changes with no speed loss; lower = wider, more weighty turns.
@export var turn_rate := 20.0
## Turning more than this many degrees away from your current direction counts as a reversal:
## the character brakes hard and pivots instead of swinging around in an arc.
@export var reverse_angle_degrees := 110.0
## Deceleration (m/s²) while braking into a reversal.
@export var reverse_brake := 70.0

@export_group("Stairs and Slopes")
## Tallest ledge the character walks up without jumping.
@export var step_height := 0.45
## How far below the feet the floor is still "stuck to", so running down stairs and slopes doesn't bounce.
@export var floor_snap := 0.4

@export_group("Combat")
## Fraction of normal speed while swinging the sword.
@export_range(0.0, 1.0) var attack_move_scale := 0.85
## How far (meters) a roll travels from standing still, and at full sprint. Between those it
## scales with your speed when you start rolling.
@export var roll_min_distance := 1.5
@export var roll_max_distance := 3.0
## Once this fraction of the roll has played, moving or jumping hands control back.
@export_range(0.0, 1.0) var roll_control_fraction := 0.55
@export var roll_cooldown := 0.3

@export_group("Jump")
@export var jump_velocity := 7.5
@export var gravity_scale := 2.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Camera")
@export var mouse_sensitivity := 0.003
@export var stick_sensitivity := 2.5
@export var min_pitch := -1.3
@export var max_pitch := 0.4
## How quickly the camera catches up to the player (higher = tighter, 0 = rigidly attached).
@export var camera_follow_speed := 14.0
## Extra field of view (degrees) added at full sprint.
@export var sprint_fov_boost := 8.0

@onready var model: CharacterModel = $Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var edge_highlight: MeshInstance3D = $CameraPivot/SpringArm3D/Camera3D/EdgeHighlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _coyote := 0.0
var _jump_buffer := 0.0
var _pitch := -0.5
var _speed := 0.0
var _roll_dir := Vector3.ZERO
var _roll_speed := 0.0
var _roll_time := 0.0
var _roll_duration := 1.0
var _roll_cooldown_left := 0.0
var _camera_offset := Vector3.ZERO
var _base_fov := 70.0


func _ready() -> void:
	_setup_input()
	floor_snap_length = floor_snap
	spring_arm.add_excluded_object(get_rid())
	_pitch = spring_arm.rotation.x
	# Detach the pivot so it can trail the player smoothly (rotation is set by mouse look only).
	_camera_offset = camera_pivot.position
	_base_fov = camera.fov
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + _camera_offset
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("cycle_shader"):
		model.cycle_style()
	elif event.is_action_pressed("toggle_edges"):
		edge_highlight.visible = not edge_highlight.visible
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var target := global_position + _camera_offset
	if camera_follow_speed > 0.0:
		camera_pivot.global_position = camera_pivot.global_position.lerp(target, 1.0 - exp(-camera_follow_speed * delta))
	else:
		camera_pivot.global_position = target
	var sprint_t := clampf((_speed - walk_speed) / maxf(sprint_speed - walk_speed, 0.01), 0.0, 1.0)
	camera.fov = lerpf(camera.fov, _base_fov + sprint_fov_boost * sprint_t, 1.0 - exp(-6.0 * delta))

	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		_look(-stick.x * stick_sensitivity * delta, -stick.y * stick_sensitivity * delta)


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	# Combat inputs
	_roll_cooldown_left = maxf(_roll_cooldown_left - delta, 0.0)
	var in_control := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and is_on_floor()
	if in_control and Input.is_action_just_pressed("attack"):
		model.attack()
	if in_control and Input.is_action_just_pressed("roll") and _roll_cooldown_left <= 0.0 and not model.is_rolling:
		_start_roll()
	if model.is_rolling and _process_roll(delta):
		return

	# Coyote time + jump buffering
	_coyote = coyote_time if is_on_floor() else maxf(_coyote - delta, 0.0)
	_jump_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else maxf(_jump_buffer - delta, 0.0)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= 0.5  # release early = shorter hop

	# Camera-relative horizontal movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera_pivot.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * input.length()

	var top_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if model.is_attacking:
		top_speed *= attack_move_scale
	var horizontal := Vector2(velocity.x, velocity.z)
	var previous_horizontal := horizontal
	var target := Vector2(dir.x, dir.z) * top_speed
	if is_on_floor() and input != Vector2.ZERO:
		# Steer the heading toward the input and keep the speed, so direction changes are
		# sharp but momentum isn't lost in the turn. Speed ramps toward the target separately.
		var target_dir := target.normalized()
		var current_speed := horizontal.length()
		var heading := target_dir
		if current_speed > 0.1:
			heading = horizontal / current_speed
			var angle := heading.angle_to(target_dir)
			if absf(angle) > deg_to_rad(reverse_angle_degrees):
				if current_speed > 1.5:
					# Reversal: brake to a near stop first, then take off the new way.
					horizontal = horizontal.move_toward(Vector2.ZERO, reverse_brake * delta)
					heading = Vector2.ZERO
				else:
					heading = target_dir
			else:
				heading = heading.rotated(clampf(angle, -turn_rate * delta, turn_rate * delta))
		if heading != Vector2.ZERO:
			horizontal = heading * move_toward(current_speed, target.length(), acceleration * delta)
	else:
		var rate := friction if input == Vector2.ZERO else air_acceleration
		horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	_speed = horizontal.length()

	# Acceleration in the character's own frame (x = right, z = back) drives the body lean.
	var accel := (horizontal - previous_horizontal) / delta
	var local_accel := Basis(Vector3.UP, model.rotation.y).inverse() * Vector3(accel.x, 0.0, accel.y)
	model.lean(delta, local_accel, _speed / sprint_speed)

	if not _snap_up_to_stairs(delta):
		move_and_slide()

	# Ease out the pop from stepping up so the model glides up stairs instead of snapping.
	model.position.y = lerpf(model.position.y, 0.0, 1.0 - exp(-14.0 * delta))

	# Face the direction we're actually travelling (not just the input), so the body never
	# points one way while the ground slides past in another, which reads as foot skating.
	if horizontal.length() > 0.5:
		var yaw := atan2(-horizontal.x, -horizontal.y)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))

	model.animate(delta, horizontal.length(), is_on_floor(), velocity.y, sprint_speed)


## Rolls in the input direction (or the way the character already faces).
func _start_roll() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := camera_pivot.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3(-sin(model.rotation.y), 0.0, -cos(model.rotation.y))
	_roll_dir = dir.normalized()
	model.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
	var start_speed := _speed
	_roll_duration = model.roll()
	if _roll_duration <= 0.0:
		return
	# Pick the speed that makes the whole roll cover the wanted distance (see _process_roll's curve).
	var distance := lerpf(roll_min_distance, roll_max_distance, clampf(start_speed / sprint_speed, 0.0, 1.0))
	var f := maxf(roll_control_fraction, 0.05)
	_roll_speed = distance / (_roll_duration * (f * 0.7 + (1.0 - f) * 0.4))
	_roll_time = _roll_duration
	_roll_cooldown_left = roll_cooldown


## Returns true while the roll still owns the character this frame.
func _process_roll(delta: float) -> bool:
	_roll_time -= delta
	var progress := 1.0 - _roll_time / _roll_duration
	var wants_out := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO \
		or Input.is_action_just_pressed("jump")
	if _roll_time <= 0.0 or (progress >= roll_control_fraction and wants_out):
		model.end_roll()
		return false
	# Fast at the start, easing off until control returns, then a slow tail.
	var s := _roll_speed * lerpf(1.0, 0.4, clampf(progress / maxf(roll_control_fraction, 0.05), 0.0, 1.0))
	velocity.x = _roll_dir.x * s
	velocity.z = _roll_dir.z * s
	_speed = s
	model.lean(delta, Vector3.ZERO, 0.0)
	if not _snap_up_to_stairs(delta):
		move_and_slide()
	model.animate(delta, s, is_on_floor(), velocity.y, sprint_speed)
	return true


## Steps up onto ledges no taller than step_height. Looks where this frame's movement would
## put us, drops a probe down from one step higher, and if it lands on a higher walkable
## surface, moves us there in one go (forward AND up, so floor snapping can't pull us back).
## Returns true if it moved the character, in which case move_and_slide() should be skipped.
func _snap_up_to_stairs(delta: float) -> bool:
	if not is_on_floor() or velocity.y > 0.1:
		return false
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0001:
		return false
	var reach := step_height * 2.0
	if test_move(global_transform, Vector3.UP * reach):
		return false  # no headroom
	var start := global_transform.translated(motion + Vector3.UP * reach)
	var down := KinematicCollision3D.new()
	if not test_move(start, Vector3.DOWN * reach, down):
		return false
	var new_position := start.origin + down.get_travel()
	var rise := new_position.y - global_position.y
	if rise > step_height or rise <= 0.01:
		return false  # too tall (a wall), or flat ground / negligible
	# Confirm the surface we'd land on is walkable, not a steep face or an edge.
	var ahead := down.get_position() + Vector3.UP * step_height + motion.normalized() * 0.1
	var query := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * reach, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < cos(floor_max_angle):
		return false
	global_position = new_position
	apply_floor_snap()
	model.position.y -= rise  # ease the visual pop out in _physics_process
	return true


func _look(yaw_delta: float, pitch_delta: float) -> void:
	camera_pivot.rotation.y += yaw_delta
	_pitch = clampf(_pitch + pitch_delta, min_pitch, max_pitch)
	spring_arm.rotation.x = _pitch


# Actions are registered in code so the project works without editing the Input Map.
# Move them into Project Settings > Input Map later if you prefer.
func _setup_input() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("toggle_mouse", KEY_ESCAPE)
	_key("cycle_shader", KEY_T)
	_key("toggle_edges", KEY_E)
	_key("roll", KEY_C)
	_key("attack", KEY_F)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_button("jump", JOY_BUTTON_A)
	_button("sprint", JOY_BUTTON_LEFT_STICK)
	_button("cycle_shader", JOY_BUTTON_Y)
	_button("toggle_edges", JOY_BUTTON_X)
	_button("roll", JOY_BUTTON_B)
	_button("attack", JOY_BUTTON_RIGHT_SHOULDER)


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)


func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)


func _button(action: StringName, button: JoyButton) -> void:
	_ensure(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
