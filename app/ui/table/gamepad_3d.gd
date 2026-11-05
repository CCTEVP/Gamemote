class_name Gamepad3D
extends Node3D
## A clay gamepad lying on the table. Each finger (touch index) owns one control:
## the stick tilts and follows the finger, buttons press in and spring back.
## Positions passed in are world points on the table plane.

signal stick_changed(value: Vector2)       # x right, y up; length <= 1
signal button_changed(index: int, pressed: bool)
signal stop_pressed

const STICK_POS := Vector2(-1.75, 0.0)
const STICK_REACH := 0.9          # finger travel (world units) for full deflection
const STICK_HIT := 1.25
const DEADZONE := 0.12
const BUTTON_CENTER := Vector2(1.75, 0.0)
const BUTTON_SPREAD := 0.62
const BUTTON_RADIUS := 0.36
const STOP_POS := Vector2(0.0, 1.45)
const STOP_RADIUS := 0.42
const PRESS_DEPTH := 0.09

## Diamond order: top, right, bottom, left (like a real pad).
const BUTTON_OFFSETS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const BUTTON_COLORS := [Clay.MINT, Clay.PEACH, Clay.SKY, Clay.PINK]

var stick_value := Vector2.ZERO
var _buttons: Array = []   # {cap: Node3D, mesh, label, center: Vector2, radius, pressed, y, vel, enabled, color}
var _stop: Dictionary
var _stick_pivot: Node3D
var _stick_tilt := Vector2.ZERO   # spring-driven displayed tilt
var _stick_tilt_vel := Vector2.ZERO
var _touches := {}                # touch index -> {"kind": "stick"|"button"|"stop", "i": int}


func _ready() -> void:
	_build()


func _build() -> void:
	# Body: a big lavender pill with two grips.
	add_child(Clay.pill(6.2, 3.0, 0.38, Clay.PAD))
	for side in [-1, 1]:
		var grip := Clay.pill(1.5, 1.5, 0.36, Clay.PAD)
		grip.position += Vector3(side * 2.1, 0, 1.15)
		add_child(grip)

	# Stick: dark well, then a pivot holding the knob.
	var well := Clay.disc(0.95, 0.42, Clay.PAD_DARK)
	well.position = Vector3(STICK_POS.x, 0.0, STICK_POS.y)
	add_child(well)
	_stick_pivot = Node3D.new()
	_stick_pivot.position = Vector3(STICK_POS.x, 0.42, STICK_POS.y)
	add_child(_stick_pivot)
	var shaft := Clay.disc(0.28, 0.35, Clay.STICK)
	_stick_pivot.add_child(shaft)
	var cap := Clay.disc(0.62, 0.16, Clay.STICK)
	cap.position.y += 0.33
	_stick_pivot.add_child(cap)
	var top := Clay.dome(0.55, 0.12, Clay.GRAPE)
	top.position.y = 0.49
	_stick_pivot.add_child(top)

	# Face buttons.
	for i in 4:
		var center: Vector2 = BUTTON_CENTER + BUTTON_OFFSETS[i] * BUTTON_SPREAD
		_buttons.append(_make_button(center, BUTTON_RADIUS, BUTTON_COLORS[i], "", 30))

	# STOP: bigger, red, centred below the stick and buttons.
	_stop = _make_button(STOP_POS, STOP_RADIUS, Clay.STOP, "STOP", 34)


func _make_button(center: Vector2, radius: float, color: Color, text: String, font: int) -> Dictionary:
	var socket := Clay.disc(radius + 0.08, 0.4, Clay.PAD_DARK)
	socket.position = Vector3(center.x, 0, center.y)
	add_child(socket)
	var cap_root := Node3D.new()
	cap_root.position = Vector3(center.x, 0.4, center.y)
	add_child(cap_root)
	var mesh := Clay.disc(radius, 0.2, color)
	cap_root.add_child(mesh)
	var bulge := Clay.dome(radius * 0.9, 0.06, color)
	bulge.position.y = 0.2
	cap_root.add_child(bulge)
	var lbl := Clay.label(text, font, Clay.INK, 0.42)
	cap_root.add_child(lbl)
	return {"cap": cap_root, "mesh": mesh, "bulge": bulge, "label": lbl, "center": center,
			"radius": radius, "pressed": false, "y": 0.0, "vel": 0.0, "enabled": true, "color": color}


