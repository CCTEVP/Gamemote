class_name Gamepad3D
extends Node3D
## A clay gamepad lying on the table. Each finger (touch index) owns one control:
## the stick tilts and follows the finger, buttons press in and spring back.
## Positions passed in are world points on the table plane.

signal stick_changed(value: Vector2)       # x right, y up; length <= 1
signal button_changed(index: int, pressed: bool)
signal stop_pressed

## Layout names (see `_layout_for`). "classic" = the old lavender pad ("both" mode);
## "sideways" = the landscape handheld with the console screen (Live). A portrait
## arrangement is added later as one more entry in `_layout_for`: nothing else places controls.
const LAYOUT_CLASSIC := "classic"
const LAYOUT_SIDEWAYS := "sideways"
## Face-button letter per SLOT. Slot order comes from the table's bindings:
## slot 0 = first action (top, X), slot 1 = level channel held (right, B),
## slot 2 = second action (bottom, A), slot 3 = third action (left, Y).
const LETTERS := ["X", "B", "A", "Y"]
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
const LETTER_COLORS := [Clay.ORANGE, Clay.TEAL, Clay.CORAL, Clay.YELLOW]
const SCREEN_PX := Vector2i(640, 352)   # pixels of the console SubViewport

## Set before the node enters the tree.
var layout := LAYOUT_CLASSIC
## Sideways layout only: the SubViewport the console screen is drawn in (add a Control to it).
var screen_viewport: SubViewport
var stick_value := Vector2.ZERO
var _L: Dictionary
var _lift := 0.0                  # how far controls sit above y = 0 (on top of the body)
var _letters := false
var _buttons: Array = []   # {cap: Node3D, mesh, label, center: Vector2, radius, pressed, y, vel, enabled, color}
var _stop: Dictionary
var _stick_pivot: Node3D
var _stick_tilt := Vector2.ZERO   # spring-driven displayed tilt
var _stick_tilt_vel := Vector2.ZERO
var _touches := {}                # touch index -> {"kind": "stick"|"button"|"stop", "i": int}


func _ready() -> void:
	_L = _layout_for(layout)
	_letters = layout != LAYOUT_CLASSIC
	_lift = float(_L.lift)
	_build()


## Positions (local XZ, x right, z down) of everything on the pad for a layout name.
func _layout_for(name: String) -> Dictionary:
	match name:
		LAYOUT_SIDEWAYS:
			return {"lift": 0.35, "stick": Vector2(-3.05, -0.1), "btn": Vector2(3.05, -0.1), "spread": 0.6,
					"btn_r": 0.36, "stop": Vector2(0.0, 1.22), "stop_r": 0.4,
					"screen": Vector2(0.0, -0.35), "screen_size": Vector2(4.0, 2.2)}
		_:
			return {"lift": 0.0, "stick": STICK_POS, "btn": BUTTON_CENTER, "spread": BUTTON_SPREAD,
					"btn_r": BUTTON_RADIUS, "stop": STOP_POS, "stop_r": STOP_RADIUS,
					"screen": Vector2.ZERO, "screen_size": Vector2.ZERO}


func _build() -> void:
	var sideways := layout == LAYOUT_SIDEWAYS
	var body_color := Clay.BODY_GREY if sideways else Clay.PAD
	var dark := Clay.BODY_GREY_DARK if sideways else Clay.PAD_DARK
	if sideways:
		# Handheld: a long matte body, two rounded grips and two small shoulder bumps.
		add_child(Clay.pill(8.6, 3.4, 0.6, body_color))
		for side in [-1, 1]:
			var grip := Clay.pill(2.0, 2.1, 0.55, body_color)
			grip.position += Vector3(side * 3.35, 0, 0.8)
			add_child(grip)
			var bump := Clay.pill(1.6, 0.6, 0.62, body_color)
			bump.position += Vector3(side * 2.75, 0, -1.72)
			add_child(bump)
		_build_screen()
	else:
		add_child(Clay.pill(6.2, 3.0, 0.38, body_color))
		for side in [-1, 1]:
			var grip := Clay.pill(1.5, 1.5, 0.36, body_color)
			grip.position += Vector3(side * 2.1, 0, 1.15)
			add_child(grip)

	# Stick: a well (ring), then a pivot holding the knob.
	var sp: Vector2 = _L.stick
	var ring_color := Clay.TEAL_DARK if sideways else dark
	var stick_color := Clay.TEAL if sideways else Clay.STICK
	var well := Clay.disc(0.95, 0.42, ring_color)
	well.position = Vector3(sp.x, _lift, sp.y)
	if sideways:
		# A low teal ring resting on the body top (y = 0.6), not a tall post.
		well = Clay.disc(0.8, 0.1, ring_color)
		well.position = Vector3(sp.x, 0.56, sp.y)
	add_child(well)
	_stick_pivot = Node3D.new()
	_stick_pivot.position = Vector3(sp.x, 0.42 + _lift, sp.y)
	add_child(_stick_pivot)
	var shaft := Clay.disc(0.28, 0.35, stick_color)
	_stick_pivot.add_child(shaft)
	var cap := Clay.disc(0.62, 0.16, stick_color)
	cap.position.y += 0.33
	_stick_pivot.add_child(cap)
	var top := Clay.dome(0.55, 0.12, Clay.TEAL.lightened(0.08) if sideways else Clay.GRAPE)
	top.position.y = 0.49
	_stick_pivot.add_child(top)

	# Face buttons (diamond: top, right, bottom, left).
	for i in 4:
		var center: Vector2 = _L.btn + BUTTON_OFFSETS[i] * float(_L.spread)
		var color: Color = LETTER_COLORS[i] if sideways else BUTTON_COLORS[i]
		_buttons.append(_make_button(center, _L.btn_r, color, LETTERS[i] if sideways else "", 52 if sideways else 30))

	# STOP: red, centred (under the screen when there is one).
	_stop = _make_button(_L.stop, _L.stop_r, Clay.STOP_RED if sideways else Clay.STOP, "STOP", 30 if sideways else 34)


