class_name AvatarController
extends Node3D

## Implements Kinematic Character Controller with Mixamo Animation States.
## ENHANCED: DYNAMIC IDLE, BEHAVIORAL FRAGMENTS, AND SENSORY AWARENESS.

@export var avatar_node: Node3D
@export var player_camera: Node3D
@export var shyness_intensity: float = 0.3
## True = disable auto turn-toward-camera (used while XR Manual Guidance is on so sticks do not fight). Possession is toggled in SkeletonKey (both triggers, no grips), which sets this — leave false for default facing.
@export var steering_active: bool = false
## Many VRM/Mixamo rigs use opposite forward; true helps face the user camera.
@export var invert_front: bool = true
## If computed facing still shows the avatar's back, add 180° from visual mesh forward vs camera.
@export var auto_front_correction: bool = true

@export_group("Startup / first animation")
## Seconds after the Mixamo pool is ready before auto idle (or wave → idle).
@export var startup_greeting_delay_sec: float = 0.35
## If false, no auto play() at startup — Jen stays in T-pose until something else plays idle.
@export var startup_auto_greeting_enabled: bool = true
## If true, play `mixamo/wave` first when available, then idle. **Off by default** (Quest-stable: straight to idle).
@export var startup_begin_with_wave: bool = false
## If wave never fires `animation_finished`, force idle after this many seconds.
@export var startup_wave_safety_idle_sec: float = 6.0
## Block sit/lay/jump/gymnastics-style clips (and matching discovered names). Steering can still opt in per-call.
@export var block_posture_acrobatic_anims: bool = true
## Off by default: state machine had no Start transitions; travel() often left the rig in T-pose. Use AnimationPlayer.play until the graph is complete.
@export var use_animation_tree_for_states: bool = false
## Procedural hip sway; on some VRM retargets additive pose drift → twisted limbs. Keep off unless you need it.
@export var enable_dynamic_pose_engine: bool = false
## Skip head gaze overrides (they fight Mixamo idle); still run blink/lip/orientation.
@export var stabilize_pose_mode: bool = true
## Before `mixamo/idle`, snap bones to skeleton rest (bind), then clear pose overrides.
## Helps bent arms / stuck mid-gesture after a bad clip transition or partial retarget.
@export var snap_rest_pose_before_idle: bool = false

signal tts_playback_finished
signal capture_requested(source: String)

