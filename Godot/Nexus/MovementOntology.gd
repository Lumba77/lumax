extends Node

## 🎭 LUMAX MOVEMENT ONTOLOGY
## Handles the mimicry, measurement, and mapping of "Idealised" movements.
## Allows Jen to "learn" from the user's kinematic data.

signal pose_captured(pose_data: Dictionary)
signal mimic_started
signal mimic_stopped

var _is_recording := false
var _is_playing := false
var _playback_index := 0
var _ideal_pose_library := {}
var _current_session_data := []

# Reference Nodes
var _left_tracker: Node3D = null
var _right_tracker: Node3D = null
var _head_tracker: Node3D = null
var _target_body: Node3D = null

func setup(left: Node3D, right: Node3D, head: Node3D, body: Node3D):
	_left_tracker = left
	_right_tracker = right
	_head_tracker = head
	_target_body = body
	print("LUMAX: Movement Ontology system online.")

func start_mimic_session():
	_is_recording = true
	_current_session_data.clear()
	mimic_started.emit()
	print("LUMAX: Mimic Session started. Tracking idealised movement.")

func stop_mimic_session():
	_is_recording = false
	mimic_stopped.emit()
	_process_session_data()
	print("LUMAX: Mimic Session stopped. Data captured: ", _current_session_data.size(), " frames.")

func _process(delta):
	if _is_recording:
		_capture_frame()
	elif _is_playing:
		_process_playback()

func start_playback():
	if _current_session_data.is_empty(): return
	_is_playing = true
	_playback_index = 0
	print("LUMAX: Starting playback of idealised movement.")

func _process_playback():
	if _playback_index >= _current_session_data.size():
		_is_playing = false
		print("LUMAX: Playback finished.")
		return
	
	var frame = _current_session_data[_playback_index]
	if _target_body:
		# Map the head tracker to Jen's head/body position
		# This "animates" her based on the user's recorded movements
		_target_body.position = frame.hp
		_target_body.basis = frame.hr
		# Future: Hand mapping via IK
	
	_playback_index += 1

func _capture_frame():
	if not _left_tracker or not _right_tracker or not _head_tracker: return
	
	var frame = {
		"t": Time.get_ticks_msec(),
		"lp": _left_tracker.position,
		"lr": _left_tracker.basis,
		"rp": _right_tracker.position,
		"rr": _right_tracker.basis,
		"hp": _head_tracker.position,
		"hr": _head_tracker.basis
	}
	_current_session_data.append(frame)

func _process_session_data():
	if _current_session_data.is_empty(): return
	
	# Measure total distance/velocity to identify "Act" type
	var total_dist = 0.0
	for i in range(1, _current_session_data.size()):
		total_dist += _current_session_data[i].lp.distance_to(_current_session_data[i-1].lp)
	
	print("LUMAX MEASUREMENT: Total Left hand path length: ", total_dist)
	# Map to an "Idealised" movement if it matches a signature
	# Future: TensorRT inference here for movement classification

func map_to_rig(session_data: Array, rig: Skeleton3D):
	# Animate movements with existing rig
	# This would involve mapping the captured trackers to IK targets
	print("LUMAX: Mapping session data to rig targets.")
	# Implementation would use SkeletonIK3D or custom FABRIK
