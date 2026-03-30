class_name AvatarController
extends Node

## Implements Kinematic Character Controller with Mixamo Animation States.
## STABILIZED: NO AUTONOMOUS MOVEMENT.

@export var avatar_node: Node3D
@export var player_camera: Node3D

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

# Natural Behavior State
var _blink_timer: float = 0.0
var _next_blink_time: float = 3.0
var _is_blinking: bool = false
var _blink_duration: float = 0.1

enum GazeMode { PLAYER, LOOK_AWAY, IDLE }
var _gaze_mode: int = GazeMode.PLAYER
var _gaze_timer: float = 0.0
var _gaze_target_pos: Vector3 = Vector3.ZERO
var _saccade_timer: float = 0.0
var _saccade_offset: Vector3 = Vector3.ZERO

func _anim_key(anim: StringName) -> StringName:
	return StringName("%s/%s" % [String(_LIB_NAME), String(anim)])

var _is_locked: bool = true

func _process(delta: float) -> void:
	if not avatar_node: return
	_update_eye_contact(delta)
	_process_natural_behavior(delta)
	_process_lip_sync(delta)

func _update_eye_contact(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var target_pos = cam.global_position
	target_pos.y = avatar_node.global_position.y # Horizontal lock
	
	var dir = (target_pos - avatar_node.global_position).normalized()
	if dir.length_squared() > 0.01:
		# FLIPPED: Many VRM models use +Z as forward. 
		# Basis.looking_at points -Z at the target by default.
		# We use -dir to point +Z at the user.
		var target_basis = Basis.looking_at(-dir, Vector3.UP)
		avatar_node.global_transform.basis = avatar_node.global_transform.basis.slerp(target_basis, delta * 1.5)

func _ready() -> void:
	if not avatar_node: 
		avatar_node = get_node_or_null("AvatarModel")
		if not avatar_node:
			# Fallback: search entire parent branch
			avatar_node = get_parent().find_child("AvatarModel", true, false)
			
	_setup_references()
	
	# TEAPOT PROTECTION: Disable the tree until we have animations ready
	if _animation_tree:
		_animation_tree.active = false
		
	_is_locked = true
	call_deferred("play_greeting")

func set_skeleton_key(sk: Node3D):
	# Re-verify references if they were missed during early _ready
	if not _skeleton: _setup_references()
	
	# Link the Tactile Nerve Network to the Synapse
	var tactile = get_node_or_null("TactileNerveNetwork")
	if tactile and sk.get("_synapse"):
		tactile.soul_synapse = sk.get("_synapse")
		print("LUMAX: Tactile Nerve Network linked to Soul Synapse.")
	
	# Explicitly find camera if not set
	if not player_camera:
		player_camera = get_viewport().get_camera_3d()
		
	if _skeleton:
		print("LUMAX: Avatar controller online. Target Skeleton: ", _skeleton.name, " (", _skeleton.get_path(), ")")
	else:
		var node_name = String(avatar_node.name) if avatar_node else "NULL"
		push_error("LUMAX: Avatar controller FAILED to find Skeleton3D in " + node_name)
	
	# NOW populate the mixamo library — SkeletonKey has scanned by the time this is called.
	# Only then is it safe to build and activate the AnimationTree.
	if _body_animation_player:
		_setup_animation_library()
		if _animation_tree:
			var lib = _body_animation_player.get_animation_library(_LIB_NAME) if _body_animation_player.has_animation_library(_LIB_NAME) else null
			if lib and not lib.get_animation_list().is_empty():
				_setup_animation_graph()
				print("LUMAX: AnimationTree initialized with ", lib.get_animation_list().size(), " mixamo clips.")
			else:
				print("LUMAX: AnimationTree deferred (library empty).")

func _process_lip_sync(_delta: float) -> void:
	if not _face_mesh: return
	var voice_player = get_node_or_null("VoicePlayer") as AudioStreamPlayer3D
	if not voice_player or not voice_player.playing:
		_set_blend_shape("Fcl_MTH_A", 0.0) 
		return
	var jitter = randf_range(0.0, 0.5)
	_set_blend_shape("Fcl_MTH_A", jitter)

func _process_natural_behavior(delta: float) -> void:
	_process_blink(delta)
	if _skeleton: _process_eye_contact(delta)

func refresh_animation_system() -> void:
	_setup_animation_library()
	force_resanitize_animations()
	
	var lib = _body_animation_player.get_animation_library("mixamo")
	if lib and not lib.get_animation_list().is_empty():
		_setup_animation_graph()
		print("LUMAX: Animation system REFRESHED and FORCED TO IDLE.")

func _process_blink(delta: float) -> void:
	if not _face_mesh: _find_face_mesh(avatar_node); if not _face_mesh: return
	if not _is_blinking:
		_blink_timer += delta; if _blink_timer >= _next_blink_time: _is_blinking = true; _blink_timer = 0.0; _next_blink_time = randf_range(2.0, 6.0)
	else:
		_blink_timer += delta; var weight = 0.0
		if _blink_timer < _blink_duration * 0.5: weight = _blink_timer / (_blink_duration * 0.5)
		elif _blink_timer < _blink_duration: weight = 1.0 - ((_blink_timer - _blink_duration * 0.5) / (_blink_duration * 0.5))
		else: _is_blinking = false; _blink_timer = 0.0; weight = 0.0
		_set_blend_shape("Fcl_EYE_Close", weight)

func _set_blend_shape(shape_name: String, value: float) -> void:
	if not _face_mesh or not _face_mesh.mesh: return
	var idx = _face_mesh.find_blend_shape_by_name(shape_name)
	if idx == -1: idx = _face_mesh.find_blend_shape_by_name(shape_name.to_lower())
	if idx != -1: _face_mesh.set_blend_shape_value(idx, value)

func _find_face_mesh(node: Node) -> void:
	if not node: return
	if node is MeshInstance3D and node.mesh:
		if node.name.to_lower().contains("face") or node.find_blend_shape_by_name("Fcl_EYE_Close") != -1: _face_mesh = node; return
	for c in node.get_children(): _find_face_mesh(c); if _face_mesh: return

func _process_eye_contact(delta: float) -> void:
	if not _skeleton or _head_bone_idx == -1 or not player_camera: return
	_gaze_timer -= delta; if _gaze_timer <= 0:
		_gaze_mode = GazeMode.LOOK_AWAY if _gaze_mode == GazeMode.PLAYER else GazeMode.PLAYER
		_gaze_timer = randf_range(1.0, 8.0)
		if _gaze_mode == GazeMode.LOOK_AWAY: _gaze_target_pos = avatar_node.global_position + Vector3(randf_range(-2,2), randf_range(0,2), -5)
	
	var look_target = player_camera.global_position if _gaze_mode == GazeMode.PLAYER else _gaze_target_pos
	_saccade_timer -= delta; if _saccade_timer <= 0: _saccade_timer = randf_range(0.2, 1.5); _saccade_offset = Vector3(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), 0)
	look_target += _saccade_offset
	
	var local_look = _skeleton.to_local(look_target)
	var rest_origin = _skeleton.get_bone_rest(_head_bone_idx).origin
	var diff = local_look - rest_origin
	if diff.length_squared() < 0.01: return # Too close, skip to prevent flip
	
	var dir = diff.normalized()
	# DROOP GUARD: Clamp vertical look to -30/+45 degrees to prevent 'Hanging Head'
	dir.y = clamp(dir.y, -0.3, 0.5) 
	
	var current_quat = _skeleton.get_bone_pose_rotation(_head_bone_idx)
	var target_quat = Quaternion(Vector3.FORWARD, dir)
	_skeleton.set_bone_pose_rotation(_head_bone_idx, current_quat.slerp(target_quat, delta * 2.0))

