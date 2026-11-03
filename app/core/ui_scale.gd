extends Node
## Autoload "UiScale": makes 1 UI unit = 1 point (like native iOS apps), so the
## same layout reads well on iPhone and iPad. Project stretch mode must be
## "canvas_items" with aspect "expand".

signal changed(scale: float)

## Extra user multiplier (e.g. 1.15 for larger text).
var extra := 1.0
var scale := 1.0


func _ready() -> void:
	get_window().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var win := get_window()
	if win.size.x <= 0 or win.size.y <= 0:
		return
	scale = _forced_scale()
	if scale <= 0.0:
		scale = maxf(1.0, DisplayServer.screen_get_scale())
	scale *= extra
	win.content_scale_size = Vector2i((Vector2(win.size) / scale).round())
	changed.emit(scale)


## Safe area (notch, home indicator) as margins in UI units: [left, top, right, bottom].
func safe_margins() -> Array:
	var win := get_window()
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if not OS.has_feature("mobile") or safe.size.x <= 0 or screen.x <= 0:
		return [0, 0, 0, 0]
	var left := safe.position.x
	var top := safe.position.y
	var right := screen.x - safe.end.x
	var bottom := screen.y - safe.end.y
	var k := float(win.content_scale_size.x) / float(win.size.x)
	return [left * k, top * k, right * k, bottom * k]


## Desktop preview of phone/tablet layouts: run with `-- --ui-scale=2`.
func _forced_scale() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			return arg.get_slice("=", 1).to_float()
	return 0.0
