extends Node

## 🚀 LUMAX LOG MASTER
## Bypasses Godot's built-in logging to write directly to a file we can read via ADB.

signal log_added(msg: String, type: String)

var _log_file: FileAccess
var _log_path: String = "user://logs/lumax_diagnostic.log"
var _log_buffer: Array[String] = []
const MAX_BUFFER = 50

func _init() -> void:
	# Earliest autoload hook; if you see nothing after this on Quest, the crash is native (export/OpenXR) before GDScript runs.
	print("LUMAX: LogMaster _init (boot step 1)")

func _ready():
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("user://logs"):
		DirAccess.make_dir_recursive_absolute("user://logs")
		
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("--- LUMAX DIAGNOSTIC SESSION STARTED: " + Time.get_datetime_string_from_system() + " ---")
		_log_file.flush()
		_push_to_buffer("DIAGNOSTIC SESSION STARTED", "SYSTEM")
		print("LUMAX: Diagnostic Log Master active at " + _log_path)
		if OS.get_name() == "Android":
			print("LUMAX: Android user_data (adb: run-as com.lumax_current.core or check godot logcat): ", OS.get_user_data_dir())
	
func log_info(msg: String):
	if _log_file:
		var timestamp = Time.get_time_string_from_system()
		var entry = "[" + timestamp + "] [INFO] " + msg
		_log_file.store_line(entry)
		_log_file.flush()
		_push_to_buffer(msg, "INFO")
	print(msg)

func log_error(msg: String):
	if _log_file:
		var timestamp = Time.get_time_string_from_system()
		var entry = "[" + timestamp + "] [ERROR] " + msg
		_log_file.store_line(entry)
		_log_file.flush()
		_push_to_buffer(msg, "ERROR")
	printerr(msg)

func _push_to_buffer(msg: String, type: String):
	var timestamp = Time.get_time_string_from_system()
	var color = "white"
	match type:
		"ERROR": color = "red"
		"INFO": color = "cyan"
		"SYSTEM": color = "green"
		"WARNING": color = "yellow"
		
	var bbcode = "[color=%s][%s] [%s] %s[/color]" % [color, timestamp, type, msg]
	_log_buffer.push_back(bbcode)
	if _log_buffer.size() > MAX_BUFFER:
		_log_buffer.remove_at(0)
	log_added.emit(bbcode, type)

func get_logs() -> Array[String]:
	return _log_buffer

func _notification(what):
	if what != NOTIFICATION_WM_CLOSE_REQUEST and what != NOTIFICATION_EXIT_TREE:
		return
	# WM_CLOSE_REQUEST and EXIT_TREE can both run; after close() the FileAccess ref may still be
	# non-null while the native handle is gone — second store_line() hits "Parameter f is null".
	if _log_file == null:
		return
	var f: FileAccess = _log_file
	_log_file = null
	f.store_line("--- SESSION ENDED ---")
	f.flush()
	f.close()
