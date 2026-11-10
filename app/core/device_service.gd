extends Node
## Autoload "Device": owns the transport and the connection to one Gamemote device.
##
## * connection state machine with auto-reconnect
## * live control: set_channel() values are streamed at 30 Hz (coalesced),
##   with a PING keepalive every 250 ms (also used to measure round-trip time)
## * routines in two modes: LIVE (VM runs here) and TRANSFER (uploaded, runs on device)
## * safety: STOP_ALL when the app goes to the background during live control

enum State { OFF, IDLE, SCANNING, CONNECTING, READY, RECONNECTING }
enum RunMode { NONE, LIVE, TRANSFER }

const STATE_NAMES := ["Bluetooth off", "Idle", "Scanning", "Connecting", "Connected", "Reconnecting"]
const STREAM_PERIOD_MS := 33
const REFRESH_PERIOD_MS := 200
const KEEPALIVE_PERIOD_MS := 250
const CONNECT_TIMEOUT_MS := 10000
const RTT_WINDOW := 40

signal state_changed(state: int)
signal log_added(text: String)
signal devices_changed(devices: Dictionary)
signal info_changed(info: Dictionary)
signal telemetry_received(flags: int, step: int, values: Array)
signal rtt_updated(p50: int, p95: int)
## Every single PING/PONG round-trip sample (ms), for the Live console.
signal rtt_measured(ms: int)
## The device answered a command with an error status (GmProtocol status code).
signal command_failed(status: int)
signal routine_changed(mode: int, state: int, block_id: Variant)

var transport: GmTransport
var state: int = State.OFF
var info: Dictionary = {}
var devices: Dictionary = {}   # id -> {"name", "rssi"}
var device_id := ""
var last_telemetry: Dictionary = {}

var run_mode: int = RunMode.NONE
var routine_state: int = GmProtocol.RS_IDLE
var routine_step_blocks: Array = []

var _seq := 0
var _acks: Dictionary = {}       # ref_seq -> status
var _targets: Dictionary = {}    # channel -> value we want on the device
var _dirty: Dictionary = {}      # channel -> true
var _last_stream_ms := 0
var _last_refresh_ms := 0
var _last_ping_ms := 0
var _rtts: Array = []
var _want_connected := false
var _connect_started_ms := 0
var _reconnect_at_ms := -1
var _live_vm: GmRoutine.VM = null
var _live_clock_start := 0


func _ready() -> void:
	# Phones/tablets default to Bluetooth. Desktops default to the mock device: there,
	# CoreBluetooth only works from an exported app whose Info.plist has the usage
	# string (pass `-- --ble` to try it anyway).
	var args := OS.get_cmdline_user_args()
	var use_ble := GmBleTransport.is_available() and not args.has("--mock") \
			and (OS.has_feature("mobile") or args.has("--ble"))
	use_transport("ble" if use_ble else "mock")


## Switch between "ble" and "mock". Drops any current connection.
func use_transport(kind: String) -> void:
	if transport:
		_want_connected = false
		transport.disconnect_from()
	transport = GmMockTransport.new() if kind == "mock" else GmBleTransport.new()
	transport.adapter_changed.connect(_on_adapter_changed)
	transport.device_found.connect(_on_device_found)
	transport.connected.connect(_on_connected)
	transport.link_ready.connect(_on_link_ready)
	transport.connect_failed.connect(_on_connect_failed)
	transport.disconnected.connect(_on_disconnected)
	transport.frame_received.connect(_on_frame)
	transport.log_message.connect(log_line)
	devices.clear()
	devices_changed.emit(devices)
	_set_state(State.OFF)
	log_line("Transport: %s" % kind)
	transport.start()


func log_line(text: String) -> void:
	var line := "%7.2f  %s" % [Time.get_ticks_msec() / 1000.0, text]
	print(line)
	log_added.emit(line)


func _set_state(s: int) -> void:
	if state != s:
		state = s
		state_changed.emit(s)


func _now() -> int:
	return Time.get_ticks_msec()


func next_seq() -> int:
	var s := _seq
	_seq = (_seq + 1) & 0xFF
	return s


# ------------------------------------------------------------------ connection

func start_scan() -> void:
	if not transport.is_adapter_ready():
		log_line("Cannot scan: adapter not ready")
		return
	devices.clear()
	devices_changed.emit(devices)
	transport.start_scan()
	_set_state(State.SCANNING)


