extends SceneTree
## Headless test runner (no addons needed):
##   godot --headless --path app --import
##   godot --headless --path app -s res://tests/run_tests.gd
## Exits with code 1 on any failure.

var _failures := 0
var _passes := 0
var _context := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vectors := _load_vectors()
	if vectors.is_empty():
		_fail("could not load protocol/test_vectors.json")
	else:
		_test_crc(vectors)
		_test_frames(vectors)
		_test_routines(vectors)
	_test_mock_device()
	await _test_extension()
	await _test_device_service()
	await _test_main_ui()
	await _test_table()
	print("\n%d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------ helpers

func _load_vectors() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../protocol/test_vectors.json")
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	return _ints(data) if typeof(data) == TYPE_DICTIONARY else {}


## JSON numbers are floats in Godot; turn whole numbers back into ints.
func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(_ints(x))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _ints(v[k])
			return out
	return v


func _unhex(s: String) -> PackedByteArray:
	return s.replace(" ", "").hex_decode()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fail(what)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_passes += 1
	elif str(actual) == str(expected):
		_passes += 1  # e.g. int vs float of the same whole value
	else:
		_fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


func _fail(what: String) -> void:
	_failures += 1
	printerr("FAIL [%s] %s" % [_context, what])


# ------------------------------------------------------------------ protocol

func _test_crc(vectors: Dictionary) -> void:
	_context = "crc"
	for v in vectors.crc:
		_eq(GmProtocol.crc16(String(v.data_ascii).to_ascii_buffer()), v.crc, v.data_ascii)


func _test_frames(vectors: Dictionary) -> void:
	_context = "frames"
	for v in vectors.frames:
		var expected: Dictionary = v.frame
		_eq(GmProtocol.encode_from_dict(expected).hex_encode(), v.hex, "encode " + v.name)
		var d := GmProtocol.decode(_unhex(v.hex))
		_check(d.ok, "decode ok " + v.name)
		for key in expected:
			var actual = d.get("name") if key == "type" else d.get(key)
			_eq(actual, expected[key], "decode %s.%s" % [v.name, key])
	for v in vectors.invalid_frames:
		_check(not GmProtocol.decode(_unhex(v.hex)).ok, "reject " + v.name)

	var program := _unhex(vectors.routines[0].program_hex)
	var frames := GmProtocol.encode_routine_upload(10, 0, program)
	_eq(frames[0].hex_encode(), "100a002300", "upload begin")
	var rebuilt := PackedByteArray()
	for i in range(1, frames.size() - 1):
		rebuilt.append_array(String(GmProtocol.decode(frames[i]).data).hex_decode())
		_check(frames[i].size() <= GmProtocol.MAX_FRAME, "chunk fits 20 bytes")
	_eq(rebuilt, program, "upload chunks rebuild program")
	_eq(GmProtocol.decode(frames[-1]).crc, vectors.routines[0].crc, "upload crc")


# ------------------------------------------------------------------ routines

func _test_routines(vectors: Dictionary) -> void:
	_context = "routines"
	var dev: Dictionary = vectors.test_device
	for r in vectors.routines:
		var c := GmRoutine.compile(r.ast)
		_check(c.ok, "compile " + r.name)
		_eq(c.program.hex_encode(), String(r.program_hex).replace(" ", ""), "bytes " + r.name)
		_eq(c.program.size(), r.length, "length " + r.name)
		_eq(GmProtocol.crc16(c.program), r.crc, "crc " + r.name)
		_eq(c.step_blocks, r.step_blocks, "step map " + r.name)

		var parsed := GmRoutine.parse(_unhex(r.program_hex), dev.channel_ids, dev.action_ids, dev.max_loop_depth)
		_check(parsed.ok, "parse " + r.name)
		var events := []
		var now := [0]
		var vm := GmRoutine.VM.new(parsed.instrs,
				func(ch, v): events.append([now[0], "set", ch, v]),
				func(a, p): events.append([now[0], "trigger", a, p]),
				func(): events.append([now[0], "stop_all"]))
		vm.start(0)
		var finished_at = null
		var limit: int = r.get("trace_until_ms", 10000)
		while now[0] <= limit:
			vm.tick(now[0])
			if vm.finished:
				finished_at = now[0]
				break
			now[0] += 10
		_eq(events, r.trace, "trace " + r.name)
		_eq(finished_at, r.finished_at_ms, "finished_at " + r.name)

	for v in vectors.invalid_programs:
		var parsed := GmRoutine.parse(_unhex(v.hex), dev.channel_ids, dev.action_ids, dev.max_loop_depth)
		_check(not parsed.ok, "reject program " + v.name)


# ------------------------------------------------------------------ mock device

func _decode_all(frames: Array) -> Array:
	var out := []
	for f in frames:
		out.append(GmProtocol.decode(f))
	return out


func _test_mock_device() -> void:
	_context = "mock device"
	var d := GmMockDevice.new()
	d.on_connect(0)
	d.handle_cmd(GmProtocol.encode_set(0, [[2, 999]]), 0)
	_eq(d.values[2], 180, "SET clamps to max")
	d.tick(400)
	_eq(d.values[2], 180, "value held before failsafe")
	d.tick(501)
	_eq(d.values[2], 90, "failsafe returns to neutral")

	var acks := _decode_all(d.handle_cmd(GmProtocol.encode_trigger(7, 1, [100]), 600))
	_eq(acks[0].status, GmProtocol.OK, "trigger ack")
	acks = _decode_all(d.handle_cmd(GmProtocol.encode_trigger(8, 9), 600))
	_eq(acks[0].status, GmProtocol.BAD_ID, "unknown action")

	var ast := {"blocks": [
		{"id": "a", "op": "set", "ch": 2, "value": 0},
		{"id": "b", "op": "repeat", "times": 2, "body": [
			{"id": "c", "op": "set", "ch": 2, "value": 180},
			{"id": "d", "op": "wait", "ms": 500},
		]},
	]}
	var program: PackedByteArray = GmRoutine.compile(ast).program
	var statuses := []
	for f in GmProtocol.encode_routine_upload(20, 0, program):
		for r in _decode_all(d.handle_cmd(f, 1000)):
			statuses.append(r.status)
	_eq(statuses, [GmProtocol.OK, GmProtocol.OK], "upload acks")
	var run := _decode_all(d.handle_cmd(GmProtocol.encode_routine_run(30, 0), 1000))
	_eq(run[0].status, GmProtocol.OK, "run ack")
	d.tick(1000)
	_eq(d.values[2], 180, "routine sets value")
	d.on_disconnect(1100)
	d.tick(1700)
	_check(d.routine_running(), "transferred routine survives disconnect")
	_eq(d.values[2], 180, "no failsafe during transferred routine")
	d.tick(2000)
	_check(not d.routine_running(), "routine finishes")
	_eq(d.values[2], 90, "neutral after routine")

	var bad := GmProtocol.encode_routine_upload(40, 0, program)
	bad[-1] = GmProtocol.encode_routine_end(99, 0)
	statuses.clear()
	for f in bad:
		for r in _decode_all(d.handle_cmd(f, 3000)):
			statuses.append(r.status)
	_eq(statuses, [GmProtocol.OK, GmProtocol.BAD_PROGRAM], "bad CRC rejected")


# ------------------------------------------------------------------ native extension

func _test_extension() -> void:
	_context = "extension"
	if not ClassDB.class_exists("GamemoteBle"):
		print("SKIP extension tests: GamemoteBle not loaded (build native/gamemote_ble first)")
		return
	var ble = ClassDB.instantiate("GamemoteBle")
	_check(ble != null, "instantiate GamemoteBle")
	print("  GamemoteBle backend: %s" % ble.get_backend_name())
	var states := []
	ble.connect("adapter_state_changed", func(s): states.append(s))
	ble.initialize()
	# The CoreBluetooth backend reports asynchronously; the stub reports at once.
	_check(await _wait_until(func(): ble.poll(); return states.size() > 0, 3000),
			"initialize reports adapter state")
	print("  adapter state: %s" % str(states))
	if ble.get_backend_name() == "corebluetooth":
		# Godot's own binary has no NSBluetoothAlwaysUsageDescription: the backend must
		# report that instead of touching CoreBluetooth (which would crash the process).
		var bundle_has_key: bool = states[0] != 6
		print("  usage description present in this binary's Info.plist: %s" % bundle_has_key)
	if ble.get_backend_name() == "stub":
		_eq(states[0], 2, "stub reports unsupported")
		_check(not ble.is_supported(), "stub is not supported")
		_check(not ble.write(GmProtocol.CMD_UUID, PackedByteArray([1, 2]), false), "stub write fails")


# ------------------------------------------------------------------ device service (mock transport)

func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not cond.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _test_device_service() -> void:
	_context = "device service"
	var svc: Node = load("res://core/device_service.gd").new()
	root.add_child(svc)
	svc.use_transport("mock")
	var mock: GmMockTransport = svc.transport
	_check(await _wait_until(func(): return svc.state == svc.State.IDLE, 1000), "mock adapter ready")
	svc.start_scan()
	_check(await _wait_until(func(): return svc.devices.has(GmMockTransport.DEVICE_ID), 2000), "scan finds mock")
	svc.connect_to(GmMockTransport.DEVICE_ID)
	_check(await _wait_until(func(): return svc.is_ready(), 2000), "connects")
	_eq(svc.info.get("name"), "Gamemote Mock", "info read")

	svc.set_channel(2, 150)
	_check(await _wait_until(func(): return mock.device.values[2] == 150, 1000), "live SET reaches device")
	var rtt := [-1]
	svc.rtt_updated.connect(func(p50, _p95): rtt[0] = p50)
	_check(await _wait_until(func(): return rtt[0] >= 0, 2000), "PING/PONG round trip measured")
	await _wait_until(func(): return false, 800)  # keepalive must prevent failsafe
	_eq(mock.device.values[2], 150, "keepalive holds value past failsafe window")
	svc.stop_all()
	_check(await _wait_until(func(): return mock.device.values[2] == 90, 1000), "STOP_ALL neutralises")

	var ast := {"version": 0, "name": "t", "blocks": [
		{"id": "x1", "op": "set", "ch": 2, "value": 10},
		{"id": "x2", "op": "wait", "ms": 200},
		{"id": "x3", "op": "set", "ch": 2, "value": 170},
		{"id": "x4", "op": "wait", "ms": 200},
	]}
	_eq(svc.run_live(ast), "", "run_live starts")
	_check(await _wait_until(func(): return mock.device.values[2] == 170, 1500), "live routine drives device")
	_check(await _wait_until(func(): return svc.run_mode == svc.RunMode.NONE, 1500), "live routine finishes")
	_check(await _wait_until(func(): return mock.device.values[2] == 90, 1000), "neutral after live routine")

	var err: String = await svc.run_transferred(ast)
	_eq(err, "", "run_transferred uploads and starts")
	_check(mock.device.routine_running(), "routine running on device")
	mock.simulate_link_loss()
	_check(mock.device.routine_running(), "transferred routine keeps running after link loss")
	_check(await _wait_until(func(): return not mock.device.routine_running(), 2000), "transferred routine finishes offline")
	_eq(svc.state, svc.State.RECONNECTING, "service tries to reconnect")
	_check(await _wait_until(func(): return svc.is_ready(), 3000), "auto-reconnects")

	svc.set_channel(3, 50)
	_check(await _wait_until(func(): return mock.device.values[3] == 50, 1000), "control after reconnect")
	mock.simulate_link_loss()
	_eq(mock.device.values[3], 0, "device neutral on link loss (live mode)")
	_check(await _wait_until(func(): return svc.is_ready(), 3000), "auto-reconnects again")

	err = await svc.run_transferred(ast)
	_eq(err, "", "second transfer")
	svc.disconnect_device()
	_check(mock.device.routine_running(), "Disconnect button leaves a transferred routine running")
	_check(await _wait_until(func(): return not mock.device.routine_running(), 2000), "it finishes on its own")
	_eq(svc.state, svc.State.IDLE, "user disconnect does not auto-reconnect")
	svc.queue_free()
	await process_frame


# ------------------------------------------------------------------ tracer UI smoke test

func _test_main_ui() -> void:
	_context = "main ui"
	var device: Node = root.get_node("Device")
	device.use_transport("mock")
	var ui: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui._on_scan_pressed()
	_check(await _wait_until(func(): return ui._device_list.item_count == 1, 2000), "device listed")
	ui._on_connect_pressed()
	_check(await _wait_until(func(): return device.is_ready(), 2000), "connect from UI")
	await process_frame
	_eq(ui._sliders.size(), 3, "one slider per channel")
	_check(ui._controls_box.visible, "controls visible when connected")
	ui._sliders[1].value = 200
	var mock: GmMockTransport = device.transport
	_check(await _wait_until(func(): return mock.device.values[1] == 200, 1000), "slider drives channel")
	ui._on_stop_pressed()
	_check(await _wait_until(func(): return mock.device.values[1] == 0, 1000), "STOP button")
	_eq(ui._sliders[1].value, 0.0, "sliders reset on STOP")
	ui._on_run_live()
	_check(ui._routine_status.text.begins_with("Running in the app"), "live status shown")
	_check(await _wait_until(func(): return ui._routine_status.text.begins_with("Finished"), 9000), "live demo finishes")
	ui._on_run_transfer()
	_check(await _wait_until(func(): return ui._routine_status.text.contains("device (transferred)"), 2000), "transfer status shown")
	_check(await _wait_until(func(): return ui._routine_status.text.begins_with("Finished"), 9000), "transferred demo finishes")
	device.disconnect_device()
	await process_frame
	_check(not ui._controls_box.visible, "controls hidden after disconnect")
	ui.queue_free()
	await process_frame


# ------------------------------------------------------------------ 3D table (real touch events)

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func _drag_to(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	root.push_input(e, true)


func _test_table() -> void:
	_context = "3d table"
	var device: Node = root.get_node("Device")
	device.use_transport("mock")
	var table: Node3D = load("res://ui/table/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	table._on_connect_pressed()
	_check(await _wait_until(func(): return device.is_ready(), 3000), "Connect auto-connects to the first device")
	await process_frame
	var mock: GmMockTransport = device.transport
	var pad: Gamepad3D = table.gamepad
	var board: BlockBoard = table.board

	# Screen <-> table mapping round-trips.
	var stick: Vector3 = pad.stick_center_world()
	var stick_px: Vector2 = table.table_to_screen(stick)
	_check((table.screen_to_table(stick_px) - Vector3(stick.x, 0.4, stick.z)).length() < 0.3, "screen to table mapping")

	# Stick up (towards screen top) -> angle channel to max.
	_touch(0, stick_px, true)
	_drag_to(0, table.table_to_screen(stick + Vector3(0, 0, -1.2)))
	_check(await _wait_until(func(): return mock.device.values[2] == 180, 1000), "stick up drives Servo to max")
	# Second finger holds the right button (LED momentary) while the stick is held.
	var led_px: Vector2 = table.table_to_screen(pad.button_center_world(1))
	_touch(1, led_px, true)
	_check(await _wait_until(func(): return mock.device.values[1] == 255, 1000), "second finger holds LED on (multitouch)")
	_check(mock.device.values[2] == 180, "stick still held during second touch")
	_touch(1, led_px, false)
	_touch(0, table.table_to_screen(stick + Vector3(0, 0, -1.2)), false)
	_check(await _wait_until(func(): return mock.device.values[1] == 0 and mock.device.values[2] == 90, 1000),
			"releasing both returns channels to neutral")

	# The board starts with a seeded routine that compiles.
	_check(board.chain.size() == 2, "seeded routine: repeat + action")
	_check(GmRoutine.compile(board.to_ast()).ok, "board compiles")

	# Drag a Wait tile from the palette into the end of the chain.
	var palette_wait := -1
	for i in board._palette.size():
		if board._palette[i].proto.op == "wait":
			palette_wait = i
	var before: int = board.chain.size()
	var target: Vector3 = board.slot_world("", before)
	_touch(0, table.table_to_screen(board.palette_center_world(palette_wait)), true)
	_drag_to(0, table.table_to_screen(target + Vector3(0, 0.4, 0)))
	_touch(0, table.table_to_screen(target + Vector3(0, 0.4, 0)), false)
	await process_frame
	_eq(board.chain.size(), before + 1, "palette drag snaps a new block at the end")
	var new_id: String = board.chain[-1]
	_eq(board.blocks[new_id].op, "wait", "snapped block is a Wait")

	# Tap it: 500 ms -> 1000 ms.
	var block_px: Vector2 = table.table_to_screen(board.block_center_world(new_id))
	_touch(0, block_px, true)
	_touch(0, block_px, false)
	await process_frame
	_eq(board.blocks[new_id].ms, 1000, "tap cycles the Wait value")

	# Drag it back onto the palette: deleted.
	_touch(0, block_px, true)
	_drag_to(0, table.table_to_screen(board.palette_center_world(0)))
	_touch(0, table.table_to_screen(board.palette_center_world(0)), false)
	await process_frame
	_eq(board.chain.size(), before, "dragging to the palette deletes")

	# Run live from the 3D button; the running block glows, then it finishes.
	var live_px: Vector2 = table.table_to_screen(board.run_button_world("live"))
	_touch(0, live_px, true)
	_touch(0, live_px, false)
	_check(await _wait_until(func(): return board._highlight != null, 1500), "running block is highlighted")
	_check(await _wait_until(func(): return device.run_mode == device.RunMode.NONE, 6000), "live routine finishes")

	# STOP on the pad neutralises everything.
	device.set_channel(3, 60)
	await _wait_until(func(): return mock.device.values[3] == 60, 1000)
	var stop_px: Vector2 = table.table_to_screen(pad.button_center_world(-1))
	_touch(0, stop_px, true)
	_touch(0, stop_px, false)
	_check(await _wait_until(func(): return mock.device.values[3] == 0, 1000), "STOP button neutralises")

	device.disconnect_device()
	table.queue_free()
	await process_frame
