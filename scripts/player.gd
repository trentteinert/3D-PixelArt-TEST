extends CharacterBody3D
## Third-person controller: camera-relative movement, sprint, variable-height jump
## with coyote time + jump buffering, and an orbit camera on a SpringArm3D.

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var acceleration := 40.0
@export var air_acceleration := 15.0
@export var friction := 50.0
@export var turn_speed := 12.0

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

@onready var model: CharacterModel = $Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var edge_highlight: MeshInstance3D = $CameraPivot/SpringArm3D/Camera3D/EdgeHighlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _coyote := 0.0
var _jump_buffer := 0.0
var _pitch := -0.5


func _ready() -> void:
	_setup_input()
	spring_arm.add_excluded_object(get_rid())
	_pitch = spring_arm.rotation.x
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
	var target := Vector2(dir.x, dir.z) * top_speed
	var rate := friction if input == Vector2.ZERO else (acceleration if is_on_floor() else air_acceleration)
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()

	# Face movement direction
	if dir.length() > 0.1:
		var yaw := atan2(-dir.x, -dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))

	model.animate(delta, horizontal.length(), is_on_floor(), velocity.y, sprint_speed)


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