const _LIB_NAME: StringName = &"mixamo"
const _DISCOVERED_LIB: StringName = &"discovered"
@export var clip_paths: Dictionary = {
	&"idle": "neutral_idle",
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

# Spread track rewrites across frames so Quest XR does not freeze (hundreds of clips × many tracks).
const _SANITIZE_BUDGET_PER_FRAME: int = 5
const _SANITIZE_BUDGET_ANDROID: int = 3
var _sanitize_queue: Array = []
var _sanitize_seen_ids: Dictionary = {}
var _sanitize_active: bool = false
var _sanitize_track_rewrites: int = 0

## Mixamo bone names → VRM humanoid (J_Bip_*). Wrong names → T-pose while mixamo/idle "plays".
const _MIXAMO_BONE_TO_VRM: Dictionary = {
	"Hips": "J_Bip_C_Hips",
	"Spine": "J_Bip_C_Spine",
	"Spine1": "J_Bip_C_Chest",
	"Spine2": "J_Bip_C_UpperChest",
	"Chest": "J_Bip_C_Chest",
	"UpperChest": "J_Bip_C_UpperChest",
	"Neck": "J_Bip_C_Neck",
	"Head": "J_Bip_C_Head",
	"LeftShoulder": "J_Bip_L_Shoulder",
	"LeftArm": "J_Bip_L_UpperArm",
	"LeftForeArm": "J_Bip_L_LowerArm",
	"LeftHand": "J_Bip_L_Hand",
	"RightShoulder": "J_Bip_R_Shoulder",
	"RightArm": "J_Bip_R_UpperArm",
	"RightForeArm": "J_Bip_R_LowerArm",
	"RightHand": "J_Bip_R_Hand",
	"LeftUpLeg": "J_Bip_L_UpperLeg",
	"LeftLeg": "J_Bip_L_LowerLeg",
	"LeftFoot": "J_Bip_L_Foot",
	"LeftToeBase": "J_Bip_L_ToeBase",
	"RightUpLeg": "J_Bip_R_UpperLeg",
	"RightLeg": "J_Bip_R_LowerLeg",
	"RightFoot": "J_Bip_R_Foot",
	"RightToeBase": "J_Bip_R_ToeBase",
}

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
var _idle_recover_timer: float = 0.0

func _anim_key(anim: StringName) -> StringName:
	return StringName("%s/%s" % [String(_LIB_NAME), String(anim)])

## Names that contain "sit" / similar but are allowed (short gestures, not posture camping).
const _MOTION_NAME_ALLOW_FRAGMENTS: Array[String] = ["sitting_and_pointing", "standing_greeting", "standing_greet"]

func _animation_motion_blocked(clean_name: String) -> bool:
	if not block_posture_acrobatic_anims:
		return false
	var n := clean_name.to_lower().strip_edges()
	if n.contains("/"):
		n = n.get_file()
	for frag in _MOTION_NAME_ALLOW_FRAGMENTS:
		if frag in n:
			return false
	if n == "sit" or n == "lay" or n == "jump" or n == "stand_to_sit":
		return true
	var probe := n
	if clip_paths.has(StringName(n)):
		probe = String(clip_paths[StringName(n)]).to_lower()
	var hay := n + " " + probe
	var tokens: Array[String] = [
		"jump", "leap", "hop", "flip", "cartwheel", "somersault", "handstand", "backflip",
		"laying", "prone", "crawl", "kneel", "kneeling", "seated", "standing_to_sit", "stand_to_sit",
		"gymnast", "vault", "acrobatic",
	]
	for t in tokens:
		if t in hay:
			return true
	if hay.contains("sit") and not (hay.contains("point") or hay.contains("greet")):
		if hay.contains("sitting_and"):
			return false
		return true
	return false

var _is_locked: bool = true
var _greeting_played: bool = false
var _awaiting_startup_wave_done: bool = false
var _anim_diag_logged: bool = false
## Deferred retries when VRM AnimationPlayer is not in tree on the first frame (export / import timing).
var _vrm_lung_bind_attempts: int = 0
## PC/editor: ~1.5–3s of frames; Quest: VRM + XR can need many more frames before importer children exist.
const _VRM_LUNG_BIND_MAX_ATTEMPTS: int = 90
const _VRM_LUNG_BIND_MAX_ATTEMPTS_ANDROID: int = 240
## After one burst of deferred tries, pause and retry (Quest was stopping forever — attempts reset then returned with no follow-up).
var _lung_bind_retry_waves: int = 0
const _LUNG_BIND_MAX_WAVES: int = 160
const _META_RUNTIME_VRM_LUNGS: StringName = &"lumax_runtime_vrm_lungs"

func _sanitize_budget_for_platform() -> int:
	return _SANITIZE_BUDGET_ANDROID if OS.get_name() == "Android" else _SANITIZE_BUDGET_PER_FRAME

func _vrm_lung_bind_max_attempts() -> int:
	return _VRM_LUNG_BIND_MAX_ATTEMPTS_ANDROID if OS.get_name() == "Android" else _VRM_LUNG_BIND_MAX_ATTEMPTS

func _process(delta: float) -> void:
	# avatar_node drives orientation / gaze; sanitize must run even if export was not wired yet.
	if avatar_node and is_instance_valid(avatar_node):
		_update_body_orientation(delta)
		if not stabilize_pose_mode:
			_process_natural_behavior(delta)
		else:
			_process_blink(delta)
		_process_lip_sync(delta)
		if enable_dynamic_pose_engine:
			_process_dynamic_pose(delta)
		_recover_idle_if_player_stopped(delta)
	_process_sanitize_chunk()

func _reset_skeleton_to_rest_pose() -> void:
	if not _skeleton or not is_instance_valid(_skeleton):
		return
	var bc := _skeleton.get_bone_count()
	for i in range(bc):
		var rest: Transform3D = _skeleton.get_bone_rest(i)
		_skeleton.set_bone_pose_position(i, rest.origin)
		_skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		_skeleton.set_bone_pose_scale(i, rest.basis.get_scale())

func _process_sanitize_chunk() -> void:
	if not _sanitize_active:
		return
	var budget: int = _sanitize_budget_for_platform()
	while budget > 0 and _sanitize_queue.size() > 0:
		var anim = _sanitize_queue.pop_front()
		if anim is Animation and is_instance_valid(anim):
			_sanitize_track_rewrites += _sanitize_animation_resource_internal(anim)
		budget -= 1
	if _sanitize_queue.is_empty():
		_sanitize_active = false
		if _sanitize_track_rewrites > 0:
			print("LUMAX_ANIM: Sanitize done (%d track paths rewritten, spread across frames)." % _sanitize_track_rewrites)
		_sanitize_track_rewrites = 0

func _update_body_orientation(delta: float) -> void:
	if steering_active: return # Don't fight manual steering
	
	if not avatar_node or not is_instance_valid(avatar_node): return
	var parent_body = avatar_node.get_parent() as Node3D
	if not parent_body: 
		parent_body = get_parent() as Node3D
		if not parent_body: return
	
	# ROBUST CAMERA DISCOVERY: get_viewport() can fail on Quest 3 mobile sessions.
	var cam = get_viewport().get_camera_3d()
	if not cam: cam = get_tree().root.find_child("*UserCamera*", true, false)
	if not cam: cam = get_tree().root.find_child("*XRCamera*", true, false)
	if not cam: cam = get_tree().root.find_child("*Camera*", true, false)
	
	if not cam: return
	
	var target_pos: Vector3 = cam.global_position
	target_pos.y = parent_body.global_position.y
	
	var dir: Vector3 = (target_pos - parent_body.global_position).normalized()
	if dir.length_squared() > 0.01:
		# SMOOTH ORIENTATION: parent -Z toward camera; optional flips for VRM vs Godot forward.
		var target_basis: Basis = Basis.looking_at(dir, Vector3.UP)
		if invert_front:
			target_basis = target_basis.rotated(Vector3.UP, PI)
		if auto_front_correction:
			var visual_local_basis := avatar_node.transform.basis.orthonormalized()
			var visual_world_basis := target_basis * visual_local_basis
			var visual_forward := (-visual_world_basis.z).normalized()
			if visual_forward.dot(dir) < 0.0:
				target_basis = target_basis.rotated(Vector3.UP, PI)
		var q_current: Quaternion = parent_body.global_transform.basis.orthonormalized().get_rotation_quaternion()
		var q_target: Quaternion = target_basis.orthonormalized().get_rotation_quaternion()
		parent_body.global_transform.basis = Basis(q_current.slerp(q_target, delta * 1.5))

func _ready() -> void:
	if not avatar_node: 
		avatar_node = get_node_or_null("AvatarModel")
		if not avatar_node:
			avatar_node = get_parent().find_child("AvatarModel", true, false)
			
	_vrm_lung_bind_attempts = 0
	_lung_bind_retry_waves = 0
	_setup_references()
	# Tree stays off until play_animation picks tree or player path (avoid fighting the mixer each frame).
	if _animation_tree:
		_animation_tree.active = false
	_is_locked = false
	call_deferred("_deferred_bind_vrm_animation_player")

## Call after `AvatarModel` is replaced at runtime (SkeletonKey VRM swap) so lung bind + Mixamo repopulation run again.
func notify_avatar_model_rebound() -> void:
	_vrm_lung_bind_attempts = 0
	_lung_bind_retry_waves = 0
	_anim_diag_logged = false
	_setup_references()
	if _animation_tree:
		_animation_tree.active = false
	call_deferred("_deferred_bind_vrm_animation_player")

## Runtime vessel swap loads a raw VRM scene without Lumax_Jen’s extra `LumaxAnimPlayer` child — add it so Mixamo targets match the default scene.
func ensure_lumax_anim_player_sibling() -> void:
	var model = get_node_or_null("AvatarModel")
	if not model or not is_instance_valid(model):
		return
	if model.get_node_or_null("LumaxAnimPlayer"):
		return
	var ap := AnimationPlayer.new()
	ap.name = "LumaxAnimPlayer"
	model.add_child(ap)
	if model.owner:
		ap.owner = model.owner
	print("LUMAX_ANIM: Created LumaxAnimPlayer under AvatarModel (runtime vessel swap).")

func _lumax_intimacy_level() -> float:
	var sk = get_tree().get_first_node_in_group("lumax_core")
	if sk and sk.has_method("get_intimacy_level"):
		return clampf(float(sk.call("get_intimacy_level")), 0.0, 1.0)
	return 0.45


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

func _on_tactile_impulse(region: String, intensity: float, _pos: Vector3, is_gentle: bool):
	var intim: float = _lumax_intimacy_level()
	var gaze_mul: float = clampf(0.82 + 0.38 * intim, 0.75, 1.45)
	var soft_pick: float = clampf(0.42 + 0.22 * intim + (0.12 if is_gentle else 0.0), 0.35, 0.88)

	# Handle specialized sensory events (like TICKLE from grabbing)
	if "TICKLE" in region:
		_gaze_mode = GazeMode.PLAYER
		_gaze_timer = 5.0 * gaze_mul
		play_animation(&"laugh")
		return

	# Jen 'reacts' to being touched (scaled by runtime intimacy + touch quality)
	if is_gentle:
		if "EROGENOUS" in region:
			_gaze_mode = GazeMode.PLAYER
			_gaze_timer = (10.0 + 4.0 * intensity) * gaze_mul
			if randf() < soft_pick: play_animation(&"happy")
			else: play_animation(&"texting")
		elif region == "HEAD":
			_gaze_mode = GazeMode.PLAYER
			_gaze_timer = 5.0 * gaze_mul
			play_animation(&"happy")
	else:
		_gaze_mode = GazeMode.SHY
		_gaze_timer = (3.0 - 0.4 * intim) * clampf(1.15 - 0.25 * intensity, 0.75, 1.2)
		if randf() < 0.4: play_animation(&"angry")
		elif randf() < 0.7: play_animation(&"sad")
		else: play_animation(&"look_around")

func _process_lip_sync(_delta: float) -> void:
	if not _face_mesh: return
	var voice_player = get_node_or_null("VoicePlayer") as AudioStreamPlayer3D
	if not voice_player or not voice_player.playing:
		_set_blend_shape("Fcl_MTH_A", 0.0) 
		return
	_set_blend_shape("Fcl_MTH_A", randf_range(0.0, 0.4))

func _process_natural_behavior(delta: float) -> void:
	_process_blink(delta)
	if _skeleton:
		_process_eye_contact(delta)

func _process_dynamic_pose(delta: float) -> void:
	# 1. Procedural Breathing/Sway (anchored to rest — additive on pose caused long-run drift / twisted rig)
	_procedural_sway += delta * 0.5
	var sway_v = sin(_procedural_sway) * 0.02
	var sway_h = cos(_procedural_sway * 0.7) * 0.01
	if _skeleton:
		var hips = _skeleton.find_bone("Hips")
		if hips == -1:
			hips = _skeleton.find_bone("J_Bip_C_Hips")
		if hips != -1:
			var rest_pos = _skeleton.get_bone_rest(hips).origin
			var offset = Vector3(sway_h + (_weight_shift * 0.004), sway_v, 0.0)
			_skeleton.set_bone_pose_position(hips, rest_pos + offset)
	_idle_variation_timer -= delta
	if _idle_variation_timer <= 0:
		_idle_variation_timer = randf_range(10.0, 30.0)
		_weight_shift = randf_range(-1.0, 1.0)
		print("LUMAX: Jen shifting weight pose (%.2f)" % _weight_shift)

func _recover_idle_if_player_stopped(delta: float) -> void:
	if not _body_animation_player or not is_instance_valid(_body_animation_player):
		return
	if steering_active:
		_idle_recover_timer = 0.0
		return
	var idle_key := String(_anim_key(&"idle"))
	if _body_animation_player.is_playing():
		_idle_recover_timer = 0.0
		return
	_idle_recover_timer += delta
	if _idle_recover_timer < 1.5:
		return
	_idle_recover_timer = 0.0
	if _body_animation_player.has_animation(idle_key):
		print("LUMAX_ANIM: idle recover (player stopped).")
		_body_animation_player.stop()
		play_animation(&"idle", -1.0, 1.0, true)

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
	# Godot 4: Quaternion(axis, angle) — do NOT pass two Vector3s (was corrupting head pose / upside-down).
	var head_up := Vector3.UP
	if absf(dir.dot(head_up)) > 0.92:
		head_up = Vector3.RIGHT
	var target_quat: Quaternion = Basis.looking_at(dir, head_up).get_rotation_quaternion()
	
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

func _cue_skeleton_idle_loop() -> void:
	var lumax = get_tree().root.find_child("LumaxCore", true, false) if get_tree() else null
	if lumax and lumax.has_method("cue_initial_idle_loop"):
		lumax.call("cue_initial_idle_loop")
	else:
		play_animation(&"idle")

func _on_startup_wave_finished(anim: StringName) -> void:
	if not _awaiting_startup_wave_done:
		return
	if not String(anim).to_lower().contains("wave"):
		return
	_awaiting_startup_wave_done = false
	_cue_skeleton_idle_loop()

func _startup_wave_safety_to_idle() -> void:
	if not _awaiting_startup_wave_done:
		return
	_awaiting_startup_wave_done = false
	_cue_skeleton_idle_loop()

## One-shot after load: mixamo wave (optional) then Chosen idle pool or mixamo idle.
func _try_play_greeting_once() -> void:
	if _greeting_played or not is_instance_valid(_body_animation_player):
		return
	_greeting_played = true
	var wave_path: String = String(_LIB_NAME) + "/wave"
	var has_wave: bool = startup_begin_with_wave and _body_animation_player.has_animation(wave_path)
	if has_wave:
		_awaiting_startup_wave_done = true
		_body_animation_player.animation_finished.connect(_on_startup_wave_finished, CONNECT_ONE_SHOT)
		if get_tree():
			get_tree().create_timer(maxf(0.5, startup_wave_safety_idle_sec)).timeout.connect(_startup_wave_safety_to_idle, CONNECT_ONE_SHOT)
		play_animation(&"wave")
	else:
		_cue_skeleton_idle_loop()

func _anim_library_debug_summary() -> String:
	if not is_instance_valid(_body_animation_player):
		return "no AnimationPlayer"
	var ps: PackedStringArray = PackedStringArray()
	for lib_name in _body_animation_player.get_animation_library_list():
		var lib = _body_animation_player.get_animation_library(lib_name)
		var n = 0
		if lib:
			n = lib.get_animation_list().size()
		ps.append("%s:%d" % [String(lib_name), n])
	return ", ".join(ps)

func _body_animation_tree_can_use_state_travel() -> bool:
	if not _animation_tree or not _animation_tree.tree_root:
		return false
	var tr = _animation_tree.tree_root
	if tr is AnimationNodeStateMachine:
		return (tr as AnimationNodeStateMachine).get_transition_count() > 0
	return true

## Use single-arg play() when blend/speed are defaults; avoids redundant path through the mixer.
func _animation_player_play_resolved(ap: AnimationPlayer, anim_key: StringName, blend: float, speed: float) -> void:
	if ap == null or not is_instance_valid(ap):
		return
	var key_s := String(anim_key)
	if not ap.has_animation(key_s):
		return
	ap.active = true
	if blend < 0.0 and absf(speed - 1.0) < 0.00001:
		ap.play(key_s)
	else:
		ap.play(key_s, blend, speed)

func play_animation(anim_name: StringName, custom_blend: float = -1.0, custom_speed: float = 1.0, allow_posture_acrobatic: bool = false) -> void:
	if not _body_animation_player or not is_instance_valid(_body_animation_player):
		_setup_references()
		if not _body_animation_player: return

	var clean_for_block := String(anim_name).to_lower()
	if block_posture_acrobatic_anims and not allow_posture_acrobatic and _animation_motion_blocked(clean_for_block):
		print("LUMAX_ANIM: posture/acrobatic blocked → idle: %s" % clean_for_block)
		play_animation(&"idle", custom_blend, custom_speed, true)
		return

	var state_name = String(anim_name).capitalize().replace(" ", "")
	
	var playback = null
	if _animation_tree: playback = _animation_tree.get("parameters/playback")
	
	var use_tree: bool = (
		use_animation_tree_for_states
		and _body_animation_tree_can_use_state_travel()
		and _body_animation_player.name != "ProceduralLungs"
		and _animation_tree
		and playback
		and _animation_tree.tree_root
		and _animation_tree.tree_root.has_node(state_name)
	)
	if use_tree:
		_animation_tree.active = true
		if playback.get_current_node() != state_name:
			playback.travel(state_name)
	else:
		# Direct AnimationPlayer path: tree must stay off or it overrides the same skeleton.
		if _animation_tree:
			_animation_tree.active = false
		var clean_name := clean_for_block
		if clean_name == "idle":
			if snap_rest_pose_before_idle:
				_reset_skeleton_to_rest_pose()
			_reset_skeleton_pose_overrides_for_idle()
		var full_anim_path = String(_LIB_NAME) + "/" + clean_name
		
		if _body_animation_player and is_instance_valid(_body_animation_player) and _body_animation_player.has_animation(full_anim_path):
			_body_animation_player.active = true
			_animation_player_play_resolved(_body_animation_player, StringName(full_anim_path), custom_blend, custom_speed)
		elif _body_animation_player and is_instance_valid(_body_animation_player) and _body_animation_player.has_animation_library(_DISCOVERED_LIB):
			var disc_path: String = String(_DISCOVERED_LIB) + "/" + clean_name
			if _body_animation_player.has_animation(disc_path):
				_body_animation_player.active = true
				_animation_player_play_resolved(_body_animation_player, StringName(disc_path), custom_blend, custom_speed)
			else:
				_try_play_animation_fallback(full_anim_path, clean_name, custom_blend, custom_speed)
		elif _body_animation_player and is_instance_valid(_body_animation_player):
			_try_play_animation_fallback(full_anim_path, clean_name, custom_blend, custom_speed)

func _reset_skeleton_pose_overrides_for_idle() -> void:
	if not _skeleton or not is_instance_valid(_skeleton):
		return
	if _skeleton.has_method("reset_bone_poses"):
		_skeleton.call("reset_bone_poses")

func _try_play_animation_fallback(full_anim_path: String, clean_name: String, custom_blend: float, custom_speed: float) -> void:
	if not _body_animation_player or not is_instance_valid(_body_animation_player):
		return
	print("LUMAX_ANIM: Searching for fallback for: %s" % full_anim_path)
	var found = false
	for lib_name in _body_animation_player.get_animation_library_list():
		var lib = _body_animation_player.get_animation_library(lib_name)
		for a in lib.get_animation_list():
			var a_name = String(lib_name) + "/" + String(a)
			if a_name.to_lower() == full_anim_path.to_lower() or String(a).to_lower() == clean_name:
				_body_animation_player.active = true
				_animation_player_play_resolved(_body_animation_player, StringName(a_name), custom_blend, custom_speed)
				found = true
				break
		if found:
			break
	if not found:
		print("LUMAX_ANIM: ERROR - [%s] not found. Libraries: %s" % [full_anim_path, _anim_library_debug_summary()])

func _migrate_animation_player_libraries(from: AnimationPlayer, to: AnimationPlayer) -> void:
	if not from or not to or from == to or not is_instance_valid(from) or not is_instance_valid(to):
		return
	for lib_name in from.get_animation_library_list():
		var src_lib = from.get_animation_library(lib_name)
		if not src_lib:
			continue
		var dst_lib: AnimationLibrary = null
		if to.has_animation_library(lib_name):
			dst_lib = to.get_animation_library(lib_name)
		else:
			dst_lib = AnimationLibrary.new()
			to.add_animation_library(lib_name, dst_lib)
		for aname in src_lib.get_animation_list():
			if dst_lib.has_animation(aname):
				continue
			var res = src_lib.get_animation(aname)
			if res:
				dst_lib.add_animation(aname, res)

func _refresh_skeleton_key_anim_player_reference() -> void:
	var core = get_tree().root.find_child("LumaxCore", true, false) if get_tree() else null
	if core and core.has_method("refresh_jen_anim_player"):
		core.call("refresh_jen_anim_player")

func _manifest_runtime_animation_player_under_avatar_model(av_model: Node) -> AnimationPlayer:
	# Godot-VRM always attaches AnimationPlayer to the VRM scene root (vrm_extension.gd). Some exports omit it; mirror that layout.
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	av_model.add_child(ap)
	ap.owner = av_model
	ap.root_node = ap.get_path_to(self)
	ap.set_meta(_META_RUNTIME_VRM_LUNGS, true)
	return ap

func _resolve_vrm_animation_player(model: Node) -> AnimationPlayer:
	if not is_instance_valid(model):
		return null
	# Godot-VRM default name/path (addons/vrm/vrm_extension.gd); matches Lumax_Jen AnimationTree anim_player.
	var direct: Node = model.get_node_or_null("AnimationPlayer")
	if direct is AnimationPlayer:
		return direct
	# Dedicated Mixamo lungs (Lumax_Jen.tscn) fallback if importer player is absent.
	var lumax_ap: Node = model.get_node_or_null("LumaxAnimPlayer")
	if lumax_ap is AnimationPlayer:
		return lumax_ap
	# owned=false: instanced/exported VRM children may not match owner filter used by find_child default.
	var by_name: Node = model.find_child("AnimationPlayer", true, false)
	if by_name is AnimationPlayer:
		return by_name
	var found: Node = _nuclear_find_node(model, ["AnimationPlayer", "AnimationMixer", "AnimPlayer"])
	return found if found is AnimationPlayer else null

func _lung_bind_retry_after_pause() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_body_animation_player) and _body_animation_player.name != "ProceduralLungs":
		_lung_bind_retry_waves = 0
		return
	call_deferred("_deferred_bind_vrm_animation_player")

