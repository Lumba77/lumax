extends Node

## [TACTILE NERVE NETWORK]
## Aggregates touch signals from body-bound sensors and routes them to the AI Soul.
## Enables Yen to "feel" specific body regions and velocity of impact.

signal touch_perceived(region: String, intensity: float, position: Vector3, is_gentle: bool)

@export var soul_synapse: Node = null 

const REGIONS = {
	"head_sensor": "HEAD",
	"neck_sensor": "NECK_EROGENOUS",
	"torso_sensor": "CHEST",
	"breast_sensor": "CHEST_EROGENOUS",
	"belly_sensor": "STOMACH",
	"groin_sensor": "INNER_THIGH_EROGENOUS",
	"arm_l_sensor": "ARM_LEFT",
	"arm_r_sensor": "ARM_RIGHT",
	"hand_l_sensor": "HAND_LEFT",
	"hand_r_sensor": "HAND_RIGHT",
	"leg_l_sensor": "LEG_LEFT",
	"leg_r_sensor": "LEG_RIGHT"
}

var _last_other_pos: Dictionary = {} # other_area_rid -> Vector3

func _ready():
	_connect_sensors()

func _connect_sensors():
	var body = get_parent()
	if body: _recursive_link_sensors(body)

func _recursive_link_sensors(node: Node):
	for child in node.get_children():
		if child is BoneAttachment3D:
			for sensor in child.get_children():
				if sensor is Area3D:
					if not sensor.area_entered.is_connected(_on_sensor_touch):
						sensor.area_entered.connect(_on_sensor_touch.bind(sensor))
		_recursive_link_sensors(child)

func _on_sensor_touch(other_area: Area3D, sensor: Area3D):
	var region = _get_region_for_sensor(sensor)
	var pos = sensor.global_position
	
	# Calculate Velocity/Gentleness
	var rid = other_area.get_instance_id()
	var velocity = 0.0
	if _last_other_pos.has(rid):
		velocity = (other_area.global_position - _last_other_pos[rid]).length() / get_process_delta_time()
	_last_other_pos[rid] = other_area.global_position
	
	var is_gentle = velocity < 1.5
	var intensity = clamp(velocity / 5.0, 0.1, 1.0)
	
	var quality = "GENTLE_CARESS" if is_gentle else "HARD_IMPACT"
	print("LUMAX: Yen felt ", quality, " on [", region, "] (Vel: ", velocity, ")")
	
	touch_perceived.emit(region, intensity, pos, is_gentle)
	
	if soul_synapse and soul_synapse.has_method("inject_sensory_event"):
		var payload = "[SENSORY: TOUCH | REGION: %s | QUALITY: %s | INTENSITY: %.1f]" % [region, quality, intensity]
		soul_synapse.inject_sensory_event(payload)

func _get_region_for_sensor(sensor: Area3D) -> String:
	for key in REGIONS.keys():
		if key in sensor.name.to_lower(): return REGIONS[key]
	return "BODY_GENERAL"
