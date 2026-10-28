class_name AttackOverlay
extends SkeletonModifier3D
## Plays an animation on the upper body only (everything below the first spine bone, i.e. spine,
## arms, head, hands) on top of whatever the main animation is doing, so the legs keep running.
## CharacterModel drives `time` and `weight` every frame.

var weight := 0.0  ## 0 = ignore the overlay, 1 = fully replace the upper body
var time := 0.0  ## seconds into the overlay animation

var _animation: Animation
var _pairs: Array[Vector2i] = []  # x = track index, y = bone index


func setup(animation: Animation, spine_suffix := "Spine") -> void:
	_animation = animation
	_pairs.clear()
	var skeleton := get_skeleton()
	if skeleton == null or animation == null:
		return
	var root := -1
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with(spine_suffix):
			root = i
			break
	if root == -1:
		push_warning("AttackOverlay: no bone ending in '%s'" % spine_suffix)
		return
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(String(animation.track_get_path(t).get_concatenated_subnames()))
		if bone != -1 and _is_under(skeleton, bone, root):
			_pairs.append(Vector2i(t, bone))


func _is_under(skeleton: Skeleton3D, bone: int, root: int) -> bool:
	while bone != -1:
		if bone == root:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


func _process_modification() -> void:
	if _animation == null or weight <= 0.001:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for pair in _pairs:
		var target := _animation.rotation_track_interpolate(pair.x, time)
		var current := skeleton.get_bone_pose_rotation(pair.y)
		skeleton.set_bone_pose_rotation(pair.y, current.slerp(target, weight))
