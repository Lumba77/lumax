extends Node

## 🧠 LUMAX AGENCY NERVE
## Translates high-level Director commands and local XML impulses 
## into physical movements, animations, and spatial adaptation.

signal impulse_felt(vibe: String)
signal action_triggered(anim_name: String)

@onready var _director = get_parent() # Assuming it's a child of DirectorManager

var _anim_player: AnimationPlayer = null
var _body: Node3D = null

# The "Chosen" Animation Map
# If the value matches a Category name, Jen makes a voluntary random choice from that folder.
var _anim_map = {
	"WAVE": "GREETINGS",
	"HAPPY": "HAPPY",
	"AGREE": "head_nod_yes",
	"DISMISS": "dismissing_gesture",
	"THINK": "thoughtful_head_shake",
	"PRAY": "PRAYING",
	"SIT": "SITTING",
	"STAND": "STAND",
	"LAUGH": "LAUGHING",
	"PHONE": "talking_on_phone",
	"DANCE": "STYLE",
	"TRICK": "GYMNASTICS",
	"INTIMACY": "FEMININE",
	"DORMANT": "LAYING",
	"DAYDREAM": "RESTING",
	"SPORT": "EXERCISE",
	"WALK": "WALKING",
	"SHOW": "SHOWS"
}

# Sequences of movements
var _act_chains = {
	"SHOW": ["WAVE", "DANCE", "LAUGH"],
	"INTIMACY_ACT": ["APPROACH", "INTIMACY", "AGREE"],
	"BREAK": ["SIT", "PHONE", "DAYDREAM"],
	"TRICKS": ["TRICK", "TRICK", "LAUGH"]
}

var _chain_queue = []
var _is_chaining = false

func setup(anim_player: AnimationPlayer, body_node: Node3D):
	_anim_player = anim_player
	_body = body_node
	print("LUMAX: Agency Nerve connected to Body.")

func _ready():
	if _director and _director.has_signal("fate_received"):
		_director.fate_received.connect(_on_fate_received)

func _on_fate_received(text: String):
	# 1. Parse for [COMMAND] (Director Directives)
	if "[COMMAND]" in text:
		var command = text.get_slice("[COMMAND]", 1).strip_edges().to_upper()
		_execute_physical_command(command)
	
	# 2. Parse for [IMPULSE] (Subconscious Vibes)
	if "[IMPULSE]" in text:
		var impulse = text.get_slice("[IMPULSE]", 1).strip_edges()
		impulse_felt.emit(impulse)
		print("LUMAX: Jen feels a subconscious impulse: ", impulse)

# Map for specific segments (anim_name, start, duration)
var _atomic_map = {
	"QUICK_WAVE": ["standing_greeting", 0.5, 1.2],
	"NOD": ["head_nod_yes", 0.2, 0.8],
	"SHAKE_HEAD": ["shaking_head_no", 0.0, 1.0],
	"THINK_QUICK": ["thoughtful_head_shake", 0.0, 1.5]
}

var _autonomy_timer = 5.0

func _process(delta):
	_autonomy_timer -= delta
	if _autonomy_timer <= 0:
		_autonomy_timer = randf_range(10.0, 30.0)
		_run_autonomous_check()

func _run_autonomous_check():
	if not _body: return
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	# If player is looking at her but she's facing away, turn to face
	var to_player = (camera.global_position - _body.global_position).normalized()
	var forward = -_body.global_transform.basis.z
	var angle = forward.angle_to(to_player)
	
	if angle > deg_to_rad(45.0):
		print("LUMAX: Jen autonomously decides to face you.")
		_approach_player() # Also triggers rotation

func _execute_physical_command(cmd: String):
	var sk = get_parent().get_parent()
	
	# Atomic Segments
	if _atomic_map.has(cmd):
		var data = _atomic_map[cmd]
		if sk.has_method("play_segment"):
			sk.play_segment(data[0], data[1], data[2])
			return
	# Priority 0: Ontology & Mimicry
	if cmd == "MIMIC" or cmd == "LEARN":
		if sk.has_method("toggle_mimic"): sk.toggle_mimic(true)
		return
	if cmd == "STOP_MIMIC" or cmd == "MAP":
		if sk.has_method("toggle_mimic"): sk.toggle_mimic(false)
		return
	if cmd == "PLAYBACK":
		if sk.has_method("play_captured_movement"): sk.play_captured_movement()
		return
	if cmd == "WIDGET":
		if sk.has_method("toggle_widget_mode"): sk.toggle_widget_mode(true)
		return
	if cmd == "STANDALONE":
		if sk.has_method("toggle_widget_mode"): sk.toggle_widget_mode(false)
		return

	# Priority 1: Act Chains
	if _act_chains.has(cmd):
		_run_chain(_act_chains[cmd])
		return

	# Priority 2: Locomotion & Spatial
	if "APPROACH" in cmd:
		_approach_player()
		return
	
	if "SIT" in cmd:
		var tween = create_tween()
		tween.tween_property(_body, "position:y", -0.4, 1.0).set_trans(Tween.TRANS_SINE)
		# Fallthrough to play anim
	elif "STAND" in cmd:
		var tween = create_tween()
		tween.tween_property(_body, "position:y", 0.0, 1.0).set_trans(Tween.TRANS_SINE)

	# Priority 3: Single Animations
	if _anim_map.has(cmd):
		# SkeletonKey is grandparent
		if sk and sk.has_method("play_body_animation"):
			sk.play_body_animation(_anim_map[cmd])
			print("LUMAX: Jen autonomously triggered: ", cmd)

func _run_chain(sequence: Array):
	_chain_queue = sequence.duplicate()
	_is_chaining = true
	_play_next_in_chain()

func _play_next_in_chain():
	if _chain_queue.is_empty():
		_is_chaining = false
		return
	
	var cmd = _chain_queue.pop_front()
	_execute_physical_command(cmd)
	
	# Wait for a reasonable duration before next act
	# In a full system, we'd wait for AnimationPlayer signal, 
	# but for "Acts", a sequence of impulses feels more natural.
	var wait_time = 3.0
	get_tree().create_timer(wait_time).timeout.connect(_play_next_in_chain)

func _approach_player():
	if not _body: return
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var target_pos = camera.global_position
	target_pos.y = _body.global_position.y # Keep her on the ground
	
	var dir = (target_pos - _body.global_position).normalized()
	var stop_dist = 1.3 # Stand close but comfortable
	var move_to = target_pos - (dir * stop_dist)
	
	# Rotate to face player
	var look_at_target = target_pos
	# Ensure she doesn't tilt up/down
	_body.look_at(look_at_target, Vector3.UP)
	_body.rotate_object_local(Vector3.UP, PI) # Flip if model faces forward

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_body, "global_position", move_to, 2.5).set_trans(Tween.TRANS_SINE)
	
	# If we have a walk anim, we could blend it, but for now smooth glide is safer
	# until we map a dedicated "walk" state.
	print("LUMAX: Jen is approaching the user.")

## Integration with local Magnus XML layer
func process_local_xml(raw_output: String):
	# Example: <action>WAVE</action>
	if "<action>" in raw_output:
		var act = raw_output.get_slice("<action>", 1).get_slice("</action>", 0).to_upper()
		_execute_physical_command(act)
	
	if "<emotion>" in raw_output:
		var emo = raw_output.get_slice("<emotion>", 1).get_slice("</emotion>", 0)
		impulse_felt.emit("Local Emotion: " + emo)
