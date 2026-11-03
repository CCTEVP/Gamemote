// GamemoteBle: a small, protocol-agnostic BLE central exposed to GDScript.
//
// All Gamemote protocol logic lives in GDScript (app/core). This class only
// scans, connects, reads, writes and subscribes. Call poll() every frame from
// the main thread; it emits the signals below.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

namespace gmble {
class Backend;
}

namespace godot {

class GamemoteBle : public RefCounted {
	GDCLASS(GamemoteBle, RefCounted)

public:
	enum AdapterState {
		STATE_UNKNOWN = 0,
		STATE_RESETTING = 1,
		STATE_UNSUPPORTED = 2,
		STATE_UNAUTHORIZED = 3,
		STATE_POWERED_OFF = 4,
		STATE_POWERED_ON = 5,
		STATE_MISSING_USAGE_DESCRIPTION = 6,
	};

	GamemoteBle();
	~GamemoteBle() override;

	String get_backend_name() const;
	bool is_supported() const;
	void initialize();
	int get_adapter_state() const;

	void start_scan(const PackedStringArray &service_uuids);
	void stop_scan();
	bool connect_peripheral(const String &id);
	void disconnect_peripheral();
	bool read(const String &char_uuid);
	bool write(const String &char_uuid, const PackedByteArray &data, bool with_response);
	bool set_notify(const String &char_uuid, bool enabled);
	int get_max_write_length(bool with_response) const;
	bool can_send_without_response() const;

	int poll();

protected:
	static void _bind_methods();

private:
	std::unique_ptr<gmble::Backend> backend;
};

} // namespace godot

VARIANT_ENUM_CAST(GamemoteBle::AdapterState);
