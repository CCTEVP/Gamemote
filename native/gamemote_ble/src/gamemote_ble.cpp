#include "gamemote_ble.h"

#include "ble_backend.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {

String to_godot(const std::string &s) {
	return String::utf8(s.c_str(), (int64_t)s.size());
}

std::string to_std(const String &s) {
	CharString utf8 = s.utf8();
	return std::string(utf8.get_data(), (size_t)utf8.length());
}

PackedByteArray to_bytes(const std::vector<uint8_t> &v) {
	PackedByteArray out;
	out.resize((int64_t)v.size());
	if (!v.empty()) {
		memcpy(out.ptrw(), v.data(), v.size());
	}
	return out;
}

} // namespace

GamemoteBle::GamemoteBle() :
		backend(gmble::create_backend()) {}

GamemoteBle::~GamemoteBle() = default;

String GamemoteBle::get_backend_name() const {
	return String(backend->name());
}

bool GamemoteBle::is_supported() const {
	return backend->is_supported();
}

void GamemoteBle::initialize() {
	backend->initialize();
}

int GamemoteBle::get_adapter_state() const {
	return backend->adapter_state();
}

void GamemoteBle::start_scan(const PackedStringArray &service_uuids) {
	std::vector<std::string> uuids;
	for (int64_t i = 0; i < service_uuids.size(); i++) {
		uuids.push_back(to_std(service_uuids[i]));
	}
	backend->start_scan(uuids);
}

void GamemoteBle::stop_scan() {
	backend->stop_scan();
}

bool GamemoteBle::connect_peripheral(const String &id) {
	return backend->connect(to_std(id));
}

void GamemoteBle::disconnect_peripheral() {
	backend->disconnect();
}

bool GamemoteBle::read(const String &char_uuid) {
	return backend->read(to_std(char_uuid));
}

bool GamemoteBle::write(const String &char_uuid, const PackedByteArray &data, bool with_response) {
	std::vector<uint8_t> bytes((size_t)data.size());
	if (!bytes.empty()) {
		memcpy(bytes.data(), data.ptr(), bytes.size());
	}
	return backend->write(to_std(char_uuid), bytes, with_response);
}

bool GamemoteBle::set_notify(const String &char_uuid, bool enabled) {
	return backend->set_notify(to_std(char_uuid), enabled);
}

int GamemoteBle::get_max_write_length(bool with_response) const {
	return backend->max_write_length(with_response);
}

bool GamemoteBle::can_send_without_response() const {
	return backend->can_send_without_response();
}

int GamemoteBle::poll() {
	int count = 0;
	gmble::Event e;
	// Bound the work per frame; anything left is handled next frame.
	while (count < 256 && backend->poll(e)) {
		count++;
		switch (e.type) {
			case gmble::EventType::AdapterState:
				emit_signal("adapter_state_changed", e.state);
				break;
			case gmble::EventType::PeripheralFound:
				emit_signal("peripheral_found", to_godot(e.id), to_godot(e.name), e.rssi);
				break;
			case gmble::EventType::Connected:
				emit_signal("connected", to_godot(e.id));
				break;
			case gmble::EventType::ConnectFailed:
				emit_signal("connect_failed", to_godot(e.id), to_godot(e.error));
				break;
			case gmble::EventType::Disconnected:
				emit_signal("disconnected", to_godot(e.id), to_godot(e.error));
				break;
			case gmble::EventType::ServicesDiscovered: {
				PackedStringArray uuids;
				for (const std::string &u : e.uuids) {
					uuids.push_back(to_godot(u));
				}
				emit_signal("services_discovered", uuids);
			} break;
			case gmble::EventType::NotifyStateChanged:
				emit_signal("notify_state_changed", to_godot(e.uuid), e.flag);
				break;
			case gmble::EventType::ValueRead:
				emit_signal("value_read", to_godot(e.uuid), to_bytes(e.data));
				break;
			case gmble::EventType::Notified:
				emit_signal("notified", to_godot(e.uuid), to_bytes(e.data));
				break;
			case gmble::EventType::WriteCompleted:
				emit_signal("write_completed", to_godot(e.uuid), to_godot(e.error));
				break;
			case gmble::EventType::ReadyToSend:
				emit_signal("ready_to_send");
				break;
			case gmble::EventType::Error:
				emit_signal("error", to_godot(e.error));
				break;
		}
	}
	return count;
}

