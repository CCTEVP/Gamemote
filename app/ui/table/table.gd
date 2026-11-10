extends Node3D
## The 3D table: a top-down orthographic view of a clay gamepad (live control) and a
## routine board (snap-together blocks). Touches are projected onto the table plane
## and routed to whichever object they land on; each finger keeps its owner until it
## lifts, so the stick and buttons work at the same time.
##
## `mode` picks what is on the table: "both" (the combined prototype), "live" (only the
## gamepad) or "builder" (only the block board). Set it before the node enters the tree;
## the Live and Builder scenes do that in their `_init`.

const HOME_SCENE := "res://ui/home/home.tscn"
const CONTENT := Vector2(19.2, 9.6)   # world area that must stay visible (x by z)
const LIVE_CONTENT := Vector2(13.0, 8.0)
const BUILDER_CONTENT := Vector2(9.0, 9.6)
const LIVE_PAD_SCALE := 1.9
const TILT_DEG := 12.0                # slight tilt so pressed buttons and shadows read
const TOP_BAR_PT := 52.0
const ORBIT_YAW_PER_PT := 0.45        # degrees of turn per point dragged sideways
const ORBIT_PITCH_PER_PT := 0.35      # degrees of tilt per point dragged up/down
const ORBIT_MIN_ELEVATION := 28.0     # lowest camera angle above the table while peeking
const CAMERA_DISTANCE := 30.0

## "both" | "live" | "builder". Must be set before the scene enters the tree.
var mode := "both"
var camera: Camera3D
var gamepad: Gamepad3D   # null in "builder" mode
var board: BlockBoard    # null in "live" mode
var _content := CONTENT
var _owners := {}            # touch index -> "pad" | "board" | "orbit"
var _look_at := Vector3.ZERO
var _yaw := 0.0              # degrees around the table's vertical axis
var _elevation := 90.0 - TILT_DEG
var _yaw_vel := 0.0
var _elevation_vel := 0.0
var _orbiting := false
var _status: Label
var _connect: Button
var _auto_connect := false
## Live mode only (null elsewhere): the plain-word console the Live view renders.
var console: ConsoleLog
var _last_state := -1
var _bindings := {"x": -1, "y": -1, "buttons": [{}, {}, {}, {}]}


func _ready() -> void:
	_build_world()
	_build_overlay()
	Device.state_changed.connect(_on_state)
	Device.info_changed.connect(_on_info)
	Device.devices_changed.connect(_on_devices)
	if mode == "live":
		console = ConsoleLog.new()
		Device.rtt_measured.connect(console.add_rtt)
		Device.command_failed.connect(_on_command_failed)
		Device.log_added.connect(_on_device_log)
		Device.telemetry_received.connect(_on_telemetry)
		Device.routine_changed.connect(_on_routine_console)
	if gamepad:
		gamepad.stick_changed.connect(_on_stick)
		gamepad.button_changed.connect(_on_button)
		gamepad.stop_pressed.connect(_on_stop)
	if board:
		Device.routine_changed.connect(_on_routine)
		board.run_requested.connect(_on_run)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	if Device.is_ready():
		_on_info(Device.info)
	_on_state(Device.state)


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Clay.TABLE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e8")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.17  # Godot diffuse carries a ~pi factor: 0.17 is a full sun here
	sun.light_color = Color("fff1de")
	sun.shadow_enabled = true
	sun.shadow_blur = 2.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var table := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 40)
	table.mesh = plane
	table.material_override = Clay.mat(Clay.TABLE, 1.0)
	add_child(table)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 100.0
	add_child(camera)

	if mode != "builder":
		gamepad = Gamepad3D.new()
		if mode == "live":
			_content = LIVE_CONTENT
			gamepad.position = Vector3(0, 0, -0.4)
			gamepad.scale = Vector3.ONE * LIVE_PAD_SCALE
		else:
			gamepad.position = Vector3(-5.0, 0, 0.25)
			gamepad.scale = Vector3.ONE * 1.18
		add_child(gamepad)

	if mode != "live":
		board = BlockBoard.new()
		if mode == "builder":
			_content = BUILDER_CONTENT
			board.position = Vector3(-0.75, 0, -0.3)
		else:
			board.position = Vector3(3.75, 0, 0.1)
		add_child(board)


