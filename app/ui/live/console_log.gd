class_name ConsoleLog
extends RefCounted
## Data model of the Live console (story 002, design/game-brief.md MVP 2): a short ring
## buffer of plain-word lines plus round-trip-time tracking for the status bar.
## No visuals: the console view renders `get_lines()` and listens to the signals.
##
## A line is a Dictionary: {"text": String, "kind": String, "key": String, "time": float}
## where `kind` is one of KINDS and `key` is "" for ordinary lines or the merge key of an
## updating line (see `update()`); `time` is seconds since app start (last update).

const KINDS := ["status", "command", "feedback", "error"]
const MAX_LINES := 200
const RTT_WINDOW := 40

## A new line was appended (it is the last one). Older lines may have been dropped.
signal line_added(line: Dictionary)
## The last line was rewritten in place (merged update); it is still the last line.
signal line_updated(line: Dictionary)
## Anything about the lines changed (added, updated or cleared). Handy for a full redraw.
signal changed
## A round-trip sample arrived (or the samples were cleared: both values are -1).
signal rtt_changed(latest_ms: int, p95_ms: int)

var _lines: Array = []
var _rtts: Array = []
var _latest_rtt := -1
var _p95_rtt := -1


## Appends a line. `kind` is one of KINDS (anything else counts as "status").
## Returns the new line. Oldest lines are dropped beyond MAX_LINES.
func add(text: String, kind: String = "status") -> Dictionary:
	return _append(text, kind, "")


## Appends a line, or, when the LAST line was made by `update()` with the same `key`,
## rewrites it instead. Use for stick values and telemetry so they do not flood the log.
## Any other line added in between ends the merge, so the next update starts a new line.
func update(key: String, text: String, kind: String = "command") -> Dictionary:
	if key != "" and not _lines.is_empty() and _lines.back().key == key:
		var line: Dictionary = _lines.back()
		line.text = text
		line.time = _now()
		line_updated.emit(line)
		changed.emit()
		return line
	return _append(text, kind, key)


## The lines, oldest first (newest last). Do not modify the returned array.
func get_lines() -> Array:
	return _lines


## Number of lines currently held.
func size() -> int:
	return _lines.size()


## Drops all lines (round-trip samples are kept; see `clear_rtt()`).
func clear() -> void:
	_lines.clear()
	changed.emit()


## Records one round-trip time sample in milliseconds. Negative values are ignored.
func add_rtt(ms: int) -> void:
	if ms < 0:
		return
	_rtts.append(ms)
	if _rtts.size() > RTT_WINDOW:
		_rtts.pop_front()
	_latest_rtt = ms
	var sorted := _rtts.duplicate()
	sorted.sort()
	_p95_rtt = int(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])
	rtt_changed.emit(_latest_rtt, _p95_rtt)


## Forgets all round-trip samples (e.g. after a reconnect).
func clear_rtt() -> void:
	_rtts.clear()
	_latest_rtt = -1
	_p95_rtt = -1
	rtt_changed.emit(-1, -1)


## True once at least one round-trip sample exists.
func has_rtt() -> bool:
	return _latest_rtt >= 0


## Latest round-trip time in ms, or -1 when there is none yet.
func latest_rtt() -> int:
	return _latest_rtt


## 95th percentile of the last RTT_WINDOW samples in ms, or -1 when there is none yet.
func p95_rtt() -> int:
	return _p95_rtt


func _append(text: String, kind: String, key: String) -> Dictionary:
	var line := {"text": text, "kind": kind if kind in KINDS else "status", "key": key, "time": _now()}
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	line_added.emit(line)
	changed.emit()
	return line


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