func stop_scan() -> void:
	transport.stop_scan()
	if state == State.SCANNING:
		_set_state(State.IDLE)


func connect_to(id: String) -> void:
	device_id = id
	_want_connected = true
	_connect_started_ms = _now()
	_reconnect_at_ms = -1
	transport.stop_scan()
	transport.connect_to(id)
	_set_state(State.CONNECTING)
	log_line("Connecting to %s..." % devices.get(id, {}).get("name", id))


func disconnect_device() -> void:
	_want_connected = false
	_reconnect_at_ms = -1
	_stop_live_routine(false)
	# Leave the device safe, except when a transferred routine is meant to keep running.
	if state == State.READY and run_mode != RunMode.TRANSFER:
		stop_all()
	transport.disconnect_from()
	_set_state(State.IDLE if transport.is_adapter_ready() else State.OFF)


func _on_adapter_changed(ready: bool, message: String) -> void:
	log_line(message)
	if ready and state == State.OFF:
		_set_state(State.IDLE)
	elif not ready:
		_set_state(State.OFF)


func _on_device_found(id: String, dev_name: String, rssi: int) -> void:
	var is_new := not devices.has(id)
	devices[id] = {"name": dev_name if dev_name != "" else "(unnamed)", "rssi": rssi}
	devices_changed.emit(devices)
	if is_new:
		log_line("Found %s (%d dBm)" % [devices[id].name, rssi])


func _on_connected(_id: String) -> void:
	log_line("Link up, discovering services...")


func _on_link_ready(p_info: Dictionary) -> void:
	info = p_info
	_acks.clear()
	_rtts.clear()
	_targets.clear()
	_dirty.clear()
	for c in info.get("channels", []):
		_targets[int(c.id)] = int(c.neutral)
	_set_state(State.READY)
	log_line("Ready: %s (fw %s, protocol %d)" % [info.get("name", "?"), info.get("fw", "?"), int(info.get("proto", -1))])
	info_changed.emit(info)


func _on_connect_failed(_id: String, reason: String) -> void:
	log_line("Connect failed: %s" % reason)
	if _want_connected and state == State.RECONNECTING:
		_reconnect_at_ms = _now() + 2000
	else:
		_want_connected = false
		_set_state(State.IDLE if transport.is_adapter_ready() else State.OFF)


func _on_disconnected(_id: String, reason: String) -> void:
	_stop_live_routine(false)
	if run_mode == RunMode.LIVE:
		run_mode = RunMode.NONE
	log_line("Disconnected%s" % ("" if reason == "" else ": " + reason))
	if _want_connected:
		_set_state(State.RECONNECTING)
		_reconnect_at_ms = _now() + 1000
	else:
		_set_state(State.IDLE if transport.is_adapter_ready() else State.OFF)


func is_ready() -> bool:
	return state == State.READY


# ------------------------------------------------------------------ frames

func _on_frame(frame: PackedByteArray) -> void:
	var f := GmProtocol.decode(frame)
	if not f.ok:
		log_line("Bad frame %s: %s" % [frame.hex_encode(), f.error])
		return
	match f.type:
		GmProtocol.ACK:
			_acks[f.ref_seq] = f.status
			if f.status != GmProtocol.OK:
				log_line("Device answered %s" % GmProtocol.status_name(f.status))
				command_failed.emit(f.status)
		GmProtocol.PONG:
			_add_rtt((_now() & 0xFFFFFFFF) - int(f.t))
		GmProtocol.TELEMETRY:
			last_telemetry = f
			if f.flags & GmProtocol.FLAG_ROUTINE_RUNNING and run_mode == RunMode.TRANSFER:
				routine_changed.emit(run_mode, GmProtocol.RS_RUNNING, _block_for_step(f.step))
			telemetry_received.emit(f.flags, f.step, f.values)
		GmProtocol.LOG:
			log_line("[device] " + String(f.text))
		GmProtocol.ROUTINE_STATE:
			routine_state = f.state
			log_line("Device routine: %s" % GmProtocol.RS_NAMES[f.state])
			if f.state != GmProtocol.RS_RUNNING:
				run_mode = RunMode.NONE
			routine_changed.emit(RunMode.TRANSFER, f.state, _block_for_step(f.step))


