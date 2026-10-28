extends CharacterBody3D
## Third-person controller: camera-relative movement, sprint, variable-height jump
## with coyote time + jump buffering, and an orbit camera on a SpringArm3D.

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 9.0
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

	_try_step_up()
	move_and_slide()

	# Ease out the pop from stepping up so the model glides up stairs instead of snapping.
	model.position.y = lerpf(model.position.y, 0.0, 1.0 - exp(-14.0 * delta))

	# Face the direction we're actually travelling (not just the input), so the body never
	# points one way while the ground slides past in another, which reads as foot skating.
	if horizontal.length() > 0.5:
		var yaw := atan2(-horizontal.x, -horizontal.y)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))

	model.animate(delta, horizontal.length(), is_on_floor(), velocity.y, sprint_speed)


## Walks up ledges lower than step_height: if we'd hit a wall-like surface, check there is
## headroom, that the way forward is clear one step higher, and that there is floor to land on.
func _try_step_up() -> void:
	if not is_on_floor() or velocity.y > 0.1:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * get_physics_process_delta_time()
	if motion.length() < 0.001:
		return
	# Probe a little further than this frame's motion so the riser is caught early.
	var probe := motion.normalized() * maxf(motion.length(), 0.1)
	var blocked := KinematicCollision3D.new()
	if not test_move(global_transform, probe, blocked) or blocked.get_normal().y > 0.7:
		return  # nothing in the way, or a walkable slope (move_and_slide handles those)
	var up := Vector3.UP * step_height
	if test_move(global_transform, up):
		return  # no headroom
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return  # still blocked one step higher: a wall, not a step
	var landing := KinematicCollision3D.new()
	if not test_move(raised.translated(probe), -up, landing) or landing.get_normal().y < 0.7:
		return  # nothing walkable to land on
	var rise := step_height - landing.get_travel().length()
	if rise <= 0.01:
		return
	global_position.y += rise
	model.position.y -= rise


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


func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	var e := InputEventKey.new()
	e.physical_keycode = keycode
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
