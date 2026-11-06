extends "res://ui/table/table.gd"
## Live mode: only the clay gamepad on the table. Back returns to Home and sends STOP.


func _init() -> void:
	mode = "live"
