extends Control
## Tracer-bullet screen (milestone M2): connect to a device, drive its channels and
## actions, watch telemetry and round-trip time, and run a demo routine in both
## modes. The real controller UI (M4) and block editor (M5) replace this later.

const LOG_LINES := 200

var _margin: MarginContainer
var _state_label: Label
var _transport_select: OptionButton
var _scan_button: Button
var _device_list: ItemList
var _connect_button: Button
var _disconnect_button: Button
var _rtt_label: Label
var _log: RichTextLabel
var _log_lines: PackedStringArray = []

var _device_title: Label
var _controls_box: VBoxContainer
var _channel_grid: GridContainer
var _actions_box: HFlowContainer
var _stop_button: Button
var _telemetry_label: Label
var _routine_label: Label
var _run_live_button: Button
var _run_transfer_button: Button
var _stop_routine_button: Button
var _routine_status: Label
var _sliders := {}        # channel id -> HSlider
var _value_labels := {}   # channel id -> Label
var _demo_ast := {}
var _demo_descriptions := {}  # block id -> text


func _ready() -> void:
	theme = _make_theme()
	_build()
	Device.state_changed.connect(_on_state_changed)
	Device.log_added.connect(_on_log)
	Device.devices_changed.connect(_on_devices_changed)
	Device.info_changed.connect(_on_info_changed)
	Device.telemetry_received.connect(_on_telemetry)
	Device.rtt_updated.connect(_on_rtt)
	Device.routine_changed.connect(_on_routine_changed)
	UiScale.changed.connect(func(_s): _apply_safe_area())
	get_window().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_select_transport_item()
	_on_state_changed(Device.state)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 10)
	return t


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)  # Apple's minimum touch target
	b.pressed.connect(on_pressed)
	return b


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.6)
	return l


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("16181d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_margin.add_child(columns)

	# ---- left: connection + log
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	columns.add_child(left)

	var header := HBoxContainer.new()
	left.add_child(header)
	var title := Label.new()
	title.text = "Gamemote"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	_state_label = Label.new()
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_state_label.modulate = Color(1, 1, 1, 0.75)
	header.add_child(_state_label)
	var table_button := _button("Table view", func(): get_tree().change_scene_to_file("res://ui/table/table.tscn"))
	header.add_child(table_button)

	var row := HBoxContainer.new()
	left.add_child(row)
	_transport_select = OptionButton.new()
	_transport_select.custom_minimum_size = Vector2(0, 44)
	_transport_select.add_item("Bluetooth", 0)
	_transport_select.add_item("Mock device", 1)
	_transport_select.set_item_disabled(0, not GmBleTransport.is_available())
	_transport_select.item_selected.connect(_on_transport_selected)
	row.add_child(_transport_select)
	_scan_button = _button("Scan", _on_scan_pressed)
	_scan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_scan_button)

	_device_list = ItemList.new()
	_device_list.custom_minimum_size = Vector2(0, 60)
	_device_list.item_activated.connect(func(_i): _on_connect_pressed())
	left.add_child(_device_list)

	row = HBoxContainer.new()
	left.add_child(row)
	_connect_button = _button("Connect", _on_connect_pressed)
	_connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_connect_button)
	_disconnect_button = _button("Disconnect", func(): Device.disconnect_device())
	_disconnect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_disconnect_button)

	_rtt_label = Label.new()
	_rtt_label.text = "Round trip: -"
	left.add_child(_rtt_label)

	left.add_child(_section("LOG"))
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 11)
	left.add_child(_log)

	# ---- right: device controls
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)

	_device_title = Label.new()
	_device_title.add_theme_font_size_override("font_size", 18)
	right.add_child(_device_title)

	_controls_box = VBoxContainer.new()
	right.add_child(_controls_box)

	_controls_box.add_child(_section("CHANNELS (live control)"))
	_channel_grid = GridContainer.new()
	_channel_grid.columns = 3
	_controls_box.add_child(_channel_grid)

	_controls_box.add_child(_section("ACTIONS"))
	_actions_box = HFlowContainer.new()
	_controls_box.add_child(_actions_box)

	_stop_button = _button("STOP", _on_stop_pressed)
	_stop_button.custom_minimum_size = Vector2(0, 56)
	_stop_button.add_theme_color_override("font_color", Color("ff5a5a"))
	_stop_button.add_theme_font_size_override("font_size", 22)
	_controls_box.add_child(_stop_button)

	_controls_box.add_child(_section("TELEMETRY"))
	_telemetry_label = Label.new()
	_controls_box.add_child(_telemetry_label)

	_controls_box.add_child(_section("DEMO ROUTINE"))
	_routine_label = Label.new()
	_routine_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_box.add_child(_routine_label)
	row = HBoxContainer.new()
	_controls_box.add_child(row)
	_run_live_button = _button("Run live", _on_run_live)
	_run_transfer_button = _button("Transfer & run", _on_run_transfer)
	_stop_routine_button = _button("Stop routine", func(): Device.stop_routine())
	for b in [_run_live_button, _run_transfer_button, _stop_routine_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_routine_status = Label.new()
	_routine_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_box.add_child(_routine_status)


func _apply_safe_area() -> void:
	var m: Array = UiScale.safe_margins()
	_margin.add_theme_constant_override("margin_left", int(m[0]) + 16)
	_margin.add_theme_constant_override("margin_top", int(m[1]) + 12)
	_margin.add_theme_constant_override("margin_right", int(m[2]) + 16)
	_margin.add_theme_constant_override("margin_bottom", int(m[3]) + 12)


func _select_transport_item() -> void:
	_transport_select.select(0 if Device.transport.get_kind() == "ble" else 1)


# ------------------------------------------------------------------ connection UI

func _on_transport_selected(index: int) -> void:
	Device.use_transport("ble" if index == 0 else "mock")


func _on_scan_pressed() -> void:
	if Device.state == Device.State.SCANNING:
		Device.stop_scan()
	else:
		Device.start_scan()


func _on_connect_pressed() -> void:
	var selected := _device_list.get_selected_items()
	var index := selected[0] if selected.size() > 0 else (0 if _device_list.item_count == 1 else -1)
	if index < 0:
		Device.log_line("Select a device first")
		return
	Device.connect_to(_device_list.get_item_metadata(index))


func _on_state_changed(state: int) -> void:
	_state_label.text = Device.STATE_NAMES[state]
	var idle := state in [Device.State.IDLE, Device.State.SCANNING]
	_scan_button.disabled = not idle
	_scan_button.text = "Stop scan" if state == Device.State.SCANNING else "Scan"
	_connect_button.disabled = not idle or _device_list.item_count == 0
	_disconnect_button.disabled = state not in [Device.State.CONNECTING, Device.State.READY, Device.State.RECONNECTING]
	_controls_box.visible = state == Device.State.READY
	if state != Device.State.READY:
		_device_title.text = "Not connected" if state != Device.State.RECONNECTING else "Reconnecting..."
		_rtt_label.text = "Round trip: -"
	_update_routine_buttons()


func _on_devices_changed(devices: Dictionary) -> void:
	var selected_id = null
	var sel := _device_list.get_selected_items()
	if sel.size() > 0:
		selected_id = _device_list.get_item_metadata(sel[0])
	_device_list.clear()
	for id in devices:
		var i := _device_list.add_item("%s   %d dBm" % [devices[id].name, devices[id].rssi])
		_device_list.set_item_metadata(i, id)
		if id == selected_id:
			_device_list.select(i)
	_on_state_changed(Device.state)


func _on_log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_LINES)
	_log.text = "\n".join(_log_lines)


