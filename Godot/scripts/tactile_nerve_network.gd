extends Node

## [TACTILE NERVE NETWORK]
## Aggregates touch signals from body-bound sensors and routes them to the AI Soul.
## Enables Yen to "feel" specific body regions.

signal touch_perceived(region: String, intensity: float, position: Vector3)

@export var soul_synapse: Node = null # Reference to Soul/Synapse node

# Mapping of sensor names/groups to body regions
const REGIONS = {
	"head_sensor": "HEAD",
	"torso_sensor": "CHEST",
	"arm_l_sensor": "ARM_LEFT",
	"arm_r_sensor": "ARM_RIGHT",
	"hand_l_sensor": "HAND_LEFT",
	"hand_r_sensor": "HAND_RIGHT",
	"leg_l_sensor": "LEG_LEFT",
	"leg_r_sensor": "LEG_RIGHT"
}

func _ready():
	print("LUMAX: Tactile Nerve Network initializing...")
	_connect_sensors()

func _connect_sensors():
	# Recursively find all Area3D sensors under the Avatar/Body
	var body = get_parent()
	if not body: return
	
	_recursive_link_sensors(body)

func _recursive_link_sensors(node: Node):
	for child in node.get_children():
		if child is BoneAttachment3D:
			for sensor in child.get_children():
				if sensor is Area3D:
					if not sensor.area_entered.is_connected(_on_sensor_touch):
						sensor.area_entered.connect(_on_sensor_touch.bind(sensor))
						print("LUMAX: Tactile sensor linked: ", sensor.name)
		_recursive_link_sensors(child)

func _on_sensor_touch(other_area: Area3D, sensor: Area3D):
	var region = _get_region_for_sensor(sensor)
	var intensity = 1.0 # To be scaled by velocity/proximity in future
	var pos = sensor.global_position
	
	print("LUMAX: Yen felt touch on [", region, "] from ", other_area.name)
	touch_perceived.emit(region, intensity, pos)
	
	if soul_synapse and soul_synapse.has_method("inject_sensory_event"):
		# Format: [SENSORY: TOUCH | REGION: HEAD | INTENSITY: 1.0]
		var payload = "[SENSORY: TOUCH | REGION: %s | INTENSITY: %.1f]" % [region, intensity]
		soul_synapse.inject_sensory_event(payload)

func apply_tactile_pressure(pos: Vector3, pressure: float, _vibration: float):
	var region = "BODY_GENERAL"
	var min_dist = 999.0
	var sensors = get_tree().get_nodes_in_group("tactile_sensors")
	for s in sensors:
		if s is Area3D:
			var d = s.global_position.distance_to(pos)
			if d < min_dist:
				min_dist = d
				region = _get_region_for_sensor(s)
	
	if pressure > 0.1:
		touch_perceived.emit(region, pressure, pos)
		if soul_synapse and soul_synapse.has_method("inject_sensory_event"):
			var payload = "[SENSORY: TOUCH | REGION: %s | PRESSURE: %.2f]" % [region, pressure]
			soul_synapse.call("inject_sensory_event", payload)

func _get_region_for_sensor(sensor: Area3D) -> String:
	for key in REGIONS.keys():
		if key in sensor.name.to_lower():
			return REGIONS[key]
	return "BODY_GENERAL"
