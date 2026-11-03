// Fallback backend for platforms without a native implementation yet
// (Linux, Windows, Android). It reports "unsupported" so the app can fall
// back to its mock transport, and lets the extension load and be tested.
#include "ble_backend.h"

namespace gmble {

class StubBackend final : public Backend {
public:
	const char *name() const override { return "stub"; }
	bool is_supported() const override { return false; }

	void initialize() override {
		Event e;
		e.type = EventType::AdapterState;
		e.state = STATE_UNSUPPORTED;
		push(std::move(e));
	}
	int adapter_state() const override { return STATE_UNSUPPORTED; }

	void start_scan(const std::vector<std::string> &) override {}
	void stop_scan() override {}
	bool connect(const std::string &) override { return false; }
	void disconnect() override {}
	bool read(const std::string &) override { return false; }
	bool write(const std::string &, const std::vector<uint8_t> &, bool) override { return false; }
	bool set_notify(const std::string &, bool) override { return false; }
	int max_write_length(bool) const override { return 20; }
	bool can_send_without_response() const override { return false; }
};

std::unique_ptr<Backend> create_backend() {
	return std::make_unique<StubBackend>();
}

} // namespace gmble