## Keeps the mode's content area visible on any aspect ratio (iPhone wide, iPad 4:3), below the top bar.
func _fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0:
		return
	var bar := TOP_BAR_PT / size.y          # fraction of the height used by the top bar
	var usable := size.y * (1.0 - bar)
	var aspect := size.x / usable
	var need_h := _content.y
	if aspect < _content.x / _content.y:
		need_h = _content.x / aspect
	var full_h := need_h / (1.0 - bar)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = full_h
	# Look at the content centre, shifted up so it sits below the bar.
	_look_at = Vector3(0, 0, -full_h * bar * 0.5)
	_apply_camera()


## Places the camera on a sphere around the content centre (yaw, elevation in degrees).
func _apply_camera() -> void:
	var el := deg_to_rad(_elevation)
	var yaw := deg_to_rad(_yaw)
	var offset := Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el)) * CAMERA_DISTANCE
	camera.position = _look_at + offset
	camera.look_at(_look_at, Vector3.UP)


## True while the view is turned away from the resting top-down angle.
func is_peeking() -> bool:
	return _orbiting or _yaw != 0.0 or _elevation != 90.0 - TILT_DEG


func _near_rest() -> bool:
	return absf(_yaw) < 0.5 and absf(_elevation - (90.0 - TILT_DEG)) < 0.5


func _process(delta: float) -> void:
	if _orbiting or not is_peeking() and absf(_yaw_vel) + absf(_elevation_vel) < 0.01:
		return
	# Let go: spring back to the top-down view.
	delta = minf(delta, 1.0 / 30.0)
	var y := Clay.spring(_yaw, _yaw_vel, 0.0, delta, 90.0, 13.0)
	var e := Clay.spring(_elevation, _elevation_vel, 90.0 - TILT_DEG, delta, 90.0, 13.0)
	_yaw = y.x
	_yaw_vel = y.y
	_elevation = e.x
	_elevation_vel = e.y
	if _near_rest() and absf(_yaw_vel) + absf(_elevation_vel) < 0.5:
		_yaw = 0.0
		_elevation = 90.0 - TILT_DEG
		_yaw_vel = 0.0
		_elevation_vel = 0.0
	_apply_camera()


## Screen point -> point on the table plane (y = 0.4, about the height of the controls).
func screen_to_table(pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var hit = Plane(Vector3.UP, 0.4).intersects_ray(origin, dir)
	return hit if hit != null else Vector3.ZERO


func table_to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p := screen_to_table(event.position)
		if event.pressed:
			if gamepad and gamepad.try_press(event.index, p):
				_owners[event.index] = "pad"
			elif board and board.try_press(event.index, p):
				_owners[event.index] = "board"
			elif not _owners.values().has("orbit"):
				# Empty table: this finger turns the camera to peek at the 3D shapes.
				_owners[event.index] = "orbit"
				_orbiting = true
			else:
				return
		else:
			match _owners.get(event.index, ""):
				"pad": gamepad.release(event.index)
				"board": board.release(event.index, p)
				"orbit": _orbiting = false
				_: return
			_owners.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _owners.get(event.index) == "orbit":
		_yaw -= event.relative.x * ORBIT_YAW_PER_PT
		_elevation = clampf(_elevation + event.relative.y * ORBIT_PITCH_PER_PT, ORBIT_MIN_ELEVATION, 90.0 - TILT_DEG)
		_apply_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _owners.has(event.index):
		var p := screen_to_table(event.position)
		if _owners[event.index] == "pad":
			gamepad.move(event.index, p)
		else:
			board.move(event.index, p)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if gamepad:
			gamepad.release_all()
		_owners.clear()
		_orbiting = false


# ------------------------------------------------------------------ overlay

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: Array = UiScale.safe_margins()
	margin.add_theme_constant_override("margin_left", int(m[0]) + 16)
	margin.add_theme_constant_override("margin_right", int(m[2]) + 16)
	margin.add_theme_constant_override("margin_top", int(m[1]) + 6)
	layer.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var title := Label.new()
	title.text = "Gamemote"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Clay.INK)
	row.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Clay.INK.lerp(Clay.TABLE, 0.35))
	_status.add_theme_font_size_override("font_size", 14)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_status)
	if mode == "both":
		_connect = _pill_button("Connect", _on_connect_pressed)
		row.add_child(_connect)
		row.add_child(_pill_button("Classic view", func(): get_tree().change_scene_to_file("res://ui/main.tscn")))
	else:
		row.add_child(_pill_button("Back", go_home))


