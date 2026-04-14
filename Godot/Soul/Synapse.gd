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
signal vitals_received(data: Dictionary)
## POST /soul_runtime_config (hot-reload GGUF + env flags).
signal soul_runtime_config_received(data: Dictionary)
## GET /soul_runtime_status (paths / flags from soul process).
signal soul_runtime_status_received(data: Dictionary)

## PC: Docker soul :8000 — default loopback. Quest (Wi‑Fi): overridden at runtime from lumax_network_config.json, user:// cache, or LAN scan (never uses 127.0.0.1 unless adb reverse).
@export var server_ip: String = "127.0.0.1"
## If true, _ready forces 127.0.0.1 (adb reverse). If false, keeps @export IP and failed heartbeats can re-sweep LAN.
@export var adb_reverse_first: bool = false
## Quest + Wi‑Fi: scan the headset's LAN for Soul :8000/health and remember it (user://).
@export var quest_lan_auto_discover: bool = true
## STT/Soul: print every HTTP step (large STT payloads spam the Godot console and trigger "output overflow").
@export var verbose_http_logs: bool = false
## When true, POST /compagent includes deep_think (richer vector retrieval + higher decode budget; slower than VR fast path).
@export var deep_think: bool = false
## Timeout for Soul HTTP POSTs (compagent/sensory/switch_model). Raise on slower local models.
@export_range(15.0, 300.0, 1.0) var soul_http_timeout_sec: float = 120.0
## Heartbeat cadence for /health probes. Higher value reduces churn during heavy inference.
@export_range(5.0, 60.0, 1.0) var heartbeat_interval_sec: float = 20.0
## Timeout for each /health probe. Raise on congested Wi‑Fi / busy local runtime.
@export_range(1.0, 15.0, 0.5) var health_probe_timeout_sec: float = 4.0
## Consecutive failed heartbeats before launching subnet sweep.
@export_range(1, 6, 1) var health_fail_threshold: int = 3
## Avoid false "UNREACHABLE" while a Soul POST is actively in-flight/backlogged.
@export var heartbeat_skip_during_soul_post: bool = true

## Filled from res://lumax_network_config.json (connect_quest.ps1 / Docker sentry): PC LAN for P2P / non-reverse fallbacks.
var pc_lan_ip: String = ""
var quest_ip: String = ""
## Default host for ENet / NAT peer (same as pc_lan_ip when config is written on PC).
var nat_peer_default: String = ""

var _alt_ips = ["127.0.0.1"]
var _current_ip_idx = 0
var _is_searching = false
var _sweep_active = false
var _health_fail_streak: int = 0
var _desktop_loopback_fallback_done: bool = false
## True after lumax_network_config.json was found and parsed (export must include this file for Quest LAN).
var network_config_loaded_ok: bool = false
const _USER_SOUL_HOST_PATH := "user://lumax_soul_host.txt"
var _lan_autodiscover_running: bool = false
var _ad_probe_done: bool = false
var _ad_probe_code: int = 0

# Rich connection context for error logs; helps diagnose stale LAN vs adb vs loopback quickly.
func _conn_debug_context() -> String:
	var is_android_runtime: bool = OS.get_name().to_lower() == "android"
	return "host=%s pc_lan=%s nat_peer=%s adb_reverse=%s android=%s netcfg=%s" % [
		server_ip,
		pc_lan_ip,
		nat_peer_default,
		str(adb_reverse_first),
		str(is_android_runtime),
		str(network_config_loaded_ok),
	]

# --- DEDICATED REQUEST NODES ---
var _soul_request: HTTPRequest
var _soul_dna_request: HTTPRequest
var _stt_request: HTTPRequest
## Serialized POSTs on `_soul_request` so compagent / sensory / switch_model do not ERR_BUSY-drop each other.
var _soul_post_queue: Array = []
const _SOUL_POST_QUEUE_MAX: int = 64

# --- COMMUNICATION HEARTBEAT ---
var _heartbeat_timer: Timer