## The console screen: a dark bezel slab with a quad textured by a SubViewport (2D UI),
## so it stays attached to the body whatever the camera does.
func _build_screen() -> void:
	var c: Vector2 = _L.screen
	var size: Vector2 = _L.screen_size
	var bezel := MeshInstance3D.new()
	# A slim slab just under the screen, in the screen's own dark tone, so the screen's
	# rounded corners read as the edge.
	var box := BoxMesh.new()
	box.size = Vector3(size.x + 0.06, 0.44, size.y + 0.06)
	bezel.mesh = box
	bezel.material_override = Clay.mat(Color("1b1f29"), 0.35)
	bezel.position = Vector3(c.x, 0.4, c.y)
	add_child(bezel)
	screen_viewport = SubViewport.new()
	screen_viewport.size = SCREEN_PX
	screen_viewport.disable_3d = true
	screen_viewport.gui_disable_input = true
	screen_viewport.transparent_bg = false
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(screen_viewport)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	quad.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = screen_viewport.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material_override = m
	quad.rotation.x = -PI / 2
	quad.position = Vector3(c.x, 0.625, c.y)
	add_child(quad)


func _make_button(center: Vector2, radius: float, color: Color, text: String, font: int) -> Dictionary:
	var socket := Clay.disc(radius + 0.08, 0.4, Clay.BODY_GREY_DARK if _letters else Clay.PAD_DARK)
	socket.position = Vector3(center.x, _lift, center.y)
	add_child(socket)
	var cap_root := Node3D.new()
	cap_root.position = Vector3(center.x, 0.4 + _lift, center.y)
	add_child(cap_root)
	var mesh := Clay.disc(radius, 0.2, color)
	cap_root.add_child(mesh)
	var bulge := Clay.dome(radius * 0.9, 0.06, color)
	bulge.position.y = 0.2
	cap_root.add_child(bulge)
	var lbl := Clay.label(text, font, Clay.INK if text != "STOP" or not _letters else Color("fff4ef"), 0.45)
	cap_root.add_child(lbl)
	return {"cap": cap_root, "mesh": mesh, "bulge": bulge, "label": lbl, "center": center,
			"radius": radius, "pressed": false, "y": 0.0, "vel": 0.0, "enabled": true, "color": color}


## Sets the text and enabled state of face button i (from the device's bindings).
func set_button(i: int, text: String, enabled: bool) -> void:
	var b: Dictionary = _buttons[i]
	b.enabled = enabled
	if not _letters:
		b.label.text = text   # sideways pads keep the fixed letter; meanings go on the screen
	var c: Color = b.color if enabled else (Clay.DISABLED if not _letters else Clay.BODY_GREY.lightened(0.22))
	Clay.set_color(b.mesh, c)
	Clay.set_color(b.bulge, c)


func button_center_world(i: int) -> Vector3:
	var c: Vector2 = _buttons[i].center if i >= 0 else _stop.center
	return to_global(Vector3(c.x, 0.6, c.y))


func stick_center_world() -> Vector3:
	return to_global(Vector3(_L.stick.x, 0.6, _L.stick.y))


# ------------------------------------------------------------------ touch routing

func _local(p: Vector3) -> Vector2:
	var l := to_local(p)
	return Vector2(l.x, l.z)


## Returns true when the touch landed on a control (it is then owned by this pad).
func try_press(index: int, p: Vector3) -> bool:
	var q := _local(p)
	if q.distance_to(_L.stop) <= float(_L.stop_r) + 0.12:
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
	if q.distance_to(_L.stick) <= STICK_HIT:
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
	var d: Vector2 = (q - Vector2(_L.stick)) / STICK_REACH
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
		b.cap.position.y = 0.4 + _lift + b.y
		# Squash a little while pressed.
		var squash := 1.0 + clampf(-b.y / PRESS_DEPTH, 0.0, 1.2) * 0.06
		b.cap.scale = Vector3(squash, 1.0 / squash, squash)
	# Stick tilts toward the finger and wobbles back to centre.
	var tx := Clay.spring(_stick_tilt.x, _stick_tilt_vel.x, stick_value.x, delta, 380.0, 16.0)
	var ty := Clay.spring(_stick_tilt.y, _stick_tilt_vel.y, stick_value.y, delta, 380.0, 16.0)
	_stick_tilt = Vector2(tx.x, ty.x)
	_stick_tilt_vel = Vector2(tx.y, ty.y)
	_stick_pivot.rotation = Vector3(-_stick_tilt.y * 0.38, 0.0, -_stick_tilt.x * 0.38)