void GamemoteBle::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_backend_name"), &GamemoteBle::get_backend_name);
	ClassDB::bind_method(D_METHOD("is_supported"), &GamemoteBle::is_supported);
	ClassDB::bind_method(D_METHOD("initialize"), &GamemoteBle::initialize);
	ClassDB::bind_method(D_METHOD("get_adapter_state"), &GamemoteBle::get_adapter_state);
	ClassDB::bind_method(D_METHOD("start_scan", "service_uuids"), &GamemoteBle::start_scan);
	ClassDB::bind_method(D_METHOD("stop_scan"), &GamemoteBle::stop_scan);
	ClassDB::bind_method(D_METHOD("connect_peripheral", "id"), &GamemoteBle::connect_peripheral);
	ClassDB::bind_method(D_METHOD("disconnect_peripheral"), &GamemoteBle::disconnect_peripheral);
	ClassDB::bind_method(D_METHOD("read", "char_uuid"), &GamemoteBle::read);
	ClassDB::bind_method(D_METHOD("write", "char_uuid", "data", "with_response"), &GamemoteBle::write);
	ClassDB::bind_method(D_METHOD("set_notify", "char_uuid", "enabled"), &GamemoteBle::set_notify);
	ClassDB::bind_method(D_METHOD("get_max_write_length", "with_response"), &GamemoteBle::get_max_write_length);
	ClassDB::bind_method(D_METHOD("can_send_without_response"), &GamemoteBle::can_send_without_response);
	ClassDB::bind_method(D_METHOD("poll"), &GamemoteBle::poll);

	ADD_SIGNAL(MethodInfo("adapter_state_changed", PropertyInfo(Variant::INT, "state")));
	ADD_SIGNAL(MethodInfo("peripheral_found", PropertyInfo(Variant::STRING, "id"),
			PropertyInfo(Variant::STRING, "name"), PropertyInfo(Variant::INT, "rssi")));
	ADD_SIGNAL(MethodInfo("connected", PropertyInfo(Variant::STRING, "id")));
	ADD_SIGNAL(MethodInfo("connect_failed", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("disconnected", PropertyInfo(Variant::STRING, "id"), PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("services_discovered", PropertyInfo(Variant::PACKED_STRING_ARRAY, "characteristics")));
	ADD_SIGNAL(MethodInfo("notify_state_changed", PropertyInfo(Variant::STRING, "char_uuid"), PropertyInfo(Variant::BOOL, "enabled")));
	ADD_SIGNAL(MethodInfo("value_read", PropertyInfo(Variant::STRING, "char_uuid"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data")));
	ADD_SIGNAL(MethodInfo("notified", PropertyInfo(Variant::STRING, "char_uuid"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data")));
	ADD_SIGNAL(MethodInfo("write_completed", PropertyInfo(Variant::STRING, "char_uuid"), PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("ready_to_send"));
	ADD_SIGNAL(MethodInfo("error", PropertyInfo(Variant::STRING, "message")));

	BIND_ENUM_CONSTANT(STATE_UNKNOWN);
	BIND_ENUM_CONSTANT(STATE_RESETTING);
	BIND_ENUM_CONSTANT(STATE_UNSUPPORTED);
	BIND_ENUM_CONSTANT(STATE_UNAUTHORIZED);
	BIND_ENUM_CONSTANT(STATE_POWERED_OFF);
	BIND_ENUM_CONSTANT(STATE_POWERED_ON);
	BIND_ENUM_CONSTANT(STATE_MISSING_USAGE_DESCRIPTION);
}
