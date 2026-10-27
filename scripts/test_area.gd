extends Node3D
## Builds a small proving ground: flat floor, steps, ramps, platforms and pillars,
## plus sun + sky. Edit the layout in _build_obstacles() or replace with real scenes later.

const GRID := preload("res://shaders/grid.gdshader")


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_obstacles()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("4a7bd0")
	sky_mat.sky_horizon_color = Color("bcd4ee")
	sky_mat.ground_horizon_color = Color("bcd4ee")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_floor() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Vector3.ZERO, Color("6b7a8a"))


func _build_obstacles() -> void:
	# Staircase (0.25m risers)
	for i in 8:
		_box(Vector3(-8, 0.125 + i * 0.25, -6 - i * 0.6), Vector3(3, 0.25 + i * 0.25, 0.6), Vector3.ZERO, Color("9a8f7a"))
	# Gentle and steep ramps
	_box(Vector3(6, 0.5, -6), Vector3(4, 0.4, 8), Vector3(-15, 0, 0), Color("7a9a7e"))
	_box(Vector3(12, 1.2, -6), Vector3(4, 0.4, 8), Vector3(-35, 0, 0), Color("9a7a7e"))
	# Jump platforms at increasing height/distance
	_box(Vector3(0, 0.5, -12), Vector3(3, 1, 3), Vector3.ZERO, Color("7a86b0"))
	_box(Vector3(0, 1.0, -17), Vector3(3, 2, 3), Vector3.ZERO, Color("7a86b0"))
	_box(Vector3(0, 1.5, -23), Vector3(3, 3, 3), Vector3.ZERO, Color("7a86b0"))
	# Pillars and a wall to bump around and test the camera against
	for p in [Vector3(-4, 1.5, 6), Vector3(0, 1.5, 8), Vector3(4, 1.5, 6)]:
		_box(p, Vector3(1, 3, 1), Vector3.ZERO, Color("b08a6a"))
	_box(Vector3(10, 1.5, 8), Vector3(10, 3, 0.5), Vector3.ZERO, Color("b08a6a"))
	# Low walls around the arena edge
	_box(Vector3(0, 1, 40.25), Vector3(80, 2, 0.5), Vector3.ZERO, Color("555e69"))
	_box(Vector3(0, 1, -40.25), Vector3(80, 2, 0.5), Vector3.ZERO, Color("555e69"))
	_box(Vector3(40.25, 1, 0), Vector3(0.5, 2, 80), Vector3.ZERO, Color("555e69"))
	_box(Vector3(-40.25, 1, 0), Vector3(0.5, 2, 80), Vector3.ZERO, Color("555e69"))


func _box(pos: Vector3, size: Vector3, rot_deg: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg

	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := ShaderMaterial.new()
	mat.shader = GRID
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("line_color", color.darkened(0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	add_child(body)