func _on_rtt(p50: int, p95: int) -> void:
	_rtt_label.text = "Round trip: p50 %d ms, p95 %d ms" % [p50, p95]


# ------------------------------------------------------------------ device UI

func _on_info_changed(info: Dictionary) -> void:
	_device_title.text = "%s  (fw %s)" % [info.get("name", "?"), info.get("fw", "?")]
	for child in _channel_grid.get_children():
		child.queue_free()
	for child in _actions_box.get_children():
		child.queue_free()
	_sliders.clear()
	_value_labels.clear()

	for c in info.get("channels", []):
		var ch := int(c.id)
		var name_label := Label.new()
		name_label.text = String(c.name)
		name_label.custom_minimum_size = Vector2(64, 0)
		_channel_grid.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = c.min
		slider.max_value = c.max
		slider.step = 1
		slider.value = c.neutral
		slider.custom_minimum_size = Vector2(160, 36)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v): _on_slider(ch, int(v)))
		_channel_grid.add_child(slider)
		var value_label := Label.new()
		value_label.text = str(int(c.neutral))
		value_label.custom_minimum_size = Vector2(44, 0)
		_channel_grid.add_child(value_label)
		_sliders[ch] = slider
		_value_labels[ch] = value_label

	for a in info.get("actions", []):
		var params := []
		for p in a.get("params", []):
			params.append(int(p.get("default", p.get("min", 0))))
		var action_id := int(a.id)
		var b := _button(String(a.name), func(): Device.trigger(action_id, params))
		b.custom_minimum_size = Vector2(96, 44)
		_actions_box.add_child(b)

	_build_demo_routine(info)
	_update_routine_buttons()


func _on_slider(ch: int, value: int) -> void:
	_value_labels[ch].text = str(value)
	Device.set_channel(ch, value)


func _reset_sliders() -> void:
	for c in Device.info.get("channels", []):
		var ch := int(c.id)
		if _sliders.has(ch):
			_sliders[ch].set_value_no_signal(c.neutral)
			_value_labels[ch].text = str(int(c.neutral))