func play_greeting() -> void: play_animation(&"wave")

func play_animation(anim_name: StringName) -> void:
	if not _animation_tree: return
	_animation_tree.active = true # Reactivate tree if it was silenced by pool animations
	var playback = _animation_tree.get("parameters/playback")
	if playback: playback.travel(String(anim_name).capitalize().replace(" ", ""))

func _setup_references() -> void:
	_animation_tree = get_node_or_null("AnimationTree")
	_body_animation_player = avatar_node.find_child("AnimationPlayer", true, false)
	if not _body_animation_player:
		_body_animation_player = avatar_node.find_child("*AnimationPlayer*", true, false)
	
	if not _skeleton:
		_skeleton = avatar_node.find_child("GeneralSkeleton", true, false)
		if not _skeleton:
			_skeleton = avatar_node.find_child("*Skeleton*", true, false)
			
	if _skeleton: 
		_head_bone_idx = _skeleton.find_bone("Head")
		if _head_bone_idx == -1:
			_head_bone_idx = _skeleton.find_bone("head")
			if _head_bone_idx == -1:
				_head_bone_idx = _skeleton.find_bone("Neck")
	
	if _body_animation_player: _setup_animation_library()
	# AnimationTree is NOT started here — it activates only after the mixamo
	# library is populated, which happens in set_skeleton_key() after SkeletonKey
	# has scanned the animation pool.

