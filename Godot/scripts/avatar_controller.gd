class_name AvatarController
extends Node

## Implements Kinematic Character Controller with Mixamo Animation States.
## ENHANCED: DYNAMIC IDLE, BEHAVIORAL FRAGMENTS, AND SENSORY AWARENESS.

@export var avatar_node: Node3D
@export var player_camera: Node3D
@export var shyness_intensity: float = 0.3

signal tts_playback_finished
signal capture_requested(source: String)

const _LIB_NAME: StringName = &"mixamo"
@export var clip_paths: Dictionary = {
	&"idle": "breathing_idle",
	&"walk": "standard_walk",
	&"walk_back": "standing_run_back",
	&"walk_left": "standing_walk_left",
	&"walk_right": "standing_walk_right",
	&"run": "walking",
	&"jump": "standing_jump",
	&"turn_left": "left_turn",
	&"turn_right": "right_turn",
	&"sit": "seated_idle",
	&"stand_to_sit": "standing_to_sit",
	&"wave": "standing_greeting",
	&"point": "sitting_and_pointing",
	&"nod": "head_nod_yes",
	&"shake": "shaking_head_no",
	&"happy": "happy_idle",
	&"sad": "sad_idle",
	&"angry": "angry",
	&"laugh": "laughing",
	&"excited": "excited",
	&"bored": "bored",
	&"dance": "dancing_twerk",
	&"texting": "talking_on_phone",
	&"look_around": "look_away_gesture",
	&"lay": "laying_idle",
	&"praying": "praying",
	&"handshake": "shaking_hands_1",
	&"clapping": "standing_clap",
}

var _animation_tree: AnimationTree
var _body_animation_player: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone_idx: int = -1
var _face_mesh: MeshInstance3D

# --- NATURAL BEHAVIOR ENGINE ---
var _blink_timer: float = 0.0
var _next_blink_time: float = 3.0
var _is_blinking: bool = false
var _blink_duration: float = 0.1

enum GazeMode { PLAYER, LOOK_AWAY, IDLE, SHY, INTERESTED }
var _gaze_mode: int = GazeMode.PLAYER
var _gaze_timer: float = 0.0
var _gaze_target_pos: Vector3 = Vector3.ZERO
var _saccade_timer: float = 0.0
var _saccade_offset: Vector3 = Vector3.ZERO

# --- DYNAMIC POSE ENGINE ---
var _idle_variation_timer: float = 0.0
var _procedural_sway: float = 0.0
var _weight_shift: float = 0.0 # -1.0 to 1.0 (Left/Right leg)
var _current_fragments: Array = [] # Active blended animation fragments

func _anim_key(anim: StringName) -> StringName:
	return StringName("%s/%s" % [String(_LIB_NAME), String(anim)])

var _is_locked: bool = true

func _process(delta: float) -> void:
	if not avatar_node: return
	
	_update_body_orientation(delta)
	_process_natural_behavior(delta)
	_process_lip_sync(delta)
	_process_dynamic_pose(delta)

