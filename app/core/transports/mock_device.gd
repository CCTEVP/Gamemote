class_name GmMockDevice
extends RefCounted
## In-app simulated Gamemote device (port of tools/gamemote/device.py).
## Lets the whole app run on a desktop or phone without hardware.

const FAILSAFE_MS := 500
const TELEMETRY_PERIOD_MS := 200

const DEFAULT_DESCRIPTOR := {
	"proto": 0,
	"name": "Gamemote Mock",
	"fw": "mock-0.1",
	"channels": [
		{"id": 1, "name": "LED", "kind": "level", "min": 0, "max": 255, "neutral": 0},
		{"id": 2, "name": "Servo", "kind": "angle", "min": 0, "max": 180, "neutral": 90},
		{"id": 3, "name": "Motor", "kind": "speed", "min": -100, "max": 100, "neutral": 0},
	],
	"actions": [
		{"id": 1, "name": "Beep", "params": [{"name": "ms", "min": 10, "max": 2000, "default": 200}]},
	],
	"telemetry": [{"name": "Knob", "min": 0, "max": 4095}],
	"routines": {"transfer": true, "max_bytes": 512, "max_loop_depth": 4},
}

signal logged(message: String)

var desc: Dictionary
var channels := {}   # id -> descriptor
var actions := {}    # id -> descriptor
var values := {}     # id -> current value
var connected := false
var transfer_supported := false
var max_bytes := 0
var max_loop_depth := 4

var _seq := 0
var _last_frame_ms := 0.0
var _last_telemetry_ms := 0.0
var _failsafe_tripped := false
var _live_active := false
var _busy_logged := false
var _upload = null  # PackedByteArray while uploading
var _upload_len := 0
var _upload_error := false
var _program: Array = []
var _vm: GmRoutine.VM = null
var _step := GmProtocol.NO_STEP


func _init(descriptor: Dictionary = DEFAULT_DESCRIPTOR) -> void:
	desc = descriptor.duplicate(true)
	for c in desc.channels:
		channels[int(c.id)] = c
		values[int(c.id)] = int(c.neutral)
	for a in desc.actions:
		actions[int(a.id)] = a
	var rt: Dictionary = desc.get("routines", {})
	transfer_supported = bool(rt.get("transfer", false))
	max_bytes = int(rt.get("max_bytes", 0))
	max_loop_depth = int(rt.get("max_loop_depth", 4))


func info_bytes() -> PackedByteArray:
	return JSON.stringify(desc).to_utf8_buffer()


func routine_running() -> bool:
	return _vm != null and _vm.running


func _next_seq() -> int:
	var s := _seq
	_seq = (_seq + 1) & 0xFF
	return s


func _ack(ref_seq: int, status: int) -> PackedByteArray:
	return GmProtocol.encode_ack(_next_seq(), ref_seq, status)


func _apply(ch: int, value: int) -> void:
	if not channels.has(ch):
		return
	var c: Dictionary = channels[ch]
	values[ch] = clampi(value, int(c.min), int(c.max))


func _neutral_all(reason: String) -> void:
	var changed := false
	for id in channels:
		if values[id] != int(channels[id].neutral):
			changed = true
		values[id] = int(channels[id].neutral)
	_live_active = false
	if changed:
		logged.emit("all channels -> neutral (%s)" % reason)


func _trigger(action: int, params: Array) -> void:
	logged.emit("[%s] %s" % [actions[action].name, str(params)])


