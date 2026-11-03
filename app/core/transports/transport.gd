class_name GmTransport
extends RefCounted
## Link between the app and one Gamemote device. Implementations: GmBleTransport
## (CoreBluetooth via the gamemote_ble extension) and GmMockTransport (in-app sim).
##
## Lifecycle: start() -> start_scan() -> device_found... -> connect_to(id)
##   -> connected -> link_ready(info) -> frame_received... -> disconnected.
## Call poll() every frame from the main thread.

signal adapter_changed(ready: bool, message: String)
signal device_found(id: String, name: String, rssi: int)
signal connected(id: String)
signal link_ready(info: Dictionary)
signal connect_failed(id: String, reason: String)
signal disconnected(id: String, reason: String)
signal frame_received(frame: PackedByteArray)
signal log_message(message: String)


func get_kind() -> String:
	return "none"


## True once the radio is usable (scan/connect will work).
func is_adapter_ready() -> bool:
	return false


func start() -> void:
	pass


func poll(_delta: float) -> void:
	pass


func start_scan() -> void:
	pass


func stop_scan() -> void:
	pass


func connect_to(_id: String) -> void:
	pass


func disconnect_from() -> void:
	pass


## Sends one CMD frame. reliable = GATT write with response.
## Returns false if it could not be queued (e.g. unreliable buffer full).
func send(_frame: PackedByteArray, _reliable: bool) -> bool:
	return false


## True when an unreliable (write-without-response) frame can be queued now.
func can_send_unreliable() -> bool:
	return true