func _update_body_orientation(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var target_pos = cam.global_position
	target_pos.y = avatar_node.global_position.y
	
	var dir = (target_pos - avatar_node.global_position).normalized()
	if dir.length_squared() > 0.01:
		# Slower, more graceful rotation
		var target_basis = Basis.looking_at(-dir, Vector3.UP)
		avatar_node.global_transform.basis = avatar_node.global_transform.basis.slerp(target_basis, delta * 0.5)

func _ready() -> void:
	if not avatar_node: 
		avatar_node = get_node_or_null("AvatarModel")
		if not avatar_node:
			avatar_node = get_parent().find_child("AvatarModel", true, false)
			
	_setup_references()
	
	if _animation_tree:
		_animation_tree.active = false
		
	_is_locked = false
	call_deferred("play_greeting")

func set_skeleton_key(sk: Node3D):
	if not _skeleton: _setup_references()
	
	var tactile = get_node_or_null("TactileNerveNetwork")
	if tactile and sk.get("_synapse"):
		tactile.soul_synapse = sk.get("_synapse")
		# Connect haptic feedback to behavior
		if not tactile.is_connected("touch_perceived", _on_tactile_impulse):
			tactile.touch_perceived.connect(_on_tactile_impulse)
	
	if not player_camera:
		player_camera = get_viewport().get_camera_3d()
		
	if _body_animation_player:
		_setup_animation_library()
		if _animation_tree:
			_setup_animation_graph()

func _on_tactile_impulse(region: String, _intensity: float, _pos: Vector3):
	# Jen 'reacts' to being touched
	if region == "HEAD":
		_gaze_mode = GazeMode.PLAYER
		_gaze_timer = 5.0 # Look at player when head is touched
		if randf() < 0.3: play_animation(&"happy")
	elif region == "BODY_GENERAL":
		if shyness_intensity > 0.5:
			_gaze_mode = GazeMode.SHY
			_gaze_timer = 2.0

func _process_lip_sync(_delta: float) -> void:
	if not _face_mesh: return
	var voice_player = get_node_or_null("VoicePlayer") as AudioStreamPlayer3D
	if not voice_player or not voice_player.playing:
		_set_blend_shape("Fcl_MTH_A", 0.0) 
		return
	_set_blend_shape("Fcl_MTH_A", randf_range(0.0, 0.4))

func _process_natural_behavior(delta: float) -> void:
	_process_blink(delta)
	if _skeleton: _process_eye_contact(delta)

func _process_dynamic_pose(delta: float) -> void:
	# 1. Procedural Breathing/Sway
	_procedural_sway += delta * 0.5
	var sway_v = sin(_procedural_sway) * 0.02
	var sway_h = cos(_procedural_sway * 0.7) * 0.01
	
	# Apply subtle sway to the Hips or Spine if possible
	if _skeleton:
		var hips = _skeleton.find_bone("Hips")
		if hips != -1:
			var cur_pos = _skeleton.get_bone_pose_position(hips)
			_skeleton.set_bone_pose_position(hips, cur_pos + Vector3(sway_h, sway_v, 0) * delta)

	# 2. Periodically shift 'weight' (simulated by varying the idle variation)
	_idle_variation_timer -= delta
	if _idle_variation_timer <= 0:
		_idle_variation_timer = randf_range(10.0, 30.0)
		_weight_shift = randf_range(-1.0, 1.0)
		print("LUMAX: Jen shifting weight pose (%.2f)" % _weight_shift)

func _process_eye_contact(delta: float) -> void:
	if not _skeleton or _head_bone_idx == -1 or not player_camera: return
	
	_gaze_timer -= delta
	if _gaze_timer <= 0:
		_update_gaze_strategy()
	
	var look_target = player_camera.global_position if _gaze_mode == GazeMode.PLAYER else _gaze_target_pos
	
	# Soulful Saccades (Micro-movements of the eyes/head)
	_saccade_timer -= delta
	if _saccade_timer <= 0:
		_saccade_timer = randf_range(0.5, 2.5)
		_saccade_offset = Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), 0)
	
	look_target += _saccade_offset
	var local_look = _skeleton.to_local(look_target)
	var rest_origin = _skeleton.get_bone_rest(_head_bone_idx).origin
	var diff = local_look - rest_origin
	if diff.length_squared() < 0.01: return
	
	var dir = diff.normalized()
	# HEAD LIMITS (Gracious range)
	dir.y = clamp(dir.y, -0.3, 0.5)
	dir.x = clamp(dir.x, -0.6, 0.6)
	
	var current_quat = _skeleton.get_bone_pose_rotation(_head_bone_idx)
	var target_quat = Quaternion(Vector3.FORWARD, dir)
	
	# LERP Speed: Faster when interested, slower when shy
	var speed = 2.5
	if _gaze_mode == GazeMode.SHY: speed = 1.0
	elif _gaze_mode == GazeMode.INTERESTED: speed = 4.0
	
	_skeleton.set_bone_pose_rotation(_head_bone_idx, current_quat.slerp(target_quat, delta * speed))

func _update_gaze_strategy():
	var roll = randf()
	if roll < shyness_intensity:
		_gaze_mode = GazeMode.SHY
		_gaze_timer = randf_range(1.5, 4.0)
		# Look down and slightly away
		_gaze_target_pos = avatar_node.global_position + (avatar_node.global_transform.basis * Vector3(0.4, -0.8, 1.5))
	elif roll < 0.8:
		_gaze_mode = GazeMode.PLAYER
		_gaze_timer = randf_range(4.0, 12.0)
	else:
		_gaze_mode = GazeMode.LOOK_AWAY
		_gaze_timer = randf_range(2.0, 6.0)
		_gaze_target_pos = avatar_node.global_position + Vector3(randf_range(-4,4), randf_range(0.5, 2.5), -4)

func _process_blink(delta: float) -> void:
	_blink_timer += delta
	if not _is_blinking:
		if _blink_timer >= _next_blink_time:
			_is_blinking = true
			_blink_timer = 0.0
	else:
		if _blink_timer <= _blink_duration:
			_set_blend_shape("Fcl_EYE_Close", 1.0)
		else:
			_set_blend_shape("Fcl_EYE_Close", 0.0)
			_is_blinking = false
			_next_blink_time = randf_range(2.0, 6.0)
			_blink_timer = 0.0

func _set_blend_shape(shape_name: String, value: float) -> void:
	if not _face_mesh or not _face_mesh.mesh: return
	var idx = _face_mesh.find_blend_shape_by_name(shape_name)
	if idx == -1: idx = _face_mesh.find_blend_shape_by_name(shape_name.to_lower())
	if idx != -1: _face_mesh.set_blend_shape_value(idx, value)

func play_greeting():
	if clip_paths.has(&"wave"):
		play_animation(&"wave")

