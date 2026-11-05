@tool
extends EditorExportPlugin
## Adds required Info.plist keys on iOS exports. A key already present in the
## preset's "Additional Plist Content" is left alone, so nothing is duplicated.

const KEYS := {
	"NSBluetoothAlwaysUsageDescription": "<string>Gamemote uses Bluetooth to find and control your device.</string>",
	"UIRequiresFullScreen": "<true/>",
}


func _get_name() -> String:
	return "GamemoteIosExport"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform.get_os_name() == "iOS"


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	var existing := ""
	var preset := get_export_preset()
	if preset != null:
		existing = str(preset.get_or_env("application/additional_plist_content", ""))
	var added := []
	for key in KEYS:
		if not existing.contains("<key>%s</key>" % key):
			add_apple_embedded_platform_plist_content("<key>%s</key>\n%s" % [key, KEYS[key]])
			added.append(key)
	if not added.is_empty():
		print("Gamemote iOS export: added Info.plist keys ", added)