func _deferred_bind_vrm_animation_player() -> void:
	if not is_inside_tree():
		return
	var model = get_node_or_null("AvatarModel")
	# Importer, Lumax_Jen LumaxAnimPlayer, or runtime manifest: lungs under AvatarModel — stop retrying.
	if is_instance_valid(_body_animation_player) and model and _body_animation_player.get_parent() == model \
			and (_body_animation_player.name == "AnimationPlayer" or _body_animation_player.name == "LumaxAnimPlayer"):
		_vrm_lung_bind_attempts = 0
		_lung_bind_retry_waves = 0
		return
	if is_instance_valid(_body_animation_player) and _body_animation_player.name != "ProceduralLungs":
		_vrm_lung_bind_attempts = 0
		_lung_bind_retry_waves = 0
		return
	if not model:
		return
	var max_attempts: int = _vrm_lung_bind_max_attempts()
	var found: AnimationPlayer = _resolve_vrm_animation_player(model)
	if not (found is AnimationPlayer) or found == _body_animation_player:
		if _vrm_lung_bind_attempts >= max_attempts:
			_vrm_lung_bind_attempts = 0
			_lung_bind_retry_waves += 1
			if is_instance_valid(_body_animation_player) and _body_animation_player.name == "ProceduralLungs":
				if _lung_bind_retry_waves == 1 or _lung_bind_retry_waves % 12 == 0:
					print("LUMAX_ANIM: WARN - VRM lungs not ready (wave %d/%d); retrying — common on Quest slow load." % [_lung_bind_retry_waves, _LUNG_BIND_MAX_WAVES])
			if _lung_bind_retry_waves <= _LUNG_BIND_MAX_WAVES and get_tree():
				get_tree().create_timer(0.35).timeout.connect(_lung_bind_retry_after_pause, CONNECT_ONE_SHOT)
			elif is_instance_valid(_body_animation_player) and _body_animation_player.name == "ProceduralLungs":
				print("LUMAX_ANIM: ERROR - No VRM AnimationPlayer under AvatarModel after %d waves. Export/reimport VRM on device." % _LUNG_BIND_MAX_WAVES)
			return
		_vrm_lung_bind_attempts += 1
		call_deferred("_deferred_bind_vrm_animation_player")
		return
	_vrm_lung_bind_attempts = 0
	_lung_bind_retry_waves = 0
	print("LUMAX_ANIM: SUCCESS - Late-bound VRM AnimationPlayer at: %s (replacing placeholder lungs)" % found.get_path())
	if is_instance_valid(_body_animation_player) and _body_animation_player.name == "ProceduralLungs":
		_migrate_animation_player_libraries(_body_animation_player, found)
		_body_animation_player.queue_free()
	_body_animation_player = found
	_refresh_skeleton_key_anim_player_reference()
	_setup_animation_library()
	if _animation_tree:
		_setup_animation_graph()
		_animation_tree.active = false
	if is_instance_valid(_body_animation_player) and is_instance_valid(_skeleton):
		_sanitize_curated_libraries_immediate()