func _on_stop_pressed() -> void:
	Device.stop_all()
	_reset_sliders()


func _on_telemetry(flags: int, step: int, values: Array) -> void:
	var parts := []
	var names: Array = Device.info.get("telemetry", [])
	for i in values.size():
		parts.append("%s %d" % [names[i].name if i < names.size() else "v%d" % i, values[i]])
	var f := []
	if flags & GmProtocol.FLAG_LIVE_ACTIVE:
		f.append("live")
	if flags & GmProtocol.FLAG_ROUTINE_RUNNING:
		f.append("routine step %d" % step)
	if flags & GmProtocol.FLAG_FAILSAFE_TRIPPED:
		f.append("FAILSAFE")
	_telemetry_label.text = "%s   [%s]" % ["  ".join(parts), ", ".join(f) if not f.is_empty() else "idle"]


# ------------------------------------------------------------------ demo routine

## Builds "wave the first angle channel 3 times, then fire the first action".
func _build_demo_routine(info: Dictionary) -> void:
	var channels: Array = info.get("channels", [])
	_demo_ast = {}
	_demo_descriptions = {}
	if channels.is_empty():
		_routine_label.text = "This device has no channels."
		return
	var c: Dictionary = channels[0]
	for candidate in channels:
		if candidate.get("kind") == "angle":
			c = candidate
			break
	var ch := int(c.id)
	var lo := int(c.min)
	var hi := int(c.max)
	var blocks := [
		{"id": "b1", "op": "set", "ch": ch, "value": lo},
		{"id": "b2", "op": "repeat", "times": 5, "body": [
			{"id": "b3", "op": "set", "ch": ch, "value": hi},
			{"id": "b4", "op": "wait", "ms": 500},
			{"id": "b5", "op": "set", "ch": ch, "value": lo},
			{"id": "b6", "op": "wait", "ms": 500},
		]},
	]
	_demo_descriptions = {
		"b1": "set %s to %d" % [c.name, lo], "b2": "repeat 5 times",
		"b3": "set %s to %d" % [c.name, hi], "b4": "wait 0.5 s",
		"b5": "set %s to %d" % [c.name, lo], "b6": "wait 0.5 s",
	}
	var actions: Array = info.get("actions", [])
	if not actions.is_empty():
		var a: Dictionary = actions[0]
		var params := []
		for p in a.get("params", []):
			params.append(int(p.get("default", p.get("min", 0))))
		blocks.append({"id": "b7", "op": "trigger", "action": int(a.id), "params": params})
		_demo_descriptions["b7"] = "trigger %s" % a.name
	_demo_ast = {"version": 0, "name": "Demo wave", "blocks": blocks}
	_routine_label.text = "Wave %s %d→%d five times (~5 s)%s." % [c.name, lo, hi,
			", then %s" % actions[0].name if not actions.is_empty() else ""]
	_routine_status.text = ""


func _update_routine_buttons() -> void:
	if _run_live_button == null:
		return
	var ready: bool = Device.is_ready() and not _demo_ast.is_empty()
	var busy: bool = Device.run_mode != Device.RunMode.NONE
	_run_live_button.disabled = not ready or busy
	_run_transfer_button.disabled = not ready or busy or not Device.supports_transfer()
	_run_transfer_button.tooltip_text = "" if Device.supports_transfer() else "This device only supports live routines"
	_stop_routine_button.disabled = not Device.is_ready() or not busy
	for s in _sliders.values():
		s.editable = Device.run_mode != Device.RunMode.TRANSFER


func _on_run_live() -> void:
	var err: String = Device.run_live(_demo_ast)
	if err != "":
		_routine_status.text = "Error: " + err
	_update_routine_buttons()


func _on_run_transfer() -> void:
	_routine_status.text = "Uploading..."
	_run_transfer_button.disabled = true
	var err: String = await Device.run_transferred(_demo_ast)
	_routine_status.text = ("Error: " + err) if err != "" else "Running on the device. You can disconnect; it keeps going."
	_update_routine_buttons()


func _on_routine_changed(mode: int, state: int, block_id: Variant) -> void:
	var where := "app (live)" if mode == Device.RunMode.LIVE else "device (transferred)"
	match state:
		GmProtocol.RS_RUNNING:
			var what: String = _demo_descriptions.get(block_id, "") if block_id != null else ""
			_routine_status.text = "Running in the %s%s" % [where, (": " + what) if what != "" else ""]
		GmProtocol.RS_FINISHED:
			_routine_status.text = "Finished (%s)" % where
			_reset_sliders()
		GmProtocol.RS_STOPPED:
			_routine_status.text = "Stopped (%s)" % where
			_reset_sliders()
		GmProtocol.RS_ERROR:
			_routine_status.text = "Error on the device"
	_update_routine_buttons()