## JSON may list host only (192.168.x.x) or accidentally include :port; Synapse always uses :8000 itself.
func _lan_host_strip_optional_port(s: String) -> String:
	var t := str(s).strip_edges()
	if t.is_empty():
		return t
	if t.is_valid_ip_address():
		return t
	var col := t.rfind(":")
	if col > 0:
		var hostpart := t.substr(0, col)
		if hostpart.is_valid_ip_address():
			return hostpart
	return t

func _load_network_config_from_json() -> void:
	const path := "res://lumax_network_config.json"
	network_config_loaded_ok = false
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(raw) != OK:
		return
	var data = j.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	network_config_loaded_ok = true
	if data.has("pc_lan_ip"):
		pc_lan_ip = _lan_host_strip_optional_port(str(data["pc_lan_ip"]))
	if data.has("quest_ip"):
		quest_ip = _lan_host_strip_optional_port(str(data["quest_ip"]))
	if data.has("nat_peer_default"):
		nat_peer_default = _lan_host_strip_optional_port(str(data["nat_peer_default"]))
	elif pc_lan_ip != "":
		nat_peer_default = pc_lan_ip
	if data.has("use_adb_reverse"):
		adb_reverse_first = bool(data["use_adb_reverse"])
	elif data.has("adb_reverse"):
		adb_reverse_first = bool(data["adb_reverse"])
	if adb_reverse_first:
		server_ip = "127.0.0.1"
		if pc_lan_ip != "" and pc_lan_ip.is_valid_ip_address() and not pc_lan_ip in _alt_ips:
			_alt_ips.append(pc_lan_ip)
		return
	if data.has("soul_host"):
		var sh := _lan_host_strip_optional_port(str(data["soul_host"]))
		if sh.is_valid_ip_address():
			server_ip = sh
	elif pc_lan_ip != "" and pc_lan_ip.is_valid_ip_address():
		server_ip = pc_lan_ip
	if pc_lan_ip != "" and pc_lan_ip.is_valid_ip_address() and not pc_lan_ip in _alt_ips:
		_alt_ips.append(pc_lan_ip)

