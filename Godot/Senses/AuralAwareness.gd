extends Node

signal transcription_received(text: String)
signal recording_state_changed(is_recording: bool)

@export var synapse: Node = null : set = set_synapse

var _mic_player: AudioStreamPlayer
var _audio_effect_record: AudioEffectRecord
var _is_recording: bool = false
var _record_bus_idx: int = -1

func set_synapse(val: Node) -> void:
	synapse = val
	if synapse and synapse.has_signal("stt_received"):
		if not synapse.stt_received.is_connected(_on_stt_received):
			synapse.stt_received.connect(_on_stt_received)
			print("LUMAX: AuralAwareness connected to Synapse STT signal.")

func _ready() -> void:
	print("LUMAX: AuralAwareness initializing...")
	if OS.get_name() == "Android":
		OS.request_permissions()
	_ensure_audio_setup()

func _ensure_audio_setup():
	var bus_index = AudioServer.get_bus_index("Record")
	if bus_index == -1:
		print("LUMAX: 'Record' bus NOT FOUND. Creating dynamically...")
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "Record")
		AudioServer.set_bus_send(bus_index, "Master")
		AudioServer.set_bus_mute(bus_index, false)
	
	# Ensure Record effect exists
	var effect_found = false
	for i in range(AudioServer.get_bus_effect_count(bus_index)):
		if AudioServer.get_bus_effect(bus_index, i) is AudioEffectRecord:
			effect_found = true
			break
	
	if not effect_found:
		print("LUMAX: Adding AudioEffectRecord to 'Record' bus.")
		AudioServer.add_bus_effect(bus_index, AudioEffectRecord.new())
	
	# Link to the capture device (microphone)
	AudioServer.set_bus_layout(AudioServer.generate_bus_layout())
	print("LUMAX: Audio Bus Setup COMPLETE.")
	
	if OS.get_name() == "Android":
		OS.request_permission("RECORD_AUDIO")
		print("LUMAX: Requesting Android Permission (RECORD_AUDIO)...")
	
	_list_audio_devices()
	_setup_audio_bus()
	# Call setter logic in case it was set via editor/before ready
	set_synapse(synapse)

func _list_audio_devices() -> void:
	var devices = AudioServer.get_input_device_list()
	print("LUMAX: Audio Input Devices Found: ", devices.size())
	for d in devices:
		print("  - Device: ", d)
	
	_select_best_mic(devices)

func _select_best_mic(devices: Array) -> void:
	var preferred = ["Quest", "Android", "Oculus"]
	var fallback = "MIC-HD"
	
	var chosen = ""
	for p in preferred:
		for d in devices:
			if p.to_lower() in d.to_lower():
				chosen = d
				break
		if chosen != "": break
	
	if chosen == "":
		for d in devices:
			if fallback.to_lower() in d.to_lower():
				chosen = d
				break
				
	if chosen != "":
		AudioServer.input_device = chosen
		print("LUMAX: Selected Microphone -> ", chosen)
	else:
		print("LUMAX: Using default system microphone.")


func _setup_audio_bus() -> void:
	# 1. Create a dedicated Record bus
	_record_bus_idx = AudioServer.get_bus_index("Record")
	if _record_bus_idx == -1:
		_record_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_record_bus_idx)
		AudioServer.set_bus_name(_record_bus_idx, "Record")
	
	# MUTE IT so we don't hear ourselves
	AudioServer.set_bus_mute(_record_bus_idx, true)
	
	# 2. Add the Record effect
	_audio_effect_record = AudioEffectRecord.new()
	# Check if effect already exists to prevent duplicates on soft reloads
	var has_effect = false
	for i in range(AudioServer.get_bus_effect_count(_record_bus_idx)):
		if AudioServer.get_bus_effect(_record_bus_idx, i) is AudioEffectRecord:
			_audio_effect_record = AudioServer.get_bus_effect(_record_bus_idx, i)
			has_effect = true
			break
	
	if not has_effect:
		AudioServer.add_bus_effect(_record_bus_idx, _audio_effect_record)
	
	# 3. Create the Microphone Stream Player
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Record"
	add_child(_mic_player)
	_mic_player.play() # Must be playing to capture data

func start_recording() -> void:
	if _is_recording: return
	_is_recording = true
	LogMaster.log_info("AURAL: Mic Recording STARTED")
	_audio_effect_record.set_recording_active(true)
	recording_state_changed.emit(true)

func _ensure_synapse():
	if is_instance_valid(synapse): return true
	
	LogMaster.log_info("AURAL: Searching for Synapse in tree...")
	# 1. Check siblings in Nexus
	var p = get_parent()
	if p:
		var s = p.get_node_or_null("Soul")
		if not s: s = p.get_node_or_null("Synapse")
		if s: 
			set_synapse(s)
			LogMaster.log_info("AURAL: Found Synapse sibling!")
			return true
			
	# 2. Global search
	var root = get_tree().root
	var nodes = root.find_children("*", "LumaxSynapse", true, false)
	if nodes.size() > 0:
		set_synapse(nodes[0])
		LogMaster.log_info("AURAL: Found Synapse via global search!")
		return true
		
	return false

func stop_recording() -> void:
	if not _is_recording: return
	_is_recording = false
	var recording = _audio_effect_record.get_recording()
	_audio_effect_record.set_recording_active(false)
	LogMaster.log_info("AURAL: Mic Recording STOPPED. Analyzing buffer...")

	if not _ensure_synapse():
		LogMaster.log_error("AURAL ERR: Synapse node STILL not found after search!")
	elif not recording:
		LogMaster.log_error("AURAL ERR: No recording data captured from AudioEffectRecord.")
	else:
		var wav = recording.save_to_wav("user://capture.wav")
		if wav == OK:
			var f = FileAccess.open("user://capture.wav", FileAccess.READ)
			if f:
				var data = f.get_buffer(f.get_length())
				LogMaster.log_info("AURAL: Captured WAV size: " + str(data.size()) + " bytes")
				if data.size() > 100: # WAV header is 44 bytes
					if synapse.has_method("send_voice_to_stt"):
						synapse.send_voice_to_stt(data)
						LogMaster.log_info("AURAL: Data dispatched to Synapse STT.")
					else:
						LogMaster.log_error("AURAL ERR: Synapse missing send_voice_to_stt method!")
				else:
					LogMaster.log_error("AURAL ERR: Captured audio is too small (likely empty).")
			else:
				LogMaster.log_error("AURAL ERR: Failed to open user://capture.wav for reading.")
		else:
			LogMaster.log_error("AURAL ERR: Failed to save WAV capture. Error code: " + str(wav))

	recording_state_changed.emit(false)

func _on_stt_received(text: String) -> void:
	print("LUMAX: transcription received: ", text)
	transcription_received.emit(text)