func _setup_references() -> void:
	if not is_inside_tree(): return
	
	_animation_tree = get_node_or_null("AnimationTree")
	if _animation_tree: _animation_tree.active = false
	
	# Prefer VRM's AnimationPlayer under AvatarModel (Lumax_Jen has no top-level lungs).
	var av_model: Node = get_node_or_null("AvatarModel")
	if av_model:
		_body_animation_player = _resolve_vrm_animation_player(av_model)
	if not _body_animation_player:
		_body_animation_player = _nuclear_find_node(self, ["AnimationPlayer", "AnimationMixer", "AnimPlayer"])
	# Resolve skeleton under AvatarModel first so we do not bind Mixamo sanitize to an unrelated Skeleton3D elsewhere in the scene.
	if av_model:
		_skeleton = _nuclear_find_node(av_model, ["GeneralSkeleton", "Skeleton3D", "Skeleton"])
	if not _skeleton:
		_skeleton = _nuclear_find_node(self, ["GeneralSkeleton", "Skeleton3D", "Skeleton"])
	
	if not _body_animation_player:
		# Second-tier search: Body / parent (never grab XR hand players from scene root)
		var body_scope: Node = get_parent()
		if body_scope:
			_body_animation_player = _nuclear_find_node(body_scope, ["AnimationPlayer", "AnimationMixer"])

	if not _body_animation_player:
		# Scoped scan under LumaxCore/Body only (avoid FunctionPointer hand AnimationPlayers).
		print("LUMAX_ANIM: CRITICAL - Performing scoped Body scan for AnimationPlayer...")
		var lumax = get_tree().root.find_child("LumaxCore", true, false) if get_tree() else null
		var body_node = lumax.get_node_or_null("Body") if lumax else null
		if body_node:
			_body_animation_player = _nuclear_find_node(body_node, ["AnimationPlayer", "AnimationMixer"])

	if not _body_animation_player:
		# Match Godot-VRM: AnimationPlayer must live under AvatarModel so tracks resolve against the VRM skeleton.
		var av_em := get_node_or_null("AvatarModel")
		if av_em:
			print("LUMAX_ANIM: CRITICAL - VRM instance has no AnimationPlayer; manifesting one under AvatarModel (export/import issue).")
			_body_animation_player = _manifest_runtime_animation_player_under_avatar_model(av_em)
		else:
			print("LUMAX_ANIM: CRITICAL - No AvatarModel; fallback AnimationPlayer on Avatar root (ProceduralLungs).")
			_body_animation_player = AnimationPlayer.new()
			_body_animation_player.name = "ProceduralLungs"
			add_child(_body_animation_player)
			_body_animation_player.root_node = _body_animation_player.get_path_to(self)

	if not _body_animation_player:
		print("LUMAX_ANIM: WARNING - [LUNGS_MISSING] TOTAL HIERARCHY AUDIT (self):")
		_dump_entire_hierarchy(self, "")
		if get_tree(): 
			var timer = get_tree().create_timer(10.0)
			if timer: timer.timeout.connect(_setup_references)
		return

	if is_instance_valid(_body_animation_player):
		# VRM import often leaves root_node empty → editor warning + broken track resolution vs Mixamo sanitize (Avatar-relative paths).
		if _body_animation_player.name != "ProceduralLungs" and _body_animation_player.root_node.is_empty():
			_body_animation_player.root_node = _body_animation_player.get_path_to(self)
			print("LUMAX_ANIM: Set AnimationPlayer root_node to Avatar: %s" % String(_body_animation_player.root_node))
		if _animation_tree and is_instance_valid(_animation_tree):
			_animation_tree.anim_player = _animation_tree.get_path_to(_body_animation_player)
		if _body_animation_player.has_meta(_META_RUNTIME_VRM_LUNGS):
			print("LUMAX_ANIM: INFO - Runtime AnimationPlayer under AvatarModel (VRM had none). %s" % _body_animation_player.get_path())
		elif _body_animation_player.name == "ProceduralLungs":
			print("LUMAX_ANIM: WARNING - Using ProceduralLungs (no AvatarModel) at: %s" % _body_animation_player.get_path())
		else:
			print("LUMAX_ANIM: SUCCESS - Lungs discovered at: %s" % _body_animation_player.get_path())
		# Child _ready runs before LumaxCore _ready; defer so find_animation_path sees Chosen/ index.
		call_deferred("_setup_animation_library")

	if is_instance_valid(_skeleton): 
		print("LUMAX_ANIM: SUCCESS - Skeleton discovered at: %s" % _skeleton.get_path())
		_head_bone_idx = _skeleton.find_bone("Head")
		if _head_bone_idx == -1: _head_bone_idx = _skeleton.find_bone("head")
		if _head_bone_idx == -1: _head_bone_idx = _skeleton.find_bone("J_Bip_C_Head")
	
	_face_mesh = null
	_find_face_mesh(self)

