extends Control
## Home: shows the connection, lets the player connect, and offers the two modes
## (Live and Routine builder). The modes stay disabled, with a plain reason, until the
## gadget is connected. Navigation only: the connection lives in the `Device` autoload
## and survives scene changes.

const LIVE_SCENE := "res://ui/live/live_mode.tscn"
const BUILDER_SCENE := "res://ui/builder/builder_mode.tscn"
const CLASSIC_SCENE := "res://ui/main.tscn"
const TILE_MIN_HEIGHT := 120.0
const BUTTON_HEIGHT := 48.0

var _status: Label
var _tiles: BoxContainer
var _top: BoxContainer
var _connect: Button
var _bluetooth: Button
var _mock: Button
var _live: Button
var _builder: Button
var _reason: Label
var _auto_connect := false


func _ready() -> void:
	_build()
	Device.state_changed.connect(_on_state)
	Device.devices_changed.connect(_on_devices)
	_on_state(Device.state)
	get_viewport().size_changed.connect(_apply_orientation)
	_apply_orientation()


## Portrait: the two tiles stack vertically; landscape: side by side.
func _apply_orientation() -> void:
	var size := get_viewport().get_visible_rect().size
	var upright := size.y > size.x
	_tiles.vertical = upright
	# Upright: title, status and Connect stack, so the row never outgrows a narrow screen.
	_top.vertical = upright
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if upright else HORIZONTAL_ALIGNMENT_RIGHT


# ------------------------------------------------------------------ layout

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Clay.TABLE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m: Array = UiScale.safe_margins()
	margin.add_theme_constant_override("margin_left", int(m[0]) + 24)
	margin.add_theme_constant_override("margin_top", int(m[1]) + 12)
	margin.add_theme_constant_override("margin_right", int(m[2]) + 24)
	margin.add_theme_constant_override("margin_bottom", int(m[3]) + 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	# Title and connection row.
	var top := BoxContainer.new()
	_top = top
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var title := Label.new()
	title.text = "Gamemote"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Clay.INK)
	top.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 17)
	# Wrap long status text instead of widening the row past a narrow (upright) screen.
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 80
	_status.add_theme_color_override("font_color", Clay.INK)
	top.add_child(_status)
	_connect = Clay.pill_button("Connect", BUTTON_HEIGHT)
	_connect.custom_minimum_size.x = 140
	_connect.pressed.connect(_on_connect_pressed)
	top.add_child(_connect)

	# Which link to use.
	var link := HBoxContainer.new()
	link.add_theme_constant_override("separation", 8)
	column.add_child(link)
	var link_label := Label.new()
	link_label.text = "Connect with"
	link_label.add_theme_font_size_override("font_size", 15)
	link_label.add_theme_color_override("font_color", Clay.INK)
	link.add_child(link_label)
	var group := ButtonGroup.new()
	_bluetooth = _transport_button("Bluetooth", group)
	_bluetooth.disabled = not GmBleTransport.is_available()
	_bluetooth.pressed.connect(_on_transport_chosen.bind("ble"))
	link.add_child(_bluetooth)
	_mock = _transport_button("Mock device", group)
	_mock.pressed.connect(_on_transport_chosen.bind("mock"))
	link.add_child(_mock)
	_select_transport_button()

	# The two big choices.
	var tiles := BoxContainer.new()
	_tiles = tiles
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiles.add_theme_constant_override("separation", 16)
	column.add_child(tiles)
	_live = _tile("Live", "Drive your gadget with the gamepad", Clay.MINT, LIVE_SCENE)
	tiles.add_child(_live)
	_builder = _tile("Routine builder", "Snap blocks together to make a routine", Clay.SKY, BUILDER_SCENE)
	tiles.add_child(_builder)

	# Why the tiles are disabled, and the developer link.
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	_reason = Label.new()
	_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason.add_theme_font_size_override("font_size", 17)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size.x = 80
	_reason.add_theme_color_override("font_color", Clay.INK)
	bottom.add_child(_reason)
	var classic := Button.new()
	classic.text = "Classic view (developer)"
	classic.flat = true
	classic.focus_mode = Control.FOCUS_NONE
	classic.custom_minimum_size = Vector2(0, 44)
	classic.add_theme_font_size_override("font_size", 13)
	classic.add_theme_color_override("font_color", Clay.INK.lerp(Clay.TABLE, 0.4))
	classic.add_theme_color_override("font_hover_color", Clay.INK)
	classic.pressed.connect(func(): get_tree().change_scene_to_file(CLASSIC_SCENE))
	bottom.add_child(classic)


func _transport_button(text: String, group: ButtonGroup) -> Button:
	var b := Clay.pill_button(text, 44.0)
	b.toggle_mode = true
	b.button_group = group
	return b


## A big clay tile with a title and a one-line description.
func _tile(title: String, subtitle: String, color: Color, scene: String) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, TILE_MIN_HEIGHT)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(28)
	sb.shadow_color = Clay.SHADOW_TINT
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate()
	hover.bg_color = color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate()
	pressed.bg_color = color.darkened(0.12)
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("pressed", pressed)
	var off := sb.duplicate()
	off.bg_color = Clay.DISABLED
	off.shadow_size = 0
	b.add_theme_stylebox_override("disabled", off)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(center)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_color", Clay.INK)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Clay.INK)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)

	b.pressed.connect(func(): get_tree().change_scene_to_file(scene))
	return b


# ------------------------------------------------------------------ connection

func _select_transport_button() -> void:
	var is_ble: bool = Device.transport.get_kind() == "ble"
	_bluetooth.set_pressed_no_signal(is_ble)
	_mock.set_pressed_no_signal(not is_ble)


## Switches between Bluetooth and the mock device (this drops any current connection).
func _on_transport_chosen(kind: String) -> void:
	if Device.transport.get_kind() != kind:
		_auto_connect = false
		Device.use_transport(kind)


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
	var reason := ""
	match state:
		Device.State.OFF:
			reason = "Bluetooth is off. Turn it on, or choose Mock device."
		Device.State.IDLE:
			text = "Not connected"
			reason = "Connect your gadget first"
		Device.State.SCANNING:
			text = "Looking for your gadget…"
			reason = "Connect your gadget first"
		Device.State.CONNECTING:
			text = "Connecting…"
			reason = "Connecting to your gadget…"
		Device.State.READY:
			text = "Connected to %s" % Device.info.get("name", "your gadget")
			reason = "Pick what you want to do"
		Device.State.RECONNECTING:
			text = "Connection lost, reconnecting…"
			reason = "Reconnecting to your gadget…"
	if Device.transport.get_kind() == "mock":
		text += " (mock device)"
	_status.text = text
	_reason.text = reason
	var busy: bool = state in [Device.State.READY, Device.State.CONNECTING, Device.State.RECONNECTING]
	_connect.text = "Disconnect" if busy else "Connect"
	_connect.disabled = state == Device.State.OFF
	# Changing the link drops the connection, so only allow it while not linked.
	_mock.disabled = busy or state == Device.State.SCANNING
	_bluetooth.disabled = _mock.disabled or not GmBleTransport.is_available()
	_select_transport_button()
	_live.disabled = not Device.is_ready()
	_builder.disabled = not Device.is_ready()
