class_name ConsoleView
extends Control
## The 2D content of the Live console screen (drawn inside the pad's SubViewport):
## status bar (link bars, link state in words, round-trip time), the message log
## (newest last, auto-scroll, colour per kind) and a legend of what each button does.

const SIZE_PX := Vector2(640, 352)
const BG := Color("1b202b")
const BAR_BG := Color("272e3c")
const KIND_COLORS := {
	"status": Color("b9c3d6"), "command": Color("8fd6c4"),
	"feedback": Color("f2d98a"), "error": Color("ff8a80"),
}
const MAX_SHOWN := 40

var _console: ConsoleLog
var _state_label: Label
var _rtt_label: Label
var _bars: Control
var _log: RichTextLabel
var _legend_row: HBoxContainer
var _legend_entries: Array = []   # [letter, text]


func _init() -> void:
	custom_minimum_size = SIZE_PX
	size = SIZE_PX


## Resizes the view to the screen's pixel size (the upright console is taller than wide).
func fit(px: Vector2) -> void:
	custom_minimum_size = Vector2.ZERO
	size = px


## Binds the view to a ConsoleLog and to the Device link state.
func setup(console: ConsoleLog) -> void:
	_build()
	_console = console
	console.changed.connect(_refresh_log)
	console.rtt_changed.connect(func(_a: int, _b: int) -> void: _refresh_status())
	Device.state_changed.connect(func(_s: int) -> void: _refresh_status())
	_refresh_log()
	_refresh_status()


## entries: Array of [letter, meaning]; an empty meaning is shown greyed as "-".
func set_legend(entries: Array) -> void:
	_legend_entries = entries
	if _legend_row == null:
		return
	for c in _legend_row.get_children():
		c.queue_free()
	var order := ["X", "Y", "B", "A"]
	var colors := {"X": Clay.ORANGE, "Y": Clay.YELLOW, "B": Clay.TEAL, "A": Clay.CORAL}
	for letter in order:
		var text := ""
		for e in entries:
			if e[0] == letter:
				text = String(e[1])
		var l := Label.new()
		l.text = "%s: %s" % [letter, text if text != "" else "-"]
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", colors[letter] if text != "" else Color("5d6678"))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_legend_row.add_child(l)


func _build() -> void:
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(18)
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	# Status bar.
	var bar_panel := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = BAR_BG
	bsb.set_corner_radius_all(10)
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	bar_panel.add_theme_stylebox_override("panel", bsb)
	col.add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar_panel.add_child(bar)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(34, 26)
	_bars.draw.connect(_draw_bars)
	bar.add_child(_bars)
	_state_label = Label.new()
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.add_theme_font_size_override("font_size", 22)
	_state_label.clip_text = true
	bar.add_child(_state_label)
	_rtt_label = Label.new()
	_rtt_label.add_theme_font_size_override("font_size", 22)
	_rtt_label.add_theme_color_override("font_color", Color("b9c3d6"))
	bar.add_child(_rtt_label)

	# Message log.
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.scroll_active = false
	_log.fit_content = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 21)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_log)

	# Legend.
	_legend_row = HBoxContainer.new()
	_legend_row.add_theme_constant_override("separation", 8)
	col.add_child(_legend_row)
	set_legend(_legend_entries)


func _draw() -> void:
	# A faint glassy sheen across the top-left corner.
	var sheen := PackedVector2Array([Vector2(0, 0), Vector2(size.x * 0.55, 0), Vector2(size.x * 0.25, size.y * 0.5), Vector2(0, size.y * 0.5)])
	draw_colored_polygon(sheen, Color(1, 1, 1, 0.045))


func _link_level() -> int:
	if Device.state != Device.State.READY:
		return 0
	var rtt := _console.p95_rtt() if _console else -1
	if rtt < 0:
		return 3
	return 4 if rtt < 60 else (3 if rtt < 120 else (2 if rtt < 250 else 1))


func _draw_bars() -> void:
	var level := _link_level()
	var col := Color("7fe0a0") if level >= 3 else (Color("f2d98a") if level >= 1 else Color("ff8a80"))
	if Device.state in [Device.State.SCANNING, Device.State.CONNECTING, Device.State.RECONNECTING]:
		col = Color("f2d98a")
		level = 1
	for i in 4:
		var h := 7.0 + i * 6.0
		var r := Rect2(i * 9.0, 26.0 - h, 6.0, h)
		_bars.draw_rect(r, col if i < level else Color("3a4254"))


func _refresh_status() -> void:
	var words := "Not connected"
	match Device.state:
		Device.State.OFF: words = "Bluetooth is off"
		Device.State.SCANNING: words = "Looking for gadgets…"
		Device.State.CONNECTING: words = "Connecting…"
		Device.State.READY: words = "Connected to %s" % Device.info.get("name", "the gadget")
		Device.State.RECONNECTING: words = "Reconnecting…"
	_state_label.text = words
	_state_label.add_theme_color_override("font_color",
			Color("e8edf7") if Device.state == Device.State.READY else Color("b9c3d6"))
	var rtt := _console.latest_rtt() if _console else -1
	_rtt_label.text = "RTT %d ms" % rtt if rtt >= 0 else "RTT --"
	_bars.queue_redraw()


func _refresh_log() -> void:
	var lines := _console.get_lines()
	var out := ""
	for i in range(maxi(0, lines.size() - MAX_SHOWN), lines.size()):
		var line: Dictionary = lines[i]
		var c: Color = KIND_COLORS.get(line.kind, KIND_COLORS.status)
		out += "[color=#%s]%s[/color]\n" % [c.to_html(false), String(line.text).replace("[", "[lb]")]
	_log.text = out.strip_edges(false, true)