func _add_rtt(ms: int) -> void:
	if ms < 0 or ms > 10000:
		return
	_rtts.append(ms)
	rtt_measured.emit(ms)
	if _rtts.size() > RTT_WINDOW:
		_rtts.pop_front()
	var sorted := _rtts.duplicate()
	sorted.sort()
	rtt_updated.emit(sorted[sorted.size() / 2], sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])


func send_unreliable(frame: PackedByteArray) -> bool:
	if not is_ready() or not transport.can_send_unreliable():
		return false
	return transport.send(frame, false)


func send_reliable(frame: PackedByteArray) -> bool:
	if not is_ready():
		return false
	return transport.send(frame, true)


## Sends a frame that expects an ACK and waits for it.
## Returns the ACK status, or -1 on timeout/disconnect.
func request(frame: PackedByteArray, timeout_ms: int = 2000) -> int:
	var seq: int = frame[1]
	_acks.erase(seq)
	if not send_reliable(frame):
		return -1
	var deadline := _now() + timeout_ms
	while not _acks.has(seq):
		if _now() > deadline or not is_ready():
			return -1
		await get_tree().process_frame
	return _acks[seq]


# ------------------------------------------------------------------ live control

func get_channel(ch: int) -> int:
	return _targets.get(ch, 0)


func set_channel(ch: int, value: int) -> void:
	if _targets.get(ch) != value:
		_targets[ch] = value
		_dirty[ch] = true


func trigger(action: int, params: Array = []) -> void:
	send_reliable(GmProtocol.encode_trigger(next_seq(), action, params))


func stop_all() -> void:
	_stop_live_routine(false)
	for c in info.get("channels", []):
		_targets[int(c.id)] = int(c.neutral)
	_dirty.clear()
	send_reliable(GmProtocol.encode_stop_all(next_seq()))


func _stream(now: int) -> void:
	if not is_ready() or now - _last_stream_ms < STREAM_PERIOD_MS:
		return
	_last_stream_ms = now
	var pairs := []
	if not _dirty.is_empty():
		for ch in _dirty:
			pairs.append([ch, _targets[ch]])
	elif now - _last_refresh_ms >= REFRESH_PERIOD_MS:
		# Periodically resend non-neutral values in case an unreliable write was lost.
		_last_refresh_ms = now
		for c in info.get("channels", []):
			var ch := int(c.id)
			if _targets.get(ch, int(c.neutral)) != int(c.neutral):
				pairs.append([ch, _targets[ch]])
	var sent_all := true
	for i in range(0, pairs.size(), GmProtocol.MAX_SET_PAIRS):
		var chunk := pairs.slice(i, i + GmProtocol.MAX_SET_PAIRS)
		if send_unreliable(GmProtocol.encode_set(next_seq(), chunk)):
			for p in chunk:
				_dirty.erase(p[0])
		else:
			sent_all = false
	# PING doubles as keepalive (device failsafe) and round-trip-time probe.
	if sent_all and now - _last_ping_ms >= KEEPALIVE_PERIOD_MS:
		if send_unreliable(GmProtocol.encode_ping(next_seq(), now & 0xFFFFFFFF)):
			_last_ping_ms = now


# ------------------------------------------------------------------ routines

func supports_transfer() -> bool:
	return bool(info.get("routines", {}).get("transfer", false))


func _block_for_step(step: int) -> Variant:
	if step >= 0 and step < routine_step_blocks.size():
		return routine_step_blocks[step]
	return null


## Runs a routine with the VM in the app. Stops if the link drops (device fails safe).
func run_live(ast: Dictionary) -> String:
	if not is_ready():
		return "not connected"
	var compiled := GmRoutine.compile(ast)
	if not compiled.ok:
		return compiled.error
	var parsed := GmRoutine.parse(compiled.program)
	if not parsed.ok:
		return parsed.error
	_stop_live_routine(false)
	routine_step_blocks = compiled.step_blocks
	_live_vm = GmRoutine.VM.new(parsed.instrs, set_channel, trigger, _vm_stop_all,
			func(step): routine_changed.emit(RunMode.LIVE, GmProtocol.RS_RUNNING, _block_for_step(step)))
	_live_clock_start = _now()
	_live_vm.start(0)
	run_mode = RunMode.LIVE
	routine_state = GmProtocol.RS_RUNNING
	log_line("Routine '%s' running in the app (live mode)" % ast.get("name", "?"))
	routine_changed.emit(RunMode.LIVE, GmProtocol.RS_RUNNING, null)
	return ""