func play_animation(anim_name: StringName) -> void:
	if not _animation_tree: return
	
	var state_name = String(anim_name).capitalize().replace(" ", "")
	var playback = _animation_tree.get("parameters/playback")
	
	if playback and _animation_tree.tree_root and _animation_tree.tree_root.has_node(state_name):
		_animation_tree.active = true 
		if playback.get_current_node() != state_name:
			playback.travel(state_name)
	else:
		# Fallback to direct AnimationPlayer
		_animation_tree.active = false
		if _body_animation_player.has_animation(String(_LIB_NAME) + "/" + String(anim_name)):
			_body_animation_player.play(String(_LIB_NAME) + "/" + String(anim_name), 0.5)

func _setup_references() -> void:
	_animation_tree = get_node_or_null("AnimationTree")
	_body_animation_player = avatar_node.find_child("AnimationPlayer", true, false)
	if not _body_animation_player: _body_animation_player = avatar_node.find_child("*AnimationPlayer*", true, false)
	
	_skeleton = avatar_node.find_child("GeneralSkeleton", true, false)
	if not _skeleton: _skeleton = avatar_node.find_child("*Skeleton*", true, false)
			
	if _skeleton: 
		_head_bone_idx = _skeleton.find_bone("Head")
		if _head_bone_idx == -1: _head_bone_idx = _skeleton.find_bone("head")
	
	_face_mesh = null
	_find_face_mesh(avatar_node)
	
	if _body_animation_player: _setup_animation_library()

func _setup_animation_library() -> void:
	var lib = null
	if _body_animation_player.has_animation_library(_LIB_NAME): lib = _body_animation_player.get_animation_library(_LIB_NAME)
	if not lib:
		lib = AnimationLibrary.new(); _body_animation_player.add_animation_library(_LIB_NAME, lib)
		
	var sk = get_tree().root.find_child("LumaxCore", true, false)
	if not sk: return
		
	if lib.get_animation_list().is_empty():
		for key in clip_paths.keys():
			var path = sk.call("find_animation_path", clip_paths[key])
			if path != "" and FileAccess.file_exists(path):
				var res = load(path)
				if res is Animation: lib.add_animation(key, res)
	force_resanitize_animations()

func force_resanitize_animations() -> void:
	if not _body_animation_player or not avatar_node: return
	var skel = _skeleton
	if not skel: return
	
	# Get path relative to the AnimationPlayer's ROOT NODE
	var anim_root_path = _body_animation_player.root_node
	var anim_root = _body_animation_player.get_node(anim_root_path)
	if not anim_root: return
	
	var skel_path = String(anim_root.get_path_to(skel))
	
	if LogMaster: LogMaster.log_info("ANIM_SYSTEM: Resanitizing tracks. Root=" + anim_root.name + " SkelPath=" + skel_path)
	
	for lib_name in _body_animation_player.get_animation_library_list():
		var lib = _body_animation_player.get_animation_library(lib_name)
		var anim_list = lib.get_animation_list()
		
		for anim_name in anim_list:
			var anim = lib.get_animation(anim_name)
			if not anim: continue
			
			var changed = false
			for i in range(anim.get_track_count()):
				var old_path = String(anim.track_get_path(i))
				for target in ["Skeleton3D", "GeneralSkeleton", "Armature"]:
					if old_path.contains(target) and not old_path.begins_with(skel_path):
						var parts = old_path.split(":")
						var new_path = skel_path + (":" + parts[1] if parts.size() > 1 else "")
						anim.track_set_path(i, NodePath(new_path))
						changed = true
						break
			if changed:
				if LogMaster and randf() < 0.01: # Log only occasionally to avoid spam
					LogMaster.log_info("ANIM_SYSTEM: Re-aligned " + anim_name)

func _setup_animation_graph() -> void:
	if not _body_animation_player: return
	var root = AnimationNodeStateMachine.new()
	var lib = _body_animation_player.get_animation_library(_LIB_NAME)
	
	# Add standard locomotion and common interaction states
	var states = ["idle", "wave", "happy", "sad", "walk", "run", "dance", "sit", "praying"]
	for s in states:
		if lib.has_animation(s):
			var node = AnimationNodeAnimation.new()
			node.animation = String(_LIB_NAME) + "/" + s
			var state_name = s.capitalize().replace(" ", "")
			root.add_node(state_name, node)
			if s == "idle":
				root.set_graph_offset(Vector2(0, 0)) # Standard center
	
	_animation_tree.tree_root = root
	_animation_tree.anim_player = _animation_tree.get_path_to(_body_animation_player)
	_animation_tree.active = false 
	var playback = _animation_tree.get("parameters/playback")
	if playback and root.has_node("Idle"): playback.start("Idle")

func _find_face_mesh(node: Node) -> void:
	if not node: return
	if node is MeshInstance3D and node.mesh:
		if node.name.to_lower().contains("face") or node.find_blend_shape_by_name("Fcl_EYE_Close") != -1: _face_mesh = node; return
	for c in node.get_children(): _find_face_mesh(c); if _face_mesh: return
