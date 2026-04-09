extends Node3D
class_name HapticWand

@onready var controller: XRController3D = get_parent()
var active = false

var current_length = 1.0 # meters
var vibration_intensity = 0.5
var glow_material: StandardMaterial3D

var mesh_inst: MeshInstance3D
var ray: RayCast3D
var _mesh_ready := false

# Spring physics for wobble — single “flexible rod” behavior (thin cylinder along tip ray).
var tip_velocity := Vector3.ZERO
var tip_position := Vector3.ZERO

func _ready():
	mesh_inst = MeshInstance3D.new()
	add_child(mesh_inst)

	glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = Color(1, 0.1, 0.1, 0.5)
	glow_material.emission_enabled = true
	glow_material.emission = Color(1, 0.0, 0.0)
	glow_material.emission_energy_multiplier = 0.0
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = glow_material

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -current_length)
	ray.collision_mask = 1 | 2
	add_child(ray)

	visible = false
	set_process(true)


func set_active(val: bool):
	active = val
	visible = active
	if active:
		glow_material.emission_energy_multiplier = 2.0
		tip_position = global_position - global_transform.basis.z * current_length
		tip_velocity = Vector3.ZERO
		_mesh_ready = false
	else:
		glow_material.emission_energy_multiplier = 0.0


func _process(delta):
	if not active or not controller:
		return

	var joy = controller.get_vector2("primary_2d_axis")
	if joy.length() > 0.1:
		current_length -= joy.y * delta * 1.5
		current_length = clamp(current_length, 0.05, 3.0)

		vibration_intensity += joy.x * delta * 1.0
		vibration_intensity = clamp(vibration_intensity, 0.0, 1.0)

	_update_physics_and_shape(delta)
	_handle_haptics()


func _update_physics_and_shape(delta):
	var straight_tip = global_position - global_transform.basis.z * current_length

	var sag = Vector3.DOWN * (current_length * current_length * 0.24)
	var target_tip = straight_tip + sag

	var stiffness = 34.0 / clamp(current_length, 0.35, 3.0)
	var damping = 4.0

	var force = (target_tip - tip_position) * stiffness
	tip_velocity += force * delta
	tip_velocity -= tip_velocity * damping * delta
	tip_position += tip_velocity * delta

	var max_stretch = current_length * 1.35
	if tip_position.distance_to(global_position) > max_stretch:
		tip_position = global_position + (tip_position - global_position).normalized() * max_stretch

	var local_tip = to_local(tip_position)
	ray.target_position = local_tip

	if not _mesh_ready:
		_mesh_ready = true
		var rod := CylinderMesh.new()
		rod.top_radius = 0.0055
		rod.bottom_radius = 0.011
		mesh_inst.mesh = rod

	var h: float = maxf(0.04, local_tip.length())
	(mesh_inst.mesh as CylinderMesh).height = h
	mesh_inst.position = local_tip * 0.5
	if local_tip.length_squared() > 0.0001:
		mesh_inst.transform.basis = _align_y_to_dir(local_tip.normalized())


func _align_y_to_dir(dir: Vector3) -> Basis:
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x = up.cross(dir).normalized()
	var z = dir.cross(x).normalized()
	return Basis(x, dir, z)


func _wand_intimacy_and_user_haptics() -> Vector2:
	var intim := 0.45
	var user_hs := 1.0
	var sk = get_tree().get_first_node_in_group("lumax_core")
	if sk and sk.has_method("get_intimacy_level"):
		intim = clampf(float(sk.call("get_intimacy_level")), 0.0, 1.0)
	var n = get_node_or_null("/root/XRToolsUserSettings")
	if n:
		var v = n.get("haptics_scale")
		if v != null:
			user_hs = clampf(float(v), 0.05, 1.0)
	return Vector2(intim, user_hs)


func _handle_haptics():
	if ray.is_colliding():
		var col = ray.get_collider()
		var is_avatar = col.name == "Avatar" or (col.get_parent() and col.get_parent().name == "Body")
		if not is_avatar:
			return

		var point = ray.get_collision_point()
		var dist = global_position.distance_to(point)
		var actual_len = to_local(tip_position).length()

		var pressure = clamp(1.0 - (dist / actual_len), 0.0, 1.0)

		if pressure > 0.01:
			var ih = _wand_intimacy_and_user_haptics()
			var pulse = pressure * vibration_intensity * ih.y * (0.52 + 0.58 * ih.x)
			if controller.has_method("trigger_haptic_pulse"):
				controller.trigger_haptic_pulse("haptic", 100.0, pulse, 0.05, 0)

			glow_material.emission_energy_multiplier = 2.0 + (pressure * 10.0)

			if col.has_method("apply_tactile_pressure"):
				col.apply_tactile_pressure(point, pressure, vibration_intensity)
	else:
		glow_material.emission_energy_multiplier = 2.0