func _persist_quest_soul_host(ip: String) -> void:
	if not ip.is_valid_ip_address() or ip == "127.0.0.1":
		return
	var f := FileAccess.open(_USER_SOUL_HOST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(ip.strip_edges() + "\n")

func _sync_multiverse_nat_peer(ip: String) -> void:
	if not ip.is_valid_ip_address() or ip == "127.0.0.1":
		return
	var n := get_tree().get_first_node_in_group("lumax_multiverse_network")
	if n and n.has_method("set_nat_peer_default"):
		n.set_nat_peer_default(ip)

func _load_persisted_quest_soul_host() -> void:
	if not FileAccess.file_exists(_USER_SOUL_HOST_PATH):
		return
	var f := FileAccess.open(_USER_SOUL_HOST_PATH, FileAccess.READ)
	if f == null:
		return
	var line := str(f.get_as_text().strip_edges().split("\n")[0]).strip_edges()
	if line.is_valid_ip_address() and line != "127.0.0.1":
		server_ip = line
		pc_lan_ip = line
		nat_peer_default = line
		print("LUMAX: Using Soul host from last successful LAN session (user://): ", server_ip)
		call_deferred("_sync_multiverse_nat_peer", line)

func _lan_subnet_prefixes_from_local_interfaces() -> PackedStringArray:
	var base_subnets: PackedStringArray = []
	var addresses: PackedStringArray = IP.get_local_addresses()
	for addr in addresses:
		if addr.is_empty() or addr == "127.0.0.1":
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			var parts: PackedStringArray = addr.split(".")
			if parts.size() >= 3:
				base_subnets.append(parts[0] + "." + parts[1] + "." + parts[2] + ".")
	var seen: Dictionary = {}
	var unique: PackedStringArray = PackedStringArray()
	for s in base_subnets:
		if not seen.has(s):
			seen[s] = true
			unique.append(s)
	return unique

func _lan_probe_host_suffixes() -> Array:
	var a: Array = []
	for i in range(100, 130):
		a.append(i)
	for i in range(2, 100):
		a.append(i)
	for i in range(130, 255):
		a.append(i)
	return a

func _on_autodisc_probe_done(_r: int, c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_ad_probe_code = c
	_ad_probe_done = true

func _scan_subnet_sequential_for_soul(sub: String) -> String:
	var suffixes: Array = _lan_probe_host_suffixes()
	for i in suffixes:
		var target := sub + str(i)
		var h := HTTPRequest.new()
		h.timeout = 0.45
		add_child(h)
		_ad_probe_done = false
		_ad_probe_code = 0
		h.request_completed.connect(_on_autodisc_probe_done, CONNECT_ONE_SHOT)
		var err := h.request("http://" + target + ":8000/health")
		if err != OK:
			h.queue_free()
			continue
		var elapsed := 0.0
		while not _ad_probe_done and elapsed < h.timeout + 0.35:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		h.queue_free()
		if _ad_probe_done and _ad_probe_code == 200:
			return target
	return ""

func _quest_lan_autodiscover_async() -> void:
	if _lan_autodiscover_running:
		return
	_lan_autodiscover_running = true
	var subnets := _lan_subnet_prefixes_from_local_interfaces()
	if subnets.is_empty():
		var local_ip := "192.168.1.1"
		if OS.has_environment("COMPUTERNAME"):
			var rh := IP.resolve_hostname(OS.get_environment("COMPUTERNAME"), IP.TYPE_IPV4)
			if rh.is_valid_ip_address():
				local_ip = rh
		var parts: PackedStringArray = local_ip.split(".")
		if parts.size() < 4:
			parts = PackedStringArray(["192", "168", "1", "1"])
		subnets = PackedStringArray([parts[0] + "." + parts[1] + "." + parts[2] + "."])
	print("LUMAX: LAN auto-discover: scanning for Soul (HTTP :8000/health) on your Wi‑Fi subnet…")
	for sub in subnets:
		var found: String = await _scan_subnet_sequential_for_soul(sub)
		if found != "":
			server_ip = found
			pc_lan_ip = found
			nat_peer_default = found
			_persist_quest_soul_host(found)
			_sync_multiverse_nat_peer(found)
			print("LUMAX: LAN auto-discover: found Soul at ", server_ip, " — saved for next launch (no USB needed).")
			_lan_autodiscover_running = false
			return
	print("LUMAX: LAN auto-discover: nothing found. Same Wi‑Fi as the PC? Docker publishing :8000? Windows firewall allows port 8000?")
	_lan_autodiscover_running = false

func _ready():
	add_to_group("lumax_synapse")
	_load_network_config_from_json()
	_load_persisted_quest_soul_host()
	var is_android_runtime: bool = OS.get_name().to_lower() == "android"
	if adb_reverse_first:
		server_ip = "127.0.0.1"
		print("LUMAX: Synapse manifested (adb reverse: using 127.0.0.1).")
		if is_android_runtime:
			print("LUMAX: Quest + ADB reverse mode: 127.0.0.1 is forwarded to the PC over USB — use USB or switch to LAN config.")
	else:
		print("LUMAX: Synapse manifested (Soul host: ", server_ip, "). LAN re-sweep if heartbeats fail.")
	if is_android_runtime and not adb_reverse_first:
		if server_ip == "127.0.0.1" and pc_lan_ip.is_valid_ip_address():
			server_ip = pc_lan_ip
			print("LUMAX: Quest LAN: soul_host was loopback — using pc_lan_ip ", server_ip, " (your PC on Wi‑Fi).")
		elif server_ip == "127.0.0.1" and network_config_loaded_ok:
			push_warning(
				"LUMAX: Quest is using 127.0.0.1 without ADB reverse — that is the headset, not your PC. "
				+ "Run connect_quest.ps1 (writes Godot/lumax_network_config.json with your PC IP e.g. 192.168.8.100), "
				+ "place the file in the Godot folder, export again, or set Synapse server_ip in the inspector."
			)
	if is_android_runtime and not network_config_loaded_ok:
		if quest_lan_auto_discover and not adb_reverse_first:
			print("LUMAX: No lumax_network_config.json in export — LAN auto-discover will try to find your PC.")
		else:
			push_warning(
				"LUMAX: lumax_network_config.json is missing or invalid. Enable quest_lan_auto_discover or add the file from connect_quest.ps1."
			)
	if nat_peer_default != "":
		print("LUMAX: NAT peer default (P2P/LAN): ", nat_peer_default)

	# Headset Wi‑Fi: never start HTTP to 127.0.0.1 (that is the Quest). Resolve LAN first so Soul/STT use the PC address.
	if is_android_runtime and not adb_reverse_first and server_ip == "127.0.0.1":
		if quest_lan_auto_discover:
			await get_tree().create_timer(0.05).timeout
			await _quest_lan_autodiscover_async()
		if server_ip == "127.0.0.1":
			push_warning(
				"LUMAX: Quest still has no PC LAN address for Soul/STT. Add res://lumax_network_config.json (connect_quest.ps1), "
				+ "or set Synapse server_ip to your PC IPv4 in the inspector, or use USB + adb reverse (connect_quest.ps1 --adb)."
			)

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = clampf(heartbeat_interval_sec, 5.0, 60.0)
	_heartbeat_timer.autostart = true
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_test_server_connectivity)
	
	_soul_request = HTTPRequest.new()
	_soul_request.name = "SoulRequest"
	# Keep bounded to avoid endless hang, but high enough for heavier local prompts/models.
	_soul_request.timeout = clampf(soul_http_timeout_sec, 15.0, 300.0)
	add_child(_soul_request)
	_soul_request.request_completed.connect(_on_soul_completed)

	_soul_dna_request = HTTPRequest.new()
	_soul_dna_request.name = "SoulDNARequest"
	add_child(_soul_dna_request)

	_stt_request = HTTPRequest.new()
	_stt_request.name = "STTRequest"
	_stt_request.timeout = 120.0
	add_child(_stt_request)
	_stt_request.request_completed.connect(_on_stt_completed)

	_test_server_connectivity()

func _test_server_connectivity():
	if _is_searching: return
	if (
		heartbeat_skip_during_soul_post
		and _soul_request != null
		and (
			_soul_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING
			or _soul_post_queue.size() > 0
		)
	):
		if verbose_http_logs:
			print("LUMAX DBG: Heartbeat skipped (Soul POST active/backlog).")
		return
	var is_android_runtime := OS.get_name().to_lower() == "android"
	# Quest/LAN guard: never keep testing 127.0.0.1 unless adb reverse mode is intentionally on.
	if is_android_runtime and not adb_reverse_first and server_ip == "127.0.0.1":
		if pc_lan_ip.is_valid_ip_address():
			server_ip = pc_lan_ip
			print("LUMAX: Quest LAN guard: replacing loopback with pc_lan_ip -> ", server_ip)
		elif quest_lan_auto_discover and not _lan_autodiscover_running:
			print("LUMAX: Quest LAN guard: loopback detected without adb reverse; starting LAN auto-discover. " + _conn_debug_context())
			call_deferred("_quest_lan_autodiscover_async")
			return
	_is_searching = true
	var url = "http://" + server_ip + ":8000/health"
	var test_req = HTTPRequest.new(); add_child(test_req)
	test_req.request_completed.connect(func(_r, c, _h, _b):
		_is_searching = false
		if c != 200:
			print("LUMAX: AI Bridge UNREACHABLE. " + _conn_debug_context())
			if (
				not is_android_runtime
				and not adb_reverse_first
				and not _desktop_loopback_fallback_done
				and server_ip != "127.0.0.1"
			):
				_desktop_loopback_fallback_done = true
				print("LUMAX: Desktop fallback: stale LAN host likely. Retrying Soul on 127.0.0.1:8000 before subnet sweep.")
				server_ip = "127.0.0.1"
				_health_fail_streak = 0
				test_req.queue_free()
				call_deferred("_test_server_connectivity")
				return
			_health_fail_streak += 1
			# After repeated failure, re-discover (fixes stale 192.168.x when WiFi/adb flaps; not only when stuck on loopback).
			if _health_fail_streak >= clampi(health_fail_threshold, 1, 6) and not _sweep_active:
				_health_fail_streak = 0
				_run_subnet_sweep()
		else:
			_desktop_loopback_fallback_done = false
			_health_fail_streak = 0
			print("LUMAX: AI Bridge ACTIVE. " + _conn_debug_context())
		test_req.queue_free()
	)
	test_req.timeout = clampf(health_probe_timeout_sec, 1.0, 15.0)
	test_req.request(url)

func _run_subnet_sweep():
	print("LUMAX: Initiating Subnet Sweep for Soul Core...")
	_sweep_active = true
	
	var base_subnets: PackedStringArray = _lan_subnet_prefixes_from_local_interfaces()
	# Fallbacks if we could not infer (e.g. desktop editor)
	if base_subnets.is_empty():
		var local_ip = "192.168.1.1"
		if OS.has_environment("COMPUTERNAME"):
			var h = IP.resolve_hostname(OS.get_environment("COMPUTERNAME"), IP.TYPE_IPV4)
			if h.is_valid_ip_address():
				local_ip = h
		var parts = local_ip.split(".")
		if parts.size() < 4:
			parts = ["192", "168", "1", "1"]
		base_subnets = PackedStringArray([parts[0] + "." + parts[1] + "." + parts[2] + ".", "192.168.1.", "192.168.0.", "10.0.0."])
	
	for sub in base_subnets:
		print("LUMAX DBG: Sweeping Subnet: " + sub + "*")
		for i in range(2, 255):
			if not _sweep_active: return # Stop if found
			_ping_target_ip(sub + str(i))
			# Stagger yielding to prevent completely locking Godot's network thread
			if i % 10 == 0: await get_tree().create_timer(0.01).timeout

func _ping_target_ip(target_ip: String):
	if not _sweep_active: return
	var req = HTTPRequest.new(); add_child(req)
	req.timeout = 1.0 # Aggressive timeout
	req.request_completed.connect(func(_r, c, _h, _b):
		if c == 200 and _sweep_active:
			_sweep_active = false
			print("LUMAX: SOUL CORE LOCATED AT -> " + target_ip)
			server_ip = target_ip
			_persist_quest_soul_host(target_ip)
		req.queue_free()
	)
	req.request("http://" + target_ip + ":8000/health")

func rotate_ip_manual():
	# Allow forcing a new sweep
	server_ip = "127.0.0.1"
	_sweep_active = false
	_run_subnet_sweep()
	return server_ip


func _soul_enqueue_post(url: String, headers: PackedStringArray, body: String, log_line: String = "") -> void:
	while _soul_post_queue.size() >= _SOUL_POST_QUEUE_MAX:
		_soul_post_queue.pop_front()
		print("LUMAX WARN: Soul POST queue full; dropped oldest.")
	_soul_post_queue.append({"url": url, "headers": headers, "body": body, "log": log_line})
	if log_line != "":
		print(log_line)
	_soul_flush_post_queue()


func _soul_flush_post_queue() -> void:
	if _soul_post_queue.is_empty():
		return
	if _soul_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var item: Dictionary = _soul_post_queue.pop_front() as Dictionary
	var err: int = _soul_request.request(item["url"], item["headers"], HTTPClient.METHOD_POST, item["body"])
	if err != OK:
		print("LUMAX ERR: Soul request failed to start: ", err)
		request_failed.emit("Soul request failed to start: %s" % str(err))
		call_deferred("_soul_flush_post_queue")
		return


func send_chat_message(text: String, channel: String = "text", image_base64: String = "", room_context: Variant = null, mcp_context: String = "", news_context: String = "", primary_context_mode: String = "", context_reservoirs: Dictionary = {}, context_ability_map: String = "", lore_context: String = "", cloud_routing: String = ""):
	var url = "http://" + server_ip + ":8000/compagent"
	var headers = ["Content-Type: application/json"]
	var payload = {"input": text, "channel": channel}
	if image_base64 != "":
		payload["image_base64"] = image_base64
	if room_context is Dictionary and not room_context.is_empty():
		payload["room_context"] = room_context
	var mcp_s := mcp_context.strip_edges()
	if mcp_s.length() > 0:
		payload["mcp_context"] = mcp_s
	var news_s := news_context.strip_edges()
	if news_s.length() > 0:
		payload["news_context"] = news_s
	var pcm := primary_context_mode.strip_edges()
	if pcm.length() > 0:
		payload["primary_context_mode"] = pcm
	if context_reservoirs is Dictionary and not context_reservoirs.is_empty():
		payload["context_reservoirs"] = context_reservoirs
	var cam := context_ability_map.strip_edges()
	if cam.length() > 0:
		payload["context_ability_map"] = cam
	var lore_s := lore_context.strip_edges()
	if lore_s.length() > 0:
		payload["lore_context"] = lore_s
	var cr := cloud_routing.strip_edges()
	if cr.length() > 0:
		payload["cloud_routing"] = cr
	if deep_think:
		payload["deep_think"] = true
	var log_s := "LUMAX: Queuing Soul POST %s (chars=%d, channel=%s, backlog=%d)" % [url, text.length(), channel, _soul_post_queue.size()]
	if log_s.length() > 200:
		log_s = log_s.substr(0, 197) + "..."
	_soul_enqueue_post(url, headers, JSON.stringify(payload), log_s)

func send_voice_to_stt(data: PackedByteArray):
	if verbose_http_logs:
		print("LUMAX: send_voice_to_stt() called. Data size: ", data.size())
	if data.size() < 64:
		print("LUMAX ERR: WAV capture too small — mic may be muted, permission denied, or record length zero.")
		request_failed.emit("STT: empty or invalid capture")
		return
	if _stt_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		print("LUMAX ERR: STT request already in flight — wait for it to finish before talking again.")
		request_failed.emit("STT busy")
		return
	var b64 = Marshalls.raw_to_base64(data)
	var url = "http://" + server_ip + ":8001/stt"
	var payload = {"audio_base64": b64}
	if verbose_http_logs:
		print("LUMAX: Sending STT request to: ", url)
	var err = _stt_request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		print("LUMAX ERR: Failed to initiate STT request. Error code: ", err)
		request_failed.emit("STT request start failed: %s" % str(err))

func _on_stt_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_str := body.get_string_from_utf8()
	if verbose_http_logs:
		print("LUMAX: STT Request Completed. Result: ", result, " Code: ", response_code, " body.len=", body_str.length())
	if result != HTTPRequest.RESULT_SUCCESS:
		var rlabel := _http_result_label(result)
		var hint := ""
		if result == HTTPRequest.RESULT_CANT_CONNECT:
			hint = " — Quest needs PC LAN IP (lumax_network_config.json) or USB adb reverse; ensure Docker publishes :8001."
		request_failed.emit("STT %s (http_code=%s)%s | %s" % [rlabel, str(response_code), hint, _conn_debug_context()])
		return
	if response_code != 200:
		request_failed.emit("STT HTTP %s: %s" % [str(response_code), body_str.substr(0, 120)])
		return
	var json = JSON.parse_string(body_str)
	if json == null:
		print("LUMAX ERR: STT response not JSON: ", body_str.substr(0, 200))
		request_failed.emit("STT bad JSON response")
		return
	if not json is Dictionary:
		request_failed.emit("STT unexpected JSON type")
		return
	if not json.has("text"):
		print("LUMAX ERR: STT JSON missing 'text' key: ", json)
		request_failed.emit("STT response missing text field")
		return
	var t: String = str(json["text"])
	if verbose_http_logs:
		print("LUMAX: STT raw text: ", t)
	stt_received.emit(t)

func _http_result_label(r: int) -> String:
	if r == HTTPRequest.RESULT_SUCCESS:
		return "OK"
	if r == HTTPRequest.RESULT_TIMEOUT:
		return "TIMEOUT"
	if r == HTTPRequest.RESULT_CANT_CONNECT:
		return "CANT_CONNECT"
	if r == HTTPRequest.RESULT_CANT_RESOLVE:
		return "CANT_RESOLVE"
	if r == HTTPRequest.RESULT_CONNECTION_ERROR:
		return "CONNECTION_ERROR"
	if r == HTTPRequest.RESULT_NO_RESPONSE:
		return "NO_RESPONSE"
	return "result_%s" % r

func _on_soul_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == OK and response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data:
			request_failed.emit("Failed to parse Soul response.")
		else:
			if data.has("response"):
				var resp_obj = data["response"]
				var thought_obj = data.get("thought", "")
				var img_b: String = str(data.get("image_b64", ""))
				if resp_obj is String:
					var pack: Dictionary = {"text": resp_obj, "thought": thought_obj}
					if img_b.length() > 32:
						pack["image_b64"] = img_b
					var emo_s: String = str(data.get("emotion", ""))
					if emo_s.length() > 0:
						pack["emotion"] = emo_s
					var sa: Variant = data.get("safety_alerts", [])
					if sa is Array and sa.size() > 0:
						pack["safety_alerts"] = sa
					response_received.emit(pack, data.get("mode", "LOCAL"))
				else:
					resp_obj["thought"] = thought_obj
					if img_b.length() > 32:
						resp_obj["image_b64"] = img_b
					var sa2: Variant = data.get("safety_alerts", [])
					if sa2 is Array and sa2.size() > 0:
						resp_obj["safety_alerts"] = sa2
					response_received.emit(resp_obj, data.get("mode", "LOCAL"))
			if data.has("audio") and data["audio"] != "":
				var audio_data = Marshalls.base64_to_raw(data["audio"])
				var sr = data.get("sample_rate", 22050.0)
				audio_received.emit(audio_data, sr)
	else:
		var rlabel := _http_result_label(result)
		var hint := ""
		if result == HTTPRequest.RESULT_TIMEOUT:
			hint = " Soul took longer than HTTPRequest.timeout=%ss, or the link stalled (slow LLM, Wi‑Fi/Virtual Desktop)." % str(_soul_request.timeout)
		elif result == HTTPRequest.RESULT_CANT_CONNECT:
			hint = " Quest: set PC LAN in lumax_network_config.json or use adb reverse; PC: docker compose up + firewall :8000."
		elif result != HTTPRequest.RESULT_SUCCESS:
			hint = " Transport/abort (e.g. quit VR mid-request)."
		if verbose_http_logs:
			print("LUMAX ERR: Soul HTTP finished but not OK: %s (%s) response_code=%s body.len=%s.%s" % [result, rlabel, response_code, body.size(), hint])
		request_failed.emit("Soul %s (http_code=%s)%s | %s" % [rlabel, response_code, hint, _conn_debug_context()])
	_soul_flush_post_queue()


func inject_sensory_event(payload: String):
	var url = "http://" + server_ip + ":8000/compagent"
	var headers = ["Content-Type: application/json"]
	var data = {"input": payload, "channel": "sensory"}
	_soul_enqueue_post(url, headers, JSON.stringify(data), "")

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
	_soul_enqueue_post(url, headers, JSON.stringify(payload), "LUMAX: Queuing model switch: " + model_name)


func apply_soul_runtime_config(payload: Dictionary) -> void:
	var url = "http://" + server_ip + ":8000/soul_runtime_config"
	var headers = ["Content-Type: application/json"]
	var body := JSON.stringify(payload)
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 120.0
	req.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, resp_body: PackedByteArray) -> void:
		var txt := resp_body.get_string_from_utf8()
		if code == 200:
			var data = JSON.parse_string(txt)
			soul_runtime_config_received.emit(data if data is Dictionary else {"ok": false, "raw": txt})
		else:
			soul_runtime_config_received.emit({"ok": false, "http_code": code, "body": txt})
		req.queue_free()
	)
	var err := req.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		soul_runtime_config_received.emit({"ok": false, "error": "request_start_failed", "code": err})
		req.queue_free()


func fetch_soul_runtime_status() -> void:
	var url = "http://" + server_ip + ":8000/soul_runtime_status"
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 15.0
	req.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		if code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			soul_runtime_status_received.emit(data if data is Dictionary else {})
		else:
			soul_runtime_status_received.emit({"error": "http", "http_code": code})
		req.queue_free()
	)
	var err := req.request(url)
	if err != OK:
		soul_runtime_status_received.emit({"error": "request_start_failed", "code": err})
		req.queue_free()


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