func _pill_button(text: String, cb: Callable) -> Button:
	var b := Clay.pill_button(text, 40.0)
	b.pressed.connect(cb)
	return b


## Leaves a mode for Home. Pad inputs are released and the gadget is told to STOP
## (Live), or an in-app routine is stopped (Builder). The connection is kept, and a
## routine already Transferred to the device keeps running.
func go_home() -> void:
	if gamepad:
		gamepad.release_all()
	if Device.is_ready() and Device.run_mode != Device.RunMode.TRANSFER:
		if mode == "live":
			Device.stop_all()
		elif Device.run_mode == Device.RunMode.LIVE:
			Device.stop_routine()
	get_tree().change_scene_to_file(HOME_SCENE)


func _on_connect_pressed() -> void:
	if Device.state in [Device.State.READY, Device.State.CONNECTING, Device.State.RECONNECTING]:
		_auto_connect = false
		Device.disconnect_device()
	else:
		_auto_connect = true
		Device.start_scan()


## Connects to the first device found after pressing Connect.
func _on_devices(devices: Dictionary) -> void:
	if _auto_connect and Device.state == Device.State.SCANNING and not devices.is_empty():
		_auto_connect = false
		Device.connect_to(devices.keys()[0])


func _on_state(state: int) -> void:
	var text: String = Device.STATE_NAMES[state]
	if state == Device.State.READY:
		text = "Connected to %s" % Device.info.get("name", "device")
	elif state == Device.State.IDLE and Device.transport.get_kind() == "mock":
		text = "Idle (mock device)"
	elif state == Device.State.RECONNECTING:
		text = "Connection lost, reconnecting…"
	_status.text = text
	_console_state(state)
	_last_state = state
	if _connect:
		_connect.text = "Disconnect" if state in [Device.State.READY, Device.State.CONNECTING, Device.State.RECONNECTING] else "Connect"
		_connect.disabled = state == Device.State.OFF
	if state != Device.State.READY and gamepad:
		gamepad.release_all()   # lost link: let go of every control (the device fails safe)
		for index in _owners.keys():
			if _owners[index] == "pad":
				_owners.erase(index)
	_update_run_buttons()


# ------------------------------------------------------------------ bindings

## Maps the device's channels and actions onto the pad:
## stick x -> first "speed" channel, stick y -> first "angle" channel,
## top button -> first action, right button -> first "level" channel while held,
## bottom/left -> further actions.
func _on_info(info: Dictionary) -> void:
	var channels: Array = info.get("channels", [])
	var actions: Array = info.get("actions", [])
	_bindings = {"x": _first_channel(channels, "speed"), "y": _first_channel(channels, "angle"),
			"buttons": [{}, {}, {}, {}]}
	if actions.size() > 0:
		_bindings.buttons[0] = {"action": actions[0]}
	var level := _first_channel(channels, "level")
	if level >= 0:
		_bindings.buttons[1] = {"hold": _channel(level)}
	if actions.size() > 1:
		_bindings.buttons[2] = {"action": actions[1]}
	if actions.size() > 2:
		_bindings.buttons[3] = {"action": actions[2]}
	for i in 4:
		var b: Dictionary = _bindings.buttons[i]
		var text := ""
		if b.has("action"):
			text = String(b.action.name)
		elif b.has("hold"):
			text = String(b.hold.name)
		if gamepad:
			gamepad.set_button(i, text, not b.is_empty())
	if board:
		board.set_info(info)
		if board.is_empty():
			_seed_routine(info)
	_update_run_buttons()