## Sets the text and enabled state of face button i (from the device's bindings).
func set_button(i: int, text: String, enabled: bool) -> void:
	var b: Dictionary = _buttons[i]
	b.enabled = enabled
	b.label.text = text
	var c: Color = b.color if enabled else Clay.DISABLED
	Clay.set_color(b.mesh, c)
	Clay.set_color(b.bulge, c)


func button_center_world(i: int) -> Vector3:
	var c: Vector2 = _buttons[i].center if i >= 0 else _stop.center
	return to_global(Vector3(c.x, 0.6, c.y))


func stick_center_world() -> Vector3:
	return to_global(Vector3(STICK_POS.x, 0.6, STICK_POS.y))


# ------------------------------------------------------------------ touch routing

func _local(p: Vector3) -> Vector2:
	var l := to_local(p)
	return Vector2(l.x, l.z)


## Returns true when the touch landed on a control (it is then owned by this pad).
func try_press(index: int, p: Vector3) -> bool:
	var q := _local(p)
	if q.distance_to(STOP_POS) <= STOP_RADIUS + 0.12:
		_touches[index] = {"kind": "stop", "i": -1}
		_set_pressed(_stop, true)
		stop_pressed.emit()
		return true
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		if b.enabled and q.distance_to(b.center) <= b.radius + 0.12:
			_touches[index] = {"kind": "button", "i": i}
			_set_pressed(b, true)
			button_changed.emit(i, true)
			return true
	if q.distance_to(STICK_POS) <= STICK_HIT:
		_touches[index] = {"kind": "stick", "i": -1}
		_move_stick(q)
		return true
	return false


func move(index: int, p: Vector3) -> bool:
	if not _touches.has(index):
		return false
	if _touches[index].kind == "stick":
		_move_stick(_local(p))
	return true


func release(index: int) -> bool:
	if not _touches.has(index):
		return false
	var t: Dictionary = _touches[index]
	_touches.erase(index)
	match t.kind:
		"stick":
			stick_value = Vector2.ZERO
			stick_changed.emit(stick_value)
		"button":
			_set_pressed(_buttons[t.i], false)
			button_changed.emit(t.i, false)
		"stop":
			_set_pressed(_stop, false)
	return true


## Lets go of everything (app paused, link lost).
func release_all() -> void:
	for index in _touches.keys():
		release(index)


func _move_stick(q: Vector2) -> void:
	var d := (q - STICK_POS) / STICK_REACH
	if d.length() > 1.0:
		d = d.normalized()
	var v := Vector2(d.x, -d.y)  # screen-up is world -Z
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	if v != stick_value:
		stick_value = v
		stick_changed.emit(v)


func _set_pressed(b: Dictionary, on: bool) -> void:
	if b.pressed == on:
		return
	b.pressed = on
	if on and OS.has_feature("mobile"):
		Input.vibrate_handheld(12, 0.6)


# ------------------------------------------------------------------ springs

func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	for b in _buttons + [_stop]:
		var s := Clay.spring(b.y, b.vel, -PRESS_DEPTH if b.pressed else 0.0, delta)
		b.y = s.x
		b.vel = s.y
		b.cap.position.y = 0.4 + b.y
		# Squash a little while pressed.
		var squash := 1.0 + clampf(-b.y / PRESS_DEPTH, 0.0, 1.2) * 0.06
		b.cap.scale = Vector3(squash, 1.0 / squash, squash)
	# Stick tilts toward the finger and wobbles back to centre.
	var tx := Clay.spring(_stick_tilt.x, _stick_tilt_vel.x, stick_value.x, delta, 380.0, 16.0)
	var ty := Clay.spring(_stick_tilt.y, _stick_tilt_vel.y, stick_value.y, delta, 380.0, 16.0)
	_stick_tilt = Vector2(tx.x, ty.x)
	_stick_tilt_vel = Vector2(tx.y, ty.y)
	_stick_pivot.rotation = Vector3(-_stick_tilt.y * 0.38, 0.0, -_stick_tilt.x * 0.38)