func _nuclear_find_node(root: Node, keywords: Array) -> Node:
	if not root: return null
	
	# Check by Type (Priority: MUST be an AnimationPlayer, NEVER an AnimationTree)
	if root is AnimationPlayer:
		return root
	if "Skeleton" in keywords and root is Skeleton3D:
		return root
	
	# Name match only counts if this is an AnimationPlayer (VRM may add plain AnimationMixer — do not use for Mixamo play()).
	var r_name = root.name.to_lower()
	for k in keywords:
		if k.to_lower() in r_name and not root is AnimationTree and root is AnimationPlayer:
			return root
	
	# Check children recursively
	for child in root.get_children():
		var found = _nuclear_find_node(child, keywords)
		if found: return found
	return null

func _setup_animation_library() -> void:
	if not is_instance_valid(_body_animation_player): return
	var lib = null
	if _body_animation_player.has_animation_library(_LIB_NAME): lib = _body_animation_player.get_animation_library(_LIB_NAME)
	if not lib:
		lib = AnimationLibrary.new(); _body_animation_player.add_animation_library(_LIB_NAME, lib)
		
	var sk = get_tree().root.find_child("LumaxCore", true, false)
	if not sk: 
		print("LUMAX_ANIM: ERROR - LumaxCore not found! Cannot load Mixamo animations.")
		return
		
	var found_any = false
	if lib:
		for key in clip_paths.keys():
			var clean_key = String(key).to_lower()
			var path = sk.call("find_animation_path", clip_paths[key])
			if path != "" and FileAccess.file_exists(path):
				var res = load(path)
				if res is Animation: 
					lib.add_animation(clean_key, res)
					found_any = true
				else:
					print("LUMAX_ANIM: ERROR - Failed to load Animation resource at: %s" % path)
			else:
				# Verbose debug for path failures
				pass # Path not found yet
	
	if not found_any:
		print("LUMAX_ANIM: WARNING - No animations found in pool. Requesting re-scan and retrying...")
		if sk.has_method("_scan_for_animations"): sk.call("_scan_for_animations")
		get_tree().create_timer(2.0).timeout.connect(_setup_animation_library)
		return
	
	print("LUMAX_ANIM: SUCCESS - Animation pool populated. Count: %d" % lib.get_animation_list().size())
	# Sanitize BEFORE set_skeleton_key builds AnimationTree — tree caches clip paths; deferred sanitize caused native crashes.
	_sanitize_curated_libraries_immediate()
	# Startup: wave → idle. Under XR (any platform), add slack so idle does not race Mind wiring (~1.25s presence apply).
	if startup_auto_greeting_enabled and get_tree():
		var greet_delay: float = maxf(0.0, startup_greeting_delay_sec)
		var vp := get_viewport()
		var xr_greet: bool = vp != null and vp.use_xr
		if not xr_greet:
			var xri: XRInterface = XRServer.find_interface("OpenXR")
			xr_greet = xri != null and xri.is_initialized()
		if OS.get_name() == "Android" or xr_greet:
			greet_delay += 1.25
		get_tree().create_timer(greet_delay).timeout.connect(_try_play_greeting_once, CONNECT_ONE_SHOT)