func _first_channel(channels: Array, kind: String) -> int:
	for c in channels:
		if c.get("kind") == kind:
			return int(c.id)
	return -1


func _channel(id: int) -> Dictionary:
	for c in Device.info.get("channels", []):
		if int(c.id) == id:
			return c
	return {}


## Axis value in [-1, 1] -> channel value around its neutral.
func _axis_value(c: Dictionary, v: float) -> int:
	var neutral := float(c.neutral)
	if v >= 0.0:
		return int(round(neutral + v * (float(c.max) - neutral)))
	return int(round(neutral + v * (neutral - float(c.min))))


func _on_stick(v: Vector2) -> void:
	if not Device.is_ready() or Device.run_mode == Device.RunMode.TRANSFER:
		return
	var parts := []
	if _bindings.x >= 0:
		var xv := _axis_value(_channel(_bindings.x), v.x)
		Device.set_channel(_bindings.x, xv)
		parts.append("%s %d" % [_channel(_bindings.x).get("name", "speed"), xv])
	if _bindings.y >= 0:
		var yv := _axis_value(_channel(_bindings.y), v.y)
		Device.set_channel(_bindings.y, yv)
		parts.append("%s %d" % [_channel(_bindings.y).get("name", "angle"), yv])
	if console:
		console.update("stick", "Stick: centred" if v == Vector2.ZERO or parts.is_empty() else "Stick: " + ", ".join(parts))


func _on_button(i: int, pressed: bool) -> void:
	if not Device.is_ready():
		return
	var b: Dictionary = _bindings.buttons[i]
	if b.has("action") and pressed:
		var params := []
		for p in b.action.get("params", []):
			params.append(int(p.get("default", p.get("min", 0))))
		Device.trigger(int(b.action.id), params)
		if console:
			console.add("Sent: %s" % b.action.name, "command")
	elif b.has("hold") and Device.run_mode != Device.RunMode.TRANSFER:
		Device.set_channel(int(b.hold.id), int(b.hold.max) if pressed else int(b.hold.neutral))
		if console:
			console.add(("Holding: %s" if pressed else "Let go: %s") % b.hold.name, "command")


func _on_stop() -> void:
	if Device.is_ready():
		Device.stop_routine()
		Device.stop_all()
		if console:
			console.add("STOP sent: everything back to neutral", "command")
	if board:
		board.set_highlight(null)


# ------------------------------------------------------------------ console (live mode)

func _console_state(state: int) -> void:
	if console == null:
		return
	match state:
		Device.State.OFF:
			console.add("Bluetooth is off", "error")
		Device.State.IDLE:
			if _last_state in [Device.State.CONNECTING, Device.State.RECONNECTING]:
				console.add("Lost the connection to the gadget", "error")
			elif _last_state == Device.State.READY:
				console.add("Disconnected", "status")
			else:
				console.add("Not connected", "status")
		Device.State.SCANNING:
			console.add("Looking for gadgets…", "status")
		Device.State.CONNECTING:
			console.add("Connecting…", "status")
		Device.State.READY:
			console.add("Connected to %s" % Device.info.get("name", "the gadget"), "status")
		Device.State.RECONNECTING:
			console.add("Connection lost, reconnecting…", "error")


## Plain words for a device error status (no codes shown to the player).
func _status_words(status: int) -> String:
	match status:
		GmProtocol.BUSY:
			return "The gadget is busy, try again"
		GmProtocol.BAD_PROGRAM:
			return "The gadget could not understand that routine"
		_:
			return "The gadget could not do that"


func _on_command_failed(status: int) -> void:
	console.add(_status_words(status), "error")


## Device log lines: only the gadget's own messages and connection problems are shown.
func _on_device_log(line: String) -> void:
	var text := line.substr(line.find("  ") + 2) if line.find("  ") >= 0 else line
	if text.begins_with("[device] "):
		console.add("Gadget says: " + text.substr(9), "feedback")
	elif text.begins_with("Connect failed"):
		console.add("Could not connect to the gadget", "error")
	elif text.begins_with("Connect timed out"):
		console.add("Connecting took too long", "error")
	elif text.begins_with("Cannot scan"):
		console.add("Cannot look for gadgets yet", "error")


