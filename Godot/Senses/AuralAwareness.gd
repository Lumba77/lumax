extends Node

signal transcription_received(text: String)
signal recording_state_changed(is_recording: bool)

@export var synapse: Node = null : set = set_synapse

const _MIN_STT_WAV_BYTES: int = 20000

var _mic_player: AudioStreamPlayer
var _audio_effect_record: AudioEffectRecord
var _is_recording: bool = false
var _record_bus_idx: int = -1
var _synapse_rebind_timer: float = 0.0
var _instance_enabled: bool = true

func set_synapse(val: Node) -> void:
	synapse = val
	if synapse and synapse.has_signal("stt_received"):
		if not synapse.stt_received.is_connected(_on_stt_received):
			synapse.stt_received.connect(_on_stt_received)
			print("LUMAX: AuralAwareness connected to Synapse STT signal.")

func _ready() -> void:
	var singleton = get_node_or_null("/root/AuralAwareness")
	if singleton != null and singleton != self:
		_instance_enabled = false
		set_process(false)
		print("LUMAX: AuralAwareness secondary instance disabled at %s" % String(get_path()))
		return
	print("LUMAX: AuralAwareness initializing...")
	_setup_audio_bus()
	# Call setter logic in case it was set via editor/before ready
	set_synapse(synapse)
	if synapse == null:
		_try_autobind_synapse()

func _process(_delta: float) -> void:
	if not _instance_enabled:
		return
	# Fail-safe: microphone playback must never stay active outside PTT recording.
	if not _is_recording and _mic_player and _mic_player.playing:
		_mic_player.stop()
	# Autoload instance may start before LumaxCore/Soul exists; retry bind lazily.
	if synapse == null:
		_synapse_rebind_timer -= _delta
		if _synapse_rebind_timer <= 0.0:
			_synapse_rebind_timer = 1.0
			_try_autobind_synapse()

func _try_autobind_synapse() -> void:
	var s: Node = get_node_or_null("/root/LumaxCore/Soul")
	if s == null and get_tree():
		s = get_tree().root.find_child("Soul", true, false)
	if s == null and get_tree():
		s = get_tree().root.find_child("Synapse", true, false)
	if s != null:
		set_synapse(s)
		print("LUMAX: AuralAwareness auto-bound synapse: %s" % String(s.get_path()))

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
	_audio_effect_record.set_recording_active(false)
	
	# 3. Create the Microphone Stream Player
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = "Record"
		add_child(_mic_player)

func start_recording() -> void:
	if not _instance_enabled:
		return
	if _is_recording: return
	_is_recording = true
	print("LUMAX: MIC RECORDING STARTED")
	if _mic_player and not _mic_player.playing:
		_mic_player.play()
	_audio_effect_record.set_recording_active(true)
	recording_state_changed.emit(true)

func stop_recording() -> void:
	if not _instance_enabled:
		return
	if not _is_recording: return
	_is_recording = false
	_audio_effect_record.set_recording_active(false)
	if _mic_player and _mic_player.playing:
		_mic_player.stop()
	print("LUMAX: MIC RECORDING STOPPED. Processing...")

	var recording = _audio_effect_record.get_recording()
	if recording == null:
		print("LUMAX ERR: No recording buffer — hold the mic button longer or check Quest mic permission.")
	elif synapse == null:
		_try_autobind_synapse()
		if synapse != null:
			# Continue to send below in this same stop cycle.
			pass
		else:
			print("LUMAX ERR: AuralAwareness.synapse not set — STT cannot run.")
			recording_state_changed.emit(false)
			return
	if recording and synapse:
		var wav = recording.save_to_wav("user://capture.wav")
		if wav == OK:
			var f = FileAccess.open("user://capture.wav", FileAccess.READ)
			if f:
				var data = f.get_buffer(f.get_length())
				f.close()
				if data.size() < _MIN_STT_WAV_BYTES:
					print("LUMAX ERR: Captured WAV too small (%d bytes) — silence or mic not routed to Record bus." % data.size())
				elif synapse.has_method("send_voice_to_stt"):
					synapse.call("send_voice_to_stt", data)
				else:
					print("LUMAX ERR: Synapse missing send_voice_to_stt method!")
			else:
				print("LUMAX ERR: Could not open user://capture.wav")
		else:
			print("LUMAX ERR: Failed to save WAV capture (err=%s)." % str(wav))

	recording_state_changed.emit(false)

func _exit_tree() -> void:
	if not _instance_enabled:
		return
	if _audio_effect_record:
		_audio_effect_record.set_recording_active(false)
	if _mic_player and _mic_player.playing:
		_mic_player.stop()

func _on_stt_received(text: String) -> void:
	print("LUMAX: transcription received: ", text)
	transcription_received.emit(text)