## Uploads a routine and runs it on the device. Keeps running if the link drops.
func run_transferred(ast: Dictionary) -> String:
	if not is_ready():
		return "not connected"
	if not supports_transfer():
		return "this device cannot run transferred routines"
	var compiled := GmRoutine.compile(ast)
	if not compiled.ok:
		return compiled.error
	var program: PackedByteArray = compiled.program
	var max_bytes := int(info.routines.get("max_bytes", 0))
	if program.size() > max_bytes:
		return "routine is %d bytes; device accepts %d" % [program.size(), max_bytes]
	_stop_live_routine(true)
	log_line("Uploading '%s' (%d bytes)..." % [ast.get("name", "?"), program.size()])
	var first := next_seq()
	var frames := GmProtocol.encode_routine_upload(first, 0, program)
	_seq = (first + frames.size()) & 0xFF
	for frame in frames:
		if frame[0] == GmProtocol.ROUTINE_CHUNK:
			if not send_reliable(frame):
				return "upload interrupted"
		else:
			var status: int = await request(frame)
			if status != GmProtocol.OK:
				return "upload failed (%s)" % ("timeout" if status < 0 else GmProtocol.status_name(status))
	var run_status: int = await request(GmProtocol.encode_routine_run(next_seq(), 0))
	if run_status != GmProtocol.OK:
		return "run failed (%s)" % ("timeout" if run_status < 0 else GmProtocol.status_name(run_status))
	routine_step_blocks = compiled.step_blocks
	run_mode = RunMode.TRANSFER
	log_line("Routine running on the device (transferred mode)")
	return ""


## A "stop all" block inside a live routine: everything to neutral, routine continues.
func _vm_stop_all() -> void:
	for c in info.get("channels", []):
		_targets[int(c.id)] = int(c.neutral)
	_dirty.clear()
	send_reliable(GmProtocol.encode_stop_all(next_seq()))


func stop_routine() -> void:
	if run_mode == RunMode.TRANSFER or routine_state == GmProtocol.RS_RUNNING:
		send_reliable(GmProtocol.encode_routine_stop(next_seq()))
	_stop_live_routine(true)


func _stop_live_routine(send_stop: bool) -> void:
	if _live_vm == null:
		return
	var was_running := _live_vm.running
	_live_vm.stop()
	_live_vm = null
	if run_mode == RunMode.LIVE:
		run_mode = RunMode.NONE
	routine_state = GmProtocol.RS_STOPPED
	if was_running:
		# Routines end with every channel at neutral (PROTOCOL.md section 4).
		for c in info.get("channels", []):
			set_channel(int(c.id), int(c.neutral))
		if send_stop and is_ready():
			send_reliable(GmProtocol.encode_stop_all(next_seq()))
		routine_changed.emit(RunMode.LIVE, GmProtocol.RS_STOPPED, null)


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if transport == null:
		return
	transport.poll(delta)
	var now := _now()

	var vm := _live_vm
	if vm != null and vm.running:
		vm.tick(now - _live_clock_start)
		if vm == _live_vm and vm.finished:
			_live_vm = null
			run_mode = RunMode.NONE
			routine_state = GmProtocol.RS_FINISHED
			for c in info.get("channels", []):
				set_channel(int(c.id), int(c.neutral))
			log_line("Routine finished")
			routine_changed.emit(RunMode.LIVE, GmProtocol.RS_FINISHED, null)

	_stream(now)

	if state == State.CONNECTING and now - _connect_started_ms > CONNECT_TIMEOUT_MS:
		log_line("Connect timed out")
		_want_connected = false
		transport.disconnect_from()
		_set_state(State.IDLE)
	if state == State.RECONNECTING and _reconnect_at_ms >= 0 and now >= _reconnect_at_ms:
		_reconnect_at_ms = -1
		log_line("Reconnecting...")
		transport.connect_to(device_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and is_ready():
		# iOS suspends us in the background. Leave the device safe, unless a
		# transferred routine is meant to keep running.
		if run_mode != RunMode.TRANSFER:
			log_line("App paused: STOP_ALL")
			stop_all()
