extends Node
class_name LumaxSynapse

## 🧠 LUMAX SYNAPSE (v1.64 - STABILIZED)
## Fixed parse errors: Completely rebuilt header with no properties.

signal response_received(data: Dictionary, mode: String)
signal stt_received(text: String)
signal audio_received(buffer: PackedByteArray, sample_rate: float)
signal request_failed(error_msg: String)
signal files_received(files: Array)
signal memory_received(archive: Array)

@export var server_ip: String = "127.0.0.1"

var _alt_ips = ["127.0.0.1", "192.168.1.100"]
var _current_ip_idx = 0
var _is_searching = false

# --- DEDICATED REQUEST NODES ---
var _soul_request: HTTPRequest
var _soul_dna_request: HTTPRequest
var _stt_request: HTTPRequest

# --- COMMUNICATION HEARTBEAT ---
var _heartbeat_timer: Timer

func _ready():
	# Default to local for ADB bridge support
	server_ip = "127.0.0.1"
	print("LUMAX: Synapse manifested (ADB Reverse Mode).")
	
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 15.0 # Check every 15s
	_heartbeat_timer.autostart = true
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_test_server_connectivity)
	
	_soul_request = HTTPRequest.new()
	_soul_request.name = "SoulRequest"
	add_child(_soul_request)
	_soul_request.request_completed.connect(_on_soul_completed)

	_soul_dna_request = HTTPRequest.new()
	_soul_dna_request.name = "SoulDNARequest"
	add_child(_soul_dna_request)

	_stt_request = HTTPRequest.new()
	_stt_request.name = "STTRequest"
	add_child(_stt_request)
	_stt_request.request_completed.connect(_on_stt_completed)

	_test_server_connectivity()

func _test_server_connectivity():
	if _is_searching: return
	_is_searching = true
	var url = "http://" + server_ip + ":8000/health"
	var test_req = HTTPRequest.new(); add_child(test_req)
	test_req.request_completed.connect(func(_r, c, _h, _b): 
		_is_searching = false
		if c != 200: 
			print("LUMAX: AI Bridge (127.0.0.1:8000) UNREACHABLE. Check ADB reverse.")
		else:
			print("LUMAX: AI Bridge ACTIVE at " + server_ip)
		test_req.queue_free()
	)
	test_req.timeout = 2.0
	test_req.request(url)

func rotate_ip_manual():
	# No longer rotating to wrong subnets. We stick to the bridge!
	server_ip = "127.0.0.1"
	_test_server_connectivity()
	return server_ip

func send_chat_message(text: String, channel: String = "text", image_base64: String = ""):
	var url = "http://" + server_ip + ":8000/compagent"
	var headers = ["Content-Type: application/json"]
	var payload = {"input": text, "channel": channel}
	if image_base64 != "":
		payload["image_base64"] = image_base64
	# Guard against ERR_BUSY — retry after short delay if request in flight
	if _soul_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		await get_tree().create_timer(0.5).timeout
	_soul_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func send_voice_to_stt(data: PackedByteArray):
	print("LUMAX: send_voice_to_stt() called. Data size: ", data.size())
	var b64 = Marshalls.raw_to_base64(data)
	var url = "http://" + server_ip + ":8001/stt"
	var payload = {"audio_base64": b64}
	print("LUMAX: Sending STT request to: ", url)
	var err = _stt_request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		print("LUMAX ERR: Failed to initiate STT request. Error code: ", err)

func _on_stt_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("LUMAX: STT Request Completed. Result: ", result, " Code: ", response_code)
	if result == OK and response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("text"): stt_received.emit(json["text"])
	else:
		request_failed.emit("STT Service Unreachable (Code: " + str(response_code) + ")")

func _on_soul_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == OK and response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data: 
			request_failed.emit("Failed to parse Soul response.")
			return
		
		if data.has("response"):
			var resp_obj = data["response"]
			var thought_obj = data.get("thought", "")
			if resp_obj is String:
				response_received.emit({"text": resp_obj, "thought": thought_obj}, data.get("mode", "LOCAL"))
			else:
				resp_obj["thought"] = thought_obj
				response_received.emit(resp_obj, data.get("mode", "LOCAL"))
		
		if data.has("audio") and data["audio"] != "":
			var audio_data = Marshalls.base64_to_raw(data["audio"])
			var sr = data.get("sample_rate", 22050.0)
			audio_received.emit(audio_data, sr)
	else:
		request_failed.emit("Soul Core Offline (Code: " + str(response_code) + ")")

func inject_sensory_event(payload: String):
	var url = "http://" + server_ip + ":8000/compagent"
	var headers = ["Content-Type: application/json"]
	var data = {"input": payload, "channel": "sensory"}
	_soul_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

func update_soul_dna(dna: Dictionary):
	var url = "http://" + server_ip + ":8000/update_soul"
	var headers = ["Content-Type: application/json"]
	# Use dedicated DNA request node to avoid cancelling chat responses
	if _soul_dna_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_soul_dna_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(dna))

func switch_model(model_name: String):
	var url = "http://" + server_ip + ":8000/switch_model"
	var headers = ["Content-Type: application/json"]
	var payload = {"model": model_name}
	_soul_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	print("LUMAX: Model Switch Request Sent for: " + model_name)

signal vitals_received(data: Dictionary)
func get_vitals():
	var url = "http://" + server_ip + ":8000/vitals"
	var req = HTTPRequest.new(); add_child(req)
	req.request_completed.connect(func(_res, code, _h, body):
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			vitals_received.emit(data if data else {})
		req.queue_free()
	)
	req.request(url)

func fetch_personality_presets():
	var url = "http://" + server_ip + ":8000/personality_presets"
	var req = HTTPRequest.new(); add_child(req)
	req.request_completed.connect(func(r, c, h, b):
		if c == 200:
			var data = JSON.parse_string(b.get_string_from_utf8())
			response_received.emit({"type": "presets", "data": data}, "LOCAL")
		req.queue_free()
	)
	req.request(url)

func list_files():
	var url = "http://" + server_ip + ":8000/list_files"
	var req = HTTPRequest.new(); add_child(req)
	req.request_completed.connect(func(_r, code, _h, body):
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data and data.has("files"): files_received.emit(data.files)
		req.queue_free()
	)
	req.request(url)

func get_memory_archive():
	var url = "http://" + server_ip + ":8000/memory_archive"
	var req = HTTPRequest.new(); add_child(req)
	req.request_completed.connect(func(_r, code, _h, body):
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data and data.has("archive"): memory_received.emit(data.archive)
		req.queue_free()
	)
	req.request(url)