func _sanitize_curated_libraries_immediate() -> void:
	if not is_instance_valid(_body_animation_player) or not is_instance_valid(_skeleton):
		return
	var total: int = 0
	var mixamo_lib = _body_animation_player.get_animation_library(_LIB_NAME)
	if mixamo_lib:
		for anim_name in mixamo_lib.get_animation_list():
			var anim = mixamo_lib.get_animation(anim_name)
			if anim is Animation:
				total += _sanitize_animation_resource_internal(anim)
	if _body_animation_player.has_animation_library(&"lumax"):
		var lumax_lib = _body_animation_player.get_animation_library(&"lumax")
		if lumax_lib:
			for anim_name in lumax_lib.get_animation_list():
				var anim = lumax_lib.get_animation(anim_name)
				if anim is Animation:
					total += _sanitize_animation_resource_internal(anim)
	if total > 0:
		print("LUMAX_ANIM: Mixamo paths sanitized immediately (%d track rewrites)." % total)
	call_deferred("_log_animation_bind_diag_once")

func _log_animation_bind_diag_once() -> void:
	if _anim_diag_logged:
		return
	_anim_diag_logged = true
	if not is_instance_valid(_body_animation_player):
		print("LUMAX_ANIM_DIAG: No AnimationPlayer — T-pose expected until lungs bind.")
		return
	var sk_path := ""
	if is_instance_valid(_skeleton):
		sk_path = String(_skeleton.get_path())
	var tree_path := ""
	if is_instance_valid(_animation_tree):
		tree_path = String(_animation_tree.anim_player)
	print("LUMAX_ANIM_DIAG: player=%s name=%s active=%s root_node=%s skeleton=%s tree.anim_player=%s mixamo/idle=%s playing=%s cur=%s" % [
		_body_animation_player.get_path(),
		_body_animation_player.name,
		_body_animation_player.active,
		String(_body_animation_player.root_node),
		sk_path,
		tree_path,
		_body_animation_player.has_animation(String(_LIB_NAME) + "/idle"),
		_body_animation_player.is_playing(),
		_body_animation_player.current_animation,
	])
	var lib_idle = _body_animation_player.get_animation_library(_LIB_NAME)
	if lib_idle and lib_idle.has_animation(&"idle"):
		var ia = lib_idle.get_animation(&"idle")
		if ia is Animation:
			for ti in range(mini(ia.get_track_count(), 40)):
				var tp := String(ia.track_get_path(ti))
				if "Skeleton" in tp or "Armature" in tp:
					print("LUMAX_ANIM_DIAG: mixamo/idle first_bone_track=%s (must be reachable from root_node)" % tp)
					break

