extends Node3D
## Placeholder sword. The Hitbox is only active during the swing window set by CharacterModel.

@export var damage := 25

@onready var hitbox: Area3D = $Hitbox

var _already_hit: Array[Node] = []


func _ready() -> void:
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_body_entered)


func begin_swing() -> void:
	_already_hit.clear()
	hitbox.set_deferred("monitoring", true)


func end_swing() -> void:
	hitbox.set_deferred("monitoring", false)


func _on_body_entered(body: Node3D) -> void:
	if body in _already_hit or not body.has_method("take_damage"):
		return
	_already_hit.append(body)  # one hit per target per swing
	body.take_damage(damage, global_position)