func _stop_routine(state: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _vm == null or (not _vm.running and state != GmProtocol.RS_FINISHED):
		return out
	_vm.stop()
	_step = GmProtocol.NO_STEP
	_neutral_all("routine ended")
	out.append(GmProtocol.encode_routine_state(_next_seq(), state, GmProtocol.NO_STEP))
	return out


func on_connect(now_ms: float) -> void:
	connected = true
	_last_frame_ms = now_ms
	_last_telemetry_ms = now_ms - TELEMETRY_PERIOD_MS
	_busy_logged = false


func on_disconnect(_now_ms: float) -> void:
	connected = false
	if not routine_running():
		_neutral_all("link lost")


## Processes one CMD write; returns EVT frames to notify.
func handle_cmd(data: PackedByteArray, now_ms: float) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var f := GmProtocol.decode(data)
	if not f.ok:
		if f.has("seq"):
			var known := GmProtocol.TYPE_NAMES.has(f.type)
			out.append(_ack(f.seq, GmProtocol.BAD_LENGTH if known else GmProtocol.UNKNOWN_TYPE))
		return out

	_last_frame_ms = now_ms
	_failsafe_tripped = false
	match f.type:
		GmProtocol.SET:
			if routine_running():
				if not _busy_logged:
					_busy_logged = true
					out.append(GmProtocol.encode_log(_next_seq(), "busy"))
				return out
			for p in f.pairs:
				_apply(p[0], p[1])
			_live_active = true
		GmProtocol.TRIGGER:
			if not actions.has(f.action):
				out.append(_ack(f.seq, GmProtocol.BAD_ID))
				return out
			_trigger(f.action, f.params)
			out.append(_ack(f.seq, GmProtocol.OK))
		GmProtocol.STOP_ALL:
			out.append(_ack(f.seq, GmProtocol.OK))
			out.append_array(_stop_routine(GmProtocol.RS_STOPPED))
			_neutral_all("STOP_ALL")
		GmProtocol.PING:
			out.append(GmProtocol.encode_pong(_next_seq(), f.t))
		GmProtocol.ROUTINE_BEGIN:
			var status := GmProtocol.OK
			if not transfer_supported:
				status = GmProtocol.UNSUPPORTED
			elif routine_running():
				status = GmProtocol.BUSY
			elif f.slot != 0:
				status = GmProtocol.BAD_ID
			elif f.length > max_bytes:
				status = GmProtocol.TOO_LARGE
			else:
				_upload = PackedByteArray()
				_upload_len = f.length
				_upload_error = false
			out.append(_ack(f.seq, status))
		GmProtocol.ROUTINE_CHUNK:
			var chunk := String(f.data).hex_decode()
			if _upload == null or f.offset != _upload.size() or _upload.size() + chunk.size() > _upload_len:
				_upload_error = true
			else:
				_upload.append_array(chunk)
		GmProtocol.ROUTINE_END:
			var ok: bool = _upload != null and not _upload_error and _upload.size() == _upload_len \
					and GmProtocol.crc16(_upload) == f.crc
			if ok:
				var parsed := GmRoutine.parse(_upload, channels.keys(), actions.keys(), max_loop_depth)
				ok = parsed.ok
				if ok:
					_program = parsed.instrs
				else:
					logged.emit("program rejected: %s" % parsed.error)
			_upload = null
			if ok:
				logged.emit("program stored (%d steps)" % _program.size())
			out.append(_ack(f.seq, GmProtocol.OK if ok else GmProtocol.BAD_PROGRAM))
		GmProtocol.ROUTINE_RUN:
			if f.slot != 0 or _program.is_empty():
				out.append(_ack(f.seq, GmProtocol.BAD_ID))
			elif routine_running():
				out.append(_ack(f.seq, GmProtocol.BUSY))
			else:
				_vm = GmRoutine.VM.new(_program, _apply, _trigger,
						func(): _neutral_all("routine STOP_ALL"), func(step): _step = step)
				_vm.start(now_ms)
				_busy_logged = false
				logged.emit("routine running on device")
				out.append(_ack(f.seq, GmProtocol.OK))
				out.append(GmProtocol.encode_routine_state(_next_seq(), GmProtocol.RS_RUNNING, 0))
		GmProtocol.ROUTINE_STOP:
			out.append(_ack(f.seq, GmProtocol.OK))
			out.append_array(_stop_routine(GmProtocol.RS_STOPPED))
		_:
			out.append(_ack(f.seq, GmProtocol.UNKNOWN_TYPE))
	return out


## Advances time; returns EVT frames to notify (empty when disconnected).
func tick(now_ms: float) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _vm != null and _vm.running:
		_vm.tick(now_ms)
		if _vm.finished:
			out.append_array(_stop_routine(GmProtocol.RS_FINISHED))
	elif _live_active and now_ms - _last_frame_ms > FAILSAFE_MS:
		_failsafe_tripped = true
		_neutral_all("failsafe: no frames for 500 ms")

	if connected and now_ms - _last_telemetry_ms >= TELEMETRY_PERIOD_MS:
		_last_telemetry_ms = now_ms
		var flags := 0
		if routine_running():
			flags |= GmProtocol.FLAG_ROUTINE_RUNNING
		if _failsafe_tripped:
			flags |= GmProtocol.FLAG_FAILSAFE_TRIPPED
		if _live_active:
			flags |= GmProtocol.FLAG_LIVE_ACTIVE
		var knob := int(2047 + 2047 * sin(now_ms / 2000.0))
		out.append(GmProtocol.encode_telemetry(_next_seq(), flags,
				_step if routine_running() else GmProtocol.NO_STEP, [knob]))
	if not connected:
		out.clear()
	return out
