class_name GmProtocol
extends RefCounted
## Gamemote BLE protocol v0: frame encoding/decoding. See protocol/PROTOCOL.md.
## Pure functions, no I/O. Verified against protocol/test_vectors.json.

const SERVICE_UUID := "4afc0001-28d2-43f3-abb0-be04c0c1413f"
const CMD_UUID := "4afc0002-28d2-43f3-abb0-be04c0c1413f"
const EVT_UUID := "4afc0003-28d2-43f3-abb0-be04c0c1413f"
const INFO_UUID := "4afc0004-28d2-43f3-abb0-be04c0c1413f"

const MAX_FRAME := 20
const MAX_SET_PAIRS := 6
const MAX_CHUNK := 16

# App -> device
const SET := 0x01
const TRIGGER := 0x02
const STOP_ALL := 0x03
const PING := 0x04
const ROUTINE_BEGIN := 0x10
const ROUTINE_CHUNK := 0x11
const ROUTINE_END := 0x12
const ROUTINE_RUN := 0x13
const ROUTINE_STOP := 0x14
# Device -> app
const ACK := 0x81
const PONG := 0x82
const TELEMETRY := 0x83
const LOG := 0x84
const ROUTINE_STATE := 0x85

const TYPE_NAMES := {
	SET: "SET", TRIGGER: "TRIGGER", STOP_ALL: "STOP_ALL", PING: "PING",
	ROUTINE_BEGIN: "ROUTINE_BEGIN", ROUTINE_CHUNK: "ROUTINE_CHUNK",
	ROUTINE_END: "ROUTINE_END", ROUTINE_RUN: "ROUTINE_RUN", ROUTINE_STOP: "ROUTINE_STOP",
	ACK: "ACK", PONG: "PONG", TELEMETRY: "TELEMETRY", LOG: "LOG",
	ROUTINE_STATE: "ROUTINE_STATE",
}

# ACK status
const OK := 0
const UNKNOWN_TYPE := 1
const BAD_LENGTH := 2
const BAD_ID := 3
const BUSY := 4
const BAD_PROGRAM := 5
const UNSUPPORTED := 6
const TOO_LARGE := 7
const STATUS_NAMES := ["OK", "UNKNOWN_TYPE", "BAD_LENGTH", "BAD_ID", "BUSY", "BAD_PROGRAM", "UNSUPPORTED", "TOO_LARGE"]

# TELEMETRY flags
const FLAG_ROUTINE_RUNNING := 0x01
const FLAG_FAILSAFE_TRIPPED := 0x02
const FLAG_LIVE_ACTIVE := 0x04
const NO_STEP := 0xFFFF

# ROUTINE_STATE.state
const RS_IDLE := 0
const RS_RUNNING := 1
const RS_FINISHED := 2
const RS_STOPPED := 3
const RS_ERROR := 4
const RS_NAMES := ["idle", "running", "finished", "stopped", "error"]


static func type_name(t: int) -> String:
	return TYPE_NAMES.get(t, "0x%02X" % t)


static func status_name(s: int) -> String:
	return STATUS_NAMES[s] if s >= 0 and s < STATUS_NAMES.size() else str(s)


## CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection.
static func crc16(data: PackedByteArray) -> int:
	var crc := 0xFFFF
	for b in data:
		crc ^= b << 8
		for i in 8:
			crc = ((crc << 1) ^ 0x1021) if (crc & 0x8000) else (crc << 1)
			crc &= 0xFFFF
	return crc


static func _hdr(t: int, seq: int) -> PackedByteArray:
	return PackedByteArray([t & 0xFF, seq & 0xFF])


static func _append_s16(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 2)
	out.encode_s16(at, clampi(v, -32768, 32767))


static func _append_u16(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 2)
	out.encode_u16(at, v & 0xFFFF)


static func _append_u32(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 4)
	out.encode_u32(at, v & 0xFFFFFFFF)


# ------------------------------------------------------------------ encoders

## pairs: Array of [channel_id, value]; 1..6 pairs.
static func encode_set(seq: int, pairs: Array) -> PackedByteArray:
	assert(pairs.size() >= 1 and pairs.size() <= MAX_SET_PAIRS)
	var out := _hdr(SET, seq)
	for p in pairs:
		out.append(int(p[0]) & 0xFF)
		_append_s16(out, int(p[1]))
	return out