func _enqueue_all_animations_for_sanitize() -> void:
	_sanitize_queue.clear()
	_sanitize_seen_ids.clear()
	if not is_instance_valid(_body_animation_player):
		return
	# Only curated Mixamo (and optional lumax) — not "discovered" (100+ clips). Chunked pass stays cheap.
	_enqueue_library_anims(_LIB_NAME)
	if _body_animation_player.has_animation_library(&"lumax"):
		_enqueue_library_anims(&"lumax")

func _enqueue_library_anims(lib_name: StringName) -> void:
	var lib = _body_animation_player.get_animation_library(lib_name)
	if not lib:
		return
	for anim_name in lib.get_animation_list():
		var anim = lib.get_animation(anim_name)
		if anim is Animation:
			var id = anim.get_instance_id()
			if _sanitize_seen_ids.has(id):
				continue
			_sanitize_seen_ids[id] = true
			_sanitize_queue.append(anim)

## Queues a full pass (mixamo first, then other libs); work runs a few clips per frame in _process.
func force_resanitize_animations() -> void:
	if _sanitize_active:
		return
	if not is_instance_valid(_body_animation_player):
		_setup_references()
	if not is_instance_valid(_body_animation_player):
		return
	if not is_instance_valid(_skeleton):
		return
	_enqueue_all_animations_for_sanitize()
	_sanitize_track_rewrites = 0
	_sanitize_active = not _sanitize_queue.is_empty()

