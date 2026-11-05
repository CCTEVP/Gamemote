@tool
extends EditorPlugin
## Registers GamemoteIosExport so iOS exports always carry the Info.plist keys the
## app needs. Without NSBluetoothAlwaysUsageDescription, iOS refuses Bluetooth
## (the app shows "missing NSBluetoothAlwaysUsageDescription").

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/gamemote_ios/ios_export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
