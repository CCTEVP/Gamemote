class_name GmBleTransport
extends GmTransport
## BLE transport using the GamemoteBle GDExtension (CoreBluetooth on iOS/macOS).
## The extension is generic; the Gamemote GATT profile is handled here.

const STATE_NAMES := ["unknown", "resetting", "unsupported", "unauthorized", "powered off",
		"powered on", "missing NSBluetoothAlwaysUsageDescription in Info.plist"]
const STATE_POWERED_ON := 5

var _ble  # GamemoteBle instance (untyped: the class only exists when the extension loaded)
var _state := 0
var _device_id := ""
var _stage := ""  # "", "connecting", "discovering", "subscribing", "reading", "ready"


## True when the native extension is loaded and has a real backend on this platform.
static func is_available() -> bool:
	if not ClassDB.class_exists("GamemoteBle"):
		return false
	var probe = ClassDB.instantiate("GamemoteBle")
	return probe != null and probe.is_supported()


func get_kind() -> String:
	return "ble"


func is_adapter_ready() -> bool:
	return _state == STATE_POWERED_ON


func start() -> void:
	_ble = ClassDB.instantiate("GamemoteBle")
	_ble.connect("adapter_state_changed", _on_adapter_state)
	_ble.connect("peripheral_found", func(id, dev_name, rssi): device_found.emit(id, dev_name, rssi))
	_ble.connect("connected", _on_connected)
	_ble.connect("connect_failed", _on_connect_failed)
	_ble.connect("disconnected", _on_disconnected)
	_ble.connect("services_discovered", _on_services)
	_ble.connect("notify_state_changed", _on_notify_state)
	_ble.connect("value_read", _on_value_read)
	_ble.connect("notified", _on_notified)
	_ble.connect("write_completed", _on_write_completed)
	_ble.connect("error", func(msg): log_message.emit("[ble] " + msg))
	log_message.emit("BLE backend: %s" % _ble.get_backend_name())
	_ble.initialize()


func poll(_delta: float) -> void:
	if _ble:
		_ble.poll()


func start_scan() -> void:
	_ble.start_scan(PackedStringArray([GmProtocol.SERVICE_UUID]))


func stop_scan() -> void:
	_ble.stop_scan()


func connect_to(id: String) -> void:
	_device_id = id
	_stage = "connecting"
	_ble.connect_peripheral(id)


func disconnect_from() -> void:
	_stage = ""
	_ble.disconnect_peripheral()


func send(frame: PackedByteArray, reliable: bool) -> bool:
	if _stage != "ready":
		return false
	return _ble.write(GmProtocol.CMD_UUID, frame, reliable)


func can_send_unreliable() -> bool:
	return _ble != null and _ble.can_send_without_response()


func _on_adapter_state(state: int) -> void:
	_state = state
	var label: String = STATE_NAMES[state] if state < STATE_NAMES.size() else str(state)
	adapter_changed.emit(state == STATE_POWERED_ON, "Bluetooth: " + label)


func _on_connected(id: String) -> void:
	_stage = "discovering"
	connected.emit(id)


func _on_connect_failed(id: String, error: String) -> void:
	_stage = ""
	connect_failed.emit(id, error)


func _on_disconnected(id: String, error: String) -> void:
	_stage = ""
	disconnected.emit(id, error)


func _on_services(uuids: PackedStringArray) -> void:
	for required in [GmProtocol.CMD_UUID, GmProtocol.EVT_UUID, GmProtocol.INFO_UUID]:
		if not uuids.has(required):
			_fail("device is missing characteristic %s (not a Gamemote device?)" % required)
			return
	_stage = "subscribing"
	_ble.set_notify(GmProtocol.EVT_UUID, true)


func _on_notify_state(uuid: String, enabled: bool) -> void:
	if uuid == GmProtocol.EVT_UUID and enabled and _stage == "subscribing":
		_stage = "reading"
		_ble.read(GmProtocol.INFO_UUID)


func _on_value_read(uuid: String, data: PackedByteArray) -> void:
	if uuid != GmProtocol.INFO_UUID or _stage != "reading":
		return
	var info = JSON.parse_string(data.get_string_from_utf8())
	if typeof(info) != TYPE_DICTIONARY:
		_fail("INFO is not valid JSON")
		return
	_stage = "ready"
	log_message.emit("max write: %d B (with response) / %d B (without)" % [
			_ble.get_max_write_length(true), _ble.get_max_write_length(false)])
	link_ready.emit(info)


func _on_notified(uuid: String, data: PackedByteArray) -> void:
	if uuid == GmProtocol.EVT_UUID:
		frame_received.emit(data)


func _on_write_completed(uuid: String, error: String) -> void:
	if error != "":
		log_message.emit("[ble] write %s failed: %s" % [uuid, error])


func _fail(reason: String) -> void:
	log_message.emit("[ble] " + reason)
	connect_failed.emit(_device_id, reason)
	disconnect_from()