func _on_telemetry(flags: int, _step: int, values: Array) -> void:
	if flags & GmProtocol.FLAG_FAILSAFE_TRIPPED:
		console.update("failsafe", "The gadget stopped itself (it lost contact)", "error")
	var parts := []
	var channels: Array = Device.info.get("channels", [])
	for i in mini(values.size(), channels.size()):
		parts.append("%s %d" % [channels[i].get("name", "channel"), int(values[i])])
	if not parts.is_empty():
		console.update("telemetry", "Gadget reports: " + ", ".join(parts), "feedback")


func _on_routine_console(mode: int, state: int, _block: Variant) -> void:
	var where := "in the app" if mode == Device.RunMode.LIVE else "on the gadget"
	match state:
		GmProtocol.RS_RUNNING:
			if console.size() == 0 or not console.get_lines().back().text.begins_with("Routine running"):
				console.add("Routine running %s" % where, "feedback")
		GmProtocol.RS_FINISHED:
			console.add("Routine finished", "feedback")
		GmProtocol.RS_STOPPED:
			console.add("Routine stopped", "feedback")
		GmProtocol.RS_ERROR:
			console.add("The routine hit a problem on the gadget", "error")


# ------------------------------------------------------------------ routines

## A first routine so the board is never empty: wave the angle channel, then an action.
func _seed_routine(info: Dictionary) -> void:
	var angle := _first_channel(info.get("channels", []), "angle")
	if angle < 0:
		return
	var c := _channel(angle) if Device.is_ready() else {}
	for ch in info.get("channels", []):
		if int(ch.id) == angle:
			c = ch
	var rep := board.add_block({"op": "repeat", "times": 3, "body": []})
	board.add_block({"op": "set", "ch": angle, "value": int(c.max)}, rep)
	board.add_block({"op": "wait", "ms": 500}, rep)
	board.add_block({"op": "set", "ch": angle, "value": int(c.min)}, rep)
	board.add_block({"op": "wait", "ms": 500}, rep)
	var actions: Array = info.get("actions", [])
	if not actions.is_empty():
		var params := []
		for p in actions[0].get("params", []):
			params.append(int(p.get("default", p.get("min", 0))))
		board.add_block({"op": "trigger", "action": int(actions[0].id), "params": params})


func _update_run_buttons() -> void:
	if not board:
		return
	var ready := Device.is_ready()
	var busy: bool = Device.run_mode != Device.RunMode.NONE
	board.set_run_enabled(ready and not busy, ready and not busy and Device.supports_transfer(), ready and busy)
	if not ready:
		board.set_status("Connect to run routines")
	elif not busy:
		board.set_status("Tap a block to change it · drag to the palette to delete")


func _on_run(mode: String) -> void:
	match mode:
		"live":
			var err: String = Device.run_live(board.to_ast())
			if err != "":
				board.set_status("Error: " + err)
		"transfer":
			board.set_status("Uploading…")
			var err: String = await Device.run_transferred(board.to_ast())
			board.set_status(("Error: " + err) if err != "" else "Running on the device")
		"stop":
			Device.stop_routine()
			board.set_highlight(null)
	_update_run_buttons()


func _on_routine(mode: int, state: int, block_id: Variant) -> void:
	var where := "in the app" if mode == Device.RunMode.LIVE else "on the device"
	match state:
		GmProtocol.RS_RUNNING:
			board.set_highlight(block_id)
			board.set_status("Running %s" % where)
		GmProtocol.RS_FINISHED, GmProtocol.RS_STOPPED:
			board.set_highlight(null)
			board.set_status("Finished %s" % where if state == GmProtocol.RS_FINISHED else "Stopped")
		GmProtocol.RS_ERROR:
			board.set_highlight(null)
			board.set_status("Error on the device")
	_update_run_buttons()