static func encode_trigger(seq: int, action: int, params: Array = []) -> PackedByteArray:
	var out := _hdr(TRIGGER, seq)
	out.append(action & 0xFF)
	for p in params:
		_append_s16(out, int(p))
	return out


static func encode_stop_all(seq: int) -> PackedByteArray:
	return _hdr(STOP_ALL, seq)


static func encode_ping(seq: int, t: int) -> PackedByteArray:
	var out := _hdr(PING, seq)
	_append_u32(out, t)
	return out


static func encode_routine_begin(seq: int, slot: int, length: int) -> PackedByteArray:
	var out := _hdr(ROUTINE_BEGIN, seq)
	out.append(slot & 0xFF)
	_append_u16(out, length)
	return out


static func encode_routine_chunk(seq: int, offset: int, data: PackedByteArray) -> PackedByteArray:
	assert(data.size() >= 1 and data.size() <= MAX_CHUNK)
	var out := _hdr(ROUTINE_CHUNK, seq)
	_append_u16(out, offset)
	out.append_array(data)
	return out


static func encode_routine_end(seq: int, crc: int) -> PackedByteArray:
	var out := _hdr(ROUTINE_END, seq)
	_append_u16(out, crc)
	return out


static func encode_routine_run(seq: int, slot: int) -> PackedByteArray:
	var out := _hdr(ROUTINE_RUN, seq)
	out.append(slot & 0xFF)
	return out


static func encode_routine_stop(seq: int) -> PackedByteArray:
	return _hdr(ROUTINE_STOP, seq)


static func encode_ack(seq: int, ref_seq: int, status: int) -> PackedByteArray:
	var out := _hdr(ACK, seq)
	out.append(ref_seq & 0xFF)
	out.append(status & 0xFF)
	return out


static func encode_pong(seq: int, t: int) -> PackedByteArray:
	var out := _hdr(PONG, seq)
	_append_u32(out, t)
	return out


static func encode_telemetry(seq: int, flags: int, step: int, values: Array) -> PackedByteArray:
	var out := _hdr(TELEMETRY, seq)
	out.append(flags & 0xFF)
	_append_u16(out, step)
	for v in values:
		_append_s16(out, int(v))
	return out


static func encode_log(seq: int, text: String) -> PackedByteArray:
	var out := _hdr(LOG, seq)
	var data := text.to_utf8_buffer()
	if data.size() > MAX_FRAME - 2:
		data = data.slice(0, MAX_FRAME - 2)
	out.append_array(data)
	return out


static func encode_routine_state(seq: int, state: int, step: int) -> PackedByteArray:
	var out := _hdr(ROUTINE_STATE, seq)
	out.append(state & 0xFF)
	_append_u16(out, step)
	return out


## Frames to upload a program: BEGIN, CHUNK..., END (consecutive seq numbers).
static func encode_routine_upload(first_seq: int, slot: int, program: PackedByteArray) -> Array[PackedByteArray]:
	var frames: Array[PackedByteArray] = []
	var seq := first_seq
	frames.append(encode_routine_begin(seq, slot, program.size()))
	var off := 0
	while off < program.size():
		seq += 1
		frames.append(encode_routine_chunk(seq, off, program.slice(off, mini(off + MAX_CHUNK, program.size()))))
		off += MAX_CHUNK
	seq += 1
	frames.append(encode_routine_end(seq, crc16(program)))
	return frames


# ------------------------------------------------------------------ decoder