func _setup_animation_library() -> void:
	var lib = null
	if _body_animation_player.has_animation_library(_LIB_NAME):
		lib = _body_animation_player.get_animation_library(_LIB_NAME)
	
	if not lib:
		lib = AnimationLibrary.new()
		_body_animation_player.add_animation_library(_LIB_NAME, lib)
		
	var sk = get_tree().root.find_child("LumaxCore", true, false)
	# If SkeletonKey isn't yet in tree, we can't fill the library
	if not sk: return
		
	# Only fill if it's still empty, or if we want to ensure it's fresh
	if lib.get_animation_list().is_empty():
		for key in clip_paths.keys():
			var path = sk.call("find_animation_path", clip_paths[key])
			if path != "" and FileAccess.file_exists(path):
				var res = load(path)
				if res is Animation: 
					lib.add_animation(key, res)
	
	force_resanitize_animations()

func force_resanitize_animations() -> void:
	if not _body_animation_player: return
	
	var skel = avatar_node.find_child("Skeleton3D", true, false)
	if not skel: skel = avatar_node.find_child("*Skeleton*", true, false)
	if not skel: return
		
	var skel_path = String(_body_animation_player.get_path_to(skel))
	
	# SANITIZE ALL LIBRARIES
	for lib_name in _body_animation_player.get_animation_library_list():
		var lib = _body_animation_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var anim = lib.get_animation(anim_name)
			if not anim: continue
			
			# IDEMPOTENCY CHECK: Don't re-sanitize if already done for this specific skeleton path
			if anim.has_meta("lumax_skel_path") and anim.get_meta("lumax_skel_path") == skel_path:
				continue
				
			var tracks_fixed = 0
			for i in range(anim.get_track_count()):
				var old_path = String(anim.track_get_path(i))
				
				# REGEX-FREE PRECISE REMAP:
				# We only replace the name if it's the root of the path or preceded by a unique name separator.
				# We look for common default skeleton names: Skeleton3D, GeneralSkeleton, Armature.
				for target in ["Skeleton3D", "GeneralSkeleton", "Armature"]:
					if old_path.contains(target) and not old_path.begins_with(skel_path):
						# If it's something like "AvatarModel/Skeleton3D:Hips", we want it to be "skel_path + :Hips"
						# But we must be careful not to replace bone names that might contain these strings.
						# Realistically, we replace the part before the colon or the whole first segment.
						var parts = old_path.split(":")
						var node_path = parts[0]
						var property_part = ":" + parts[1] if parts.size() > 1 else ""
						
						if node_path.ends_with(target):
							var new_path = skel_path + property_part
							if old_path != new_path:
								anim.track_set_path(i, NodePath(new_path))
								tracks_fixed += 1
								break # Found and fixed
			
			anim.set_meta("lumax_skel_path", skel_path)
			if tracks_fixed > 0:
				print("LUMAX: Sanitized ", tracks_fixed, " tracks in ", lib_name, "/", anim_name, " -> ", skel_path)
	
	print("LUMAX: Bone Injection Sync COMPLETE.")

func _setup_animation_graph() -> void:
	var root = AnimationNodeStateMachine.new()
	
	# Only add nodes for clips that actually exist in the library
	var lib = _body_animation_player.get_animation_library(_LIB_NAME)
	
	if lib.has_animation(&"idle"):
		var locomotion = AnimationNodeAnimation.new()
		locomotion.animation = _LIB_NAME + "/idle"
		root.add_node("Locomotion", locomotion)
	
	if lib.has_animation(&"wave"):
		var wave = AnimationNodeAnimation.new()
		wave.animation = _LIB_NAME + "/wave"
		root.add_node("Wave", wave)
		
		if root.has_node("Locomotion"):
			var to_wave = AnimationNodeStateMachineTransition.new()
			to_wave.xfade_time = 0.3
			root.add_transition("Locomotion", "Wave", to_wave)
			
			var back = AnimationNodeStateMachineTransition.new()
			back.xfade_time = 0.5
			back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
			root.add_transition("Wave", "Locomotion", back)
	
	_animation_tree.tree_root = root
	_animation_tree.anim_player = _animation_tree.get_path_to(_body_animation_player)
	_animation_tree.active = false # START INACTIVE to allow SkeletonKey idle pool freedom
	
	var playback = _animation_tree.get("parameters/playback")
	if playback and root.has_node("Locomotion"): 
		playback.start("Locomotion")
