class_name GmMockTransport
extends GmTransport
## Simulated device inside the app: no Bluetooth needed. Adds a little latency so
## the app behaves like it would over a real link.

const DEVICE_ID := "mock-1"
const LATENCY_MS := 20.0

var device := GmMockDevice.new()
var _scanning := false
var _scan_timer := 0.0
var _connect_timer := -1.0
var _connected := false
var _inbox: Array = []   # [deliver_at_ms, frame] (app -> device)
var _outbox: Array = []  # [deliver_at_ms, frame] (device -> app)


func _init() -> void:
	device.logged.connect(func(m): log_message.emit("[mock] " + m))


func get_kind() -> String:
	return "mock"


func is_adapter_ready() -> bool:
	return true


func start() -> void:
	adapter_changed.emit(true, "Mock device (no Bluetooth)")


func _now() -> float:
	return float(Time.get_ticks_msec())


func poll(delta: float) -> void:
	var now := _now()
	if _scanning:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = 1.0
			device_found.emit(DEVICE_ID, "GM-Mock", -42)
	if _connect_timer >= 0.0:
		_connect_timer -= delta
		if _connect_timer < 0.0:
			_connected = true
			device.on_connect(now)
			connected.emit(DEVICE_ID)
			var info = JSON.parse_string(device.info_bytes().get_string_from_utf8())
			link_ready.emit(info)
	while not _inbox.is_empty() and _inbox[0][0] <= now:
		var frame: PackedByteArray = _inbox.pop_front()[1]
		for evt in device.handle_cmd(frame, now):
			_outbox.append([now + LATENCY_MS, evt])
	for evt in device.tick(now):
		_outbox.append([now + LATENCY_MS, evt])
	while _connected and not _outbox.is_empty() and _outbox[0][0] <= now:
		frame_received.emit(_outbox.pop_front()[1])


func start_scan() -> void:
	_scanning = true
	_scan_timer = 0.4


func stop_scan() -> void:
	_scanning = false


func connect_to(id: String) -> void:
	if id != DEVICE_ID:
		connect_failed.emit(id, "unknown mock device")
		return
	_scanning = false
	_connect_timer = 0.3


func disconnect_from() -> void:
	_connect_timer = -1.0
	if _connected:
		_connected = false
		_inbox.clear()
		_outbox.clear()
		device.on_disconnect(_now())
		disconnected.emit(DEVICE_ID, "")


## Test hook: drop the link as if the device went out of range.
func simulate_link_loss() -> void:
	if _connected:
		_connected = false
		_inbox.clear()
		_outbox.clear()
		device.on_disconnect(_now())
		disconnected.emit(DEVICE_ID, "simulated link loss")


func send(frame: PackedByteArray, _reliable: bool) -> bool:
	if not _connected:
		return false
	_inbox.append([_now() + LATENCY_MS, frame])
	return true