## Decodes any frame. Returns {"ok": true, "type", "name", "seq", ...fields}
## or {"ok": false, "error": String} (plus "type"/"seq" when the header was readable).
static func decode(frame: PackedByteArray) -> Dictionary:
	if frame.size() < 2:
		return {"ok": false, "error": "frame shorter than header"}
	var t := frame[0]
	var d := {"ok": true, "type": t, "name": type_name(t), "seq": frame[1]}
	if frame.size() > MAX_FRAME:
		return _bad(d, "frame longer than 20 bytes")
	var p := frame.slice(2)
	var n := p.size()
	match t:
		SET:
			if n == 0 or n % 3 != 0:
				return _bad(d, "SET: payload must be N*3 bytes")
			var pairs := []
			for i in range(0, n, 3):
				pairs.append([p[i], p.decode_s16(i + 1)])
			d["pairs"] = pairs
		TRIGGER:
			if n < 1 or (n - 1) % 2 != 0:
				return _bad(d, "TRIGGER: bad length")
			d["action"] = p[0]
			var params := []
			for i in range(1, n, 2):
				params.append(p.decode_s16(i))
			d["params"] = params
		STOP_ALL, ROUTINE_STOP:
			if n != 0:
				return _bad(d, "%s: unexpected payload" % d.name)
		PING, PONG:
			if n != 4:
				return _bad(d, "%s: expected 4 bytes" % d.name)
			d["t"] = p.decode_u32(0)
		ROUTINE_BEGIN:
			if n != 3:
				return _bad(d, "ROUTINE_BEGIN: expected 3 bytes")
			d["slot"] = p[0]
			d["length"] = p.decode_u16(1)
		ROUTINE_CHUNK:
			if n < 3 or n > 2 + MAX_CHUNK:
				return _bad(d, "ROUTINE_CHUNK: bad length")
			d["offset"] = p.decode_u16(0)
			d["data"] = p.slice(2).hex_encode()
		ROUTINE_END:
			if n != 2:
				return _bad(d, "ROUTINE_END: expected 2 bytes")
			d["crc"] = p.decode_u16(0)
		ROUTINE_RUN:
			if n != 1:
				return _bad(d, "ROUTINE_RUN: expected 1 byte")
			d["slot"] = p[0]
		ACK:
			if n != 2:
				return _bad(d, "ACK: expected 2 bytes")
			d["ref_seq"] = p[0]
			d["status"] = p[1]
		TELEMETRY:
			if n < 3 or (n - 3) % 2 != 0:
				return _bad(d, "TELEMETRY: bad length")
			d["flags"] = p[0]
			d["step"] = p.decode_u16(1)
			var values := []
			for i in range(3, n, 2):
				values.append(p.decode_s16(i))
			d["values"] = values
		LOG:
			d["text"] = p.get_string_from_utf8()
		ROUTINE_STATE:
			if n != 3:
				return _bad(d, "ROUTINE_STATE: expected 3 bytes")
			d["state"] = p[0]
			d["step"] = p.decode_u16(1)
		_:
			return _bad(d, "unknown frame type 0x%02X" % t)
	return d


static func _bad(d: Dictionary, error: String) -> Dictionary:
	d["ok"] = false
	d["error"] = error
	return d


## Encodes the dictionary form used in test_vectors.json ({"type": "SET", "seq": 1, ...}).
static func encode_from_dict(d: Dictionary) -> PackedByteArray:
	var seq := int(d.seq)
	match String(d.type):
		"SET": return encode_set(seq, d.pairs)
		"TRIGGER": return encode_trigger(seq, int(d.action), d.get("params", []))
		"STOP_ALL": return encode_stop_all(seq)
		"PING": return encode_ping(seq, int(d.t))
		"PONG": return encode_pong(seq, int(d.t))
		"ROUTINE_BEGIN": return encode_routine_begin(seq, int(d.slot), int(d.length))
		"ROUTINE_CHUNK": return encode_routine_chunk(seq, int(d.offset), String(d.data).hex_decode())
		"ROUTINE_END": return encode_routine_end(seq, int(d.crc))
		"ROUTINE_RUN": return encode_routine_run(seq, int(d.slot))
		"ROUTINE_STOP": return encode_routine_stop(seq)
		"ACK": return encode_ack(seq, int(d.ref_seq), int(d.status))
		"TELEMETRY": return encode_telemetry(seq, int(d.flags), int(d.step), d.values)
		"LOG": return encode_log(seq, String(d.text))
		"ROUTINE_STATE": return encode_routine_state(seq, int(d.state), int(d.step))
	push_error("cannot encode %s" % d.type)
	return PackedByteArray()
