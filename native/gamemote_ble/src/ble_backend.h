// Platform-neutral BLE central backend used by the GamemoteBle Godot class.
//
// This header deliberately has no Godot and no Objective-C types, so the
// CoreBluetooth implementation (.mm) never includes godot-cpp headers.
//
// Threading: platform callbacks may arrive on any thread. They are turned into
// Event values and pushed into a mutex-protected queue; Godot drains the queue
// from the main thread with poll().
#pragma once

#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace gmble {

// Values match CBManagerState (0..5); 6 is ours.
enum AdapterState : int {
	STATE_UNKNOWN = 0,
	STATE_RESETTING = 1,
	STATE_UNSUPPORTED = 2,
	STATE_UNAUTHORIZED = 3,
	STATE_POWERED_OFF = 4,
	STATE_POWERED_ON = 5,
	STATE_MISSING_USAGE_DESCRIPTION = 6, // Info.plist lacks NSBluetoothAlwaysUsageDescription
};

enum class EventType {
	AdapterState,
	PeripheralFound,
	Connected,
	ConnectFailed,
	Disconnected,
	ServicesDiscovered,
	NotifyStateChanged,
	ValueRead,
	Notified,
	WriteCompleted,
	ReadyToSend,
	Error,
};

struct Event {
	EventType type = EventType::Error;
	std::string id; // peripheral identifier
	std::string name; // peripheral name
	std::string uuid; // characteristic UUID (lowercase)
	std::string error; // empty when no error
	std::vector<uint8_t> data;
	std::vector<std::string> uuids; // discovered characteristic UUIDs
	int rssi = 0;
	int state = 0;
	bool flag = false;
};

class Backend {
public:
	virtual ~Backend() = default;

	virtual const char *name() const = 0;
	virtual bool is_supported() const = 0;

	// Creates the platform manager. On iOS this may show the permission prompt.
	virtual void initialize() = 0;
	virtual int adapter_state() const = 0;

	virtual void start_scan(const std::vector<std::string> &service_uuids) = 0;
	virtual void stop_scan() = 0;
	virtual bool connect(const std::string &id) = 0;
	virtual void disconnect() = 0;
	virtual bool read(const std::string &char_uuid) = 0;
	virtual bool write(const std::string &char_uuid, const std::vector<uint8_t> &data, bool with_response) = 0;
	virtual bool set_notify(const std::string &char_uuid, bool enabled) = 0;
	virtual int max_write_length(bool with_response) const = 0;
	virtual bool can_send_without_response() const = 0;

	// Pops one event. Thread-safe. Returns false when the queue is empty.
	bool poll(Event &out) {
		std::lock_guard<std::mutex> lock(mutex_);
		if (queue_.empty()) {
			return false;
		}
		out = std::move(queue_.front());
		queue_.pop_front();
		return true;
	}

protected:
	void push(Event e) {
		std::lock_guard<std::mutex> lock(mutex_);
		if (queue_.size() >= kMaxQueued) {
			queue_.pop_front(); // never grow without bound if Godot stops polling
		}
		queue_.push_back(std::move(e));
	}

private:
	static constexpr size_t kMaxQueued = 1024;
	std::mutex mutex_;
	std::deque<Event> queue_;
};

std::unique_ptr<Backend> create_backend();

} // namespace gmble
