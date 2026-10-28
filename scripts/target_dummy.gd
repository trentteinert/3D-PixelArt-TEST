extends StaticBody3D
## Training dummy: flashes, wobbles away from the hit, shows its health, and resets when "defeated".

@export var max_health := 100
@export var reset_delay := 1.5

@onready var visual: Node3D = $Visual
@onready var label: Label3D = $Label3D

var health := 0
var _materials: Array[ShaderMaterial] = []
var _base_colors: Array[Color] = []
var _wobble: Tween
var _flash: Tween


func _ready() -> void:
	health = max_health
	for child in visual.find_children("*", "MeshInstance3D"):
		var mi := child as MeshInstance3D
		var mat := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		mi.material_override = mat
		_materials.append(mat)
		_base_colors.append(mat.get_shader_parameter("albedo"))
	_update_label()


## Called by the sword. attacker_position decides which way the dummy is knocked.
func take_damage(amount: int, attacker_position: Vector3) -> void:
	if health <= 0:
		return
	health = maxi(health - amount, 0)
	_update_label()
	_play_hit(attacker_position)
	if health == 0:
		await get_tree().create_timer(reset_delay).timeout
		health = max_health
		_update_label()


func _play_hit(attacker_position: Vector3) -> void:
	# Flash white, then back to the base colors.
	if _flash:
		_flash.kill()
	_flash = create_tween().set_parallel(true)
	for i in _materials.size():
		_materials[i].set_shader_parameter("albedo", Color.WHITE)
		_flash.tween_method(func(c: Color): _materials[i].set_shader_parameter("albedo", c), Color.WHITE, _base_colors[i], 0.25)

	# Tip away from the attacker, then spring back upright.
	var away := global_position - attacker_position
	away.y = 0.0
	var axis := Vector3.UP.cross(away.normalized()) if away.length() > 0.001 else Vector3.RIGHT
	if _wobble:
		_wobble.kill()
	visual.quaternion = Quaternion(axis.normalized(), 0.35)
	_wobble = create_tween()
	_wobble.tween_property(visual, "quaternion", Quaternion.IDENTITY, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _update_label() -> void:
	label.text = "Dummy  %d/%d" % [health, max_health] if health > 0 else "Defeated"