## Immediate sanitize for one clip (e.g. idle swap) — cheap; avoids re-queuing the whole library.
func resanitize_animation_resource(anim: Animation) -> void:
	if not anim or not is_instance_valid(anim):
		return
	if not is_instance_valid(_skeleton):
		_setup_references()
	if not is_instance_valid(_skeleton):
		return
	_sanitize_animation_resource_internal(anim)

func _remap_track_bone_name_for_vrm(path_str: String) -> String:
	if not is_instance_valid(_skeleton):
		return path_str
	var ci := path_str.rfind(":")
	if ci < 0:
		return path_str
	var node_sub := path_str.substr(0, ci)
	var bone_name := path_str.substr(ci + 1)
	if bone_name.contains("/"):
		return path_str
	if _skeleton.find_bone(bone_name) != -1:
		return path_str
	var cleaned := bone_name
	if cleaned.begins_with("mixamorig"):
		cleaned = cleaned.trim_prefix("mixamorig")
	if cleaned != bone_name and _skeleton.find_bone(cleaned) != -1:
		return node_sub + ":" + cleaned
	if _MIXAMO_BONE_TO_VRM.has(cleaned):
		var vrm_bone: String = String(_MIXAMO_BONE_TO_VRM[cleaned])
		if _skeleton.find_bone(vrm_bone) != -1:
			return node_sub + ":" + vrm_bone
	return path_str

func _sanitize_animation_resource_internal(anim: Animation) -> int:
	# Tracks must be relative to AnimationPlayer.root_node (often the Avatar). Using only the player's parent
	# (AvatarModel) produced paths like "GeneralSkeleton:..." while root is Avatar → wrong node → T-pose with "playing" logs.
	var ap := _body_animation_player
	if ap == null or not is_instance_valid(ap) or not is_instance_valid(_skeleton):
		return 0
	var path_root: Node = null
	if ap.root_node.is_empty():
		path_root = ap.get_parent()
	else:
		path_root = ap.get_node_or_null(ap.root_node)
	if path_root == null or not is_instance_valid(path_root):
		path_root = ap.get_parent()
	if path_root == null or not is_instance_valid(path_root):
		return 0
	var skel_path: String = String(path_root.get_path_to(_skeleton))
	if skel_path == ".":
		skel_path = ""
	var changed: int = 0
	for i in range(anim.get_track_count()):
		var old_path = String(anim.track_get_path(i))
		# Avoid matching arbitrary "root" substrings (can corrupt non-skeleton tracks and crash the mixer).
		if "Skeleton" in old_path or "Armature" in old_path:
			var colon_idx = old_path.find(":")
			if colon_idx != -1:
				var subnames = old_path.substr(colon_idx)
				if subnames.length() < 2:
					continue
				var final_path = (skel_path + subnames) if skel_path != "" else subnames.substr(1)
				if old_path != final_path:
					anim.track_set_path(i, NodePath(final_path))
					changed += 1
				var cur := String(anim.track_get_path(i))
				var remapped := _remap_track_bone_name_for_vrm(cur)
				if remapped != cur:
					anim.track_set_path(i, NodePath(remapped))
					changed += 1
	return changed

func _setup_animation_graph() -> void:
	if not is_instance_valid(_body_animation_player): return
	var root = AnimationNodeStateMachine.new()
	var lib = _body_animation_player.get_animation_library(_LIB_NAME)
	var states = ["idle", "wave", "happy", "sad", "walk", "walk_back", "walk_left", "walk_right", "run", "dance", "sit", "praying"]
	for s in states:
		if lib and lib.has_animation(s):
			var node = AnimationNodeAnimation.new()
			node.animation = String(_LIB_NAME) + "/" + s
			var state_name = s.capitalize().replace(" ", "")
			root.add_node(state_name, node)
	if root.has_node(&"Idle") and not root.has_transition(&"Start", &"Idle"):
		var start_idle := AnimationNodeStateMachineTransition.new()
		root.add_transition(&"Start", &"Idle", start_idle)
	
	if _animation_tree:
		_animation_tree.tree_root = root
		_animation_tree.anim_player = _animation_tree.get_path_to(_body_animation_player)
		_animation_tree.active = false 

func _find_face_mesh(node: Node) -> void:
	if not node: return
	if node is MeshInstance3D and node.mesh:
		if node.name.to_lower().contains("face") or node.find_blend_shape_by_name("Fcl_EYE_Close") != -1: _face_mesh = node; return
	for c in node.get_children(): _find_face_mesh(c); if _face_mesh: return

func _dump_entire_hierarchy(node: Node, indent: String):
	print("%s -> [%s] (%s)" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_dump_entire_hierarchy(child, indent + "  ")
