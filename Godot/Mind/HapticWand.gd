extends Node3D
class_name HapticWand

@onready var controller: XRController3D = get_parent()
var active = false

var current_length = 1.0 # meters
var vibration_intensity = 0.5
var glow_material: StandardMaterial3D

var mesh_inst: MeshInstance3D
var ray: RayCast3D
var _current_mode := -1 # -1: None, 0: Ball, 1: Club, 2: Sword

# Spring physics for wobble
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
	ray.collision_mask = 1 | 2 # Layer 1 & 2
	add_child(ray)
	
	visible = false
	set_process(true)

func set_active(val: bool):
	active = val
	visible = active
	if active:
		glow_material.emission_energy_multiplier = 2.0
		# Reset physics
		tip_position = global_position - global_transform.basis.z * current_length
		tip_velocity = Vector3.ZERO
	else:
		glow_material.emission_energy_multiplier = 0.0

func _process(delta):
	if not active or not controller: return
	
	# Joystick Input for Length and Vibration
	var joy = controller.get_vector2("primary_2d_axis")
	if joy.length() > 0.1:
		current_length -= joy.y * delta * 1.5
		current_length = clamp(current_length, 0.05, 3.0)
		
		vibration_intensity += joy.x * delta * 1.0
		vibration_intensity = clamp(vibration_intensity, 0.0, 1.0)
	
	_update_physics_and_shape(delta)
	_handle_haptics()

func _update_physics_and_shape(delta):
	# Calculate ideal straight tip position
	var straight_tip = global_position - global_transform.basis.z * current_length
	
	# Add "gravity" sag based on length
	var sag = Vector3.DOWN * (current_length * current_length * 0.1)
	var target_tip = straight_tip + sag
	
	# Spring physics for wobble
	var stiffness = 50.0 / clamp(current_length, 0.5, 3.0)
	var damping = 5.0
	
	var force = (target_tip - tip_position) * stiffness
	tip_velocity += force * delta
	tip_velocity -= tip_velocity * damping * delta
	tip_position += tip_velocity * delta
	
	# Ensure tip doesn't stretch infinitely
	var max_stretch = current_length * 1.2
	if tip_position.distance_to(global_position) > max_stretch:
		tip_position = global_position + (tip_position - global_position).normalized() * max_stretch
	
	# Update Raycast to point at the wobbling tip
	var local_tip = to_local(tip_position)
	ray.target_position = local_tip
	
	# Construct Mesh based on distance - OPTIMIZED: Only rebuild on mode change
	var new_mode = 0
	if current_length > 1.2: new_mode = 2 # Sword
	elif current_length > 0.3: new_mode = 1 # Club
	
	if new_mode != _current_mode:
		_current_mode = new_mode
		if _current_mode == 2:
			var m = CylinderMesh.new(); m.top_radius = 0.005; m.bottom_radius = 0.02; mesh_inst.mesh = m
		elif _current_mode == 1:
			var m = CylinderMesh.new(); m.top_radius = 0.04; m.bottom_radius = 0.02; mesh_inst.mesh = m
		else:
			var m = SphereMesh.new(); m.radius = 0.08; m.height = 0.16; mesh_inst.mesh = m
	
	if _current_mode > 0:
		mesh_inst.mesh.height = local_tip.length()
		mesh_inst.position = local_tip / 2.0
		if local_tip.length_squared() > 0.001:
			mesh_inst.transform.basis = _align_y_to_dir(local_tip.normalized())
	else:
		mesh_inst.transform.basis = Basis.IDENTITY
		mesh_inst.position = local_tip

func _align_y_to_dir(dir: Vector3) -> Basis:
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x = up.cross(dir).normalized()
	var z = dir.cross(x).normalized()
	return Basis(x, dir, z)

func _handle_haptics():
	if ray.is_colliding():
		var col = ray.get_collider()
		# ONLY vibrate on Avatar contact
		var is_avatar = col.name == "Avatar" or (col.get_parent() and col.get_parent().name == "Body")
		if not is_avatar: return

		var point = ray.get_collision_point()
		var dist = global_position.distance_to(point)
		# actual_len is the current elastic distance to the wobbling tip
		var actual_len = to_local(tip_position).length()
		
		# Elastic pressure: How much the wand is 'bent' against the object
		var pressure = clamp(1.0 - (dist / actual_len), 0.0, 1.0)
		
		if pressure > 0.01:
			var pulse = pressure * vibration_intensity
			# Quest 3 Haptics
			if controller.has_method("trigger_haptic_pulse"):
				controller.trigger_haptic_pulse("haptic", 100.0, pulse, 0.05, 0)
			
			glow_material.emission_energy_multiplier = 2.0 + (pressure * 10.0)
			
			# Trigger Tactile Nerve for Jen to 'feel' it
			if col.has_method("apply_tactile_pressure"):
				col.apply_tactile_pressure(point, pressure, vibration_intensity)
	else:
		glow_material.emission_energy_multiplier = 2.0
