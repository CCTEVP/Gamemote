// CoreBluetooth backend (iOS, iPadOS, macOS).
//
// Compiled with -fobjc-arc -fmodules -fcxx-modules. With modules enabled, the
// `@import CoreBluetooth;` below makes clang embed an auto-link directive, so the
// app links CoreBluetooth.framework without any Xcode project edits (Godot's own
// iOS sources rely on the same mechanism).
//
// Threading: CBCentralManager runs on a private serial dispatch queue. Every
// CoreBluetooth object is only touched on that queue. Public methods are called
// from Godot's main thread and dispatch onto the queue; results flow back as
// Events through the thread-safe queue in Backend.

@import Foundation;
@import CoreBluetooth;

#include "ble_backend.h"

#include <atomic>

namespace gmble {
class AppleBackend;
}

@interface GMBleDelegate : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property(nonatomic, assign) gmble::AppleBackend *owner;
@end

namespace gmble {

static std::string to_std(NSString *s) {
	return s ? std::string([s UTF8String]) : std::string();
}

static NSString *to_ns(const std::string &s) {
	return [NSString stringWithUTF8String:s.c_str()];
}

static std::string uuid_key(CBUUID *uuid) {
	return to_std([[uuid UUIDString] lowercaseString]);
}

static std::string error_text(NSError *error) {
	return error ? to_std([error localizedDescription]) : std::string();
}

class AppleBackend final : public Backend {
public:
	AppleBackend() {
		queue_ = dispatch_queue_create("com.gamemote.ble", DISPATCH_QUEUE_SERIAL);
		delegate_ = [GMBleDelegate new];
		delegate_.owner = this;
		discovered_ = [NSMutableDictionary dictionary];
		characteristics_ = [NSMutableDictionary dictionary];
		pending_reads_ = [NSMutableSet set];
	}

	~AppleBackend() override {
		dispatch_sync(queue_, ^{
			delegate_.owner = nullptr;
			if (central_) {
				if (central_.state == CBManagerStatePoweredOn) {
					[central_ stopScan];
					if (peripheral_) {
						[central_ cancelPeripheralConnection:peripheral_];
					}
				}
				central_.delegate = nil;
			}
			peripheral_.delegate = nil;
			peripheral_ = nil;
			central_ = nil;
		});
	}

	const char *name() const override { return "corebluetooth"; }
	bool is_supported() const override { return true; }

	void initialize() override {
		// Accessing CoreBluetooth without a usage description makes iOS/macOS kill
		// the app. Check first and report a clear state instead of crashing.
		id usage = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSBluetoothAlwaysUsageDescription"];
		if (usage == nil) {
			state_ = STATE_MISSING_USAGE_DESCRIPTION;
			Event e;
			e.type = EventType::AdapterState;
			e.state = STATE_MISSING_USAGE_DESCRIPTION;
			push(std::move(e));
			return;
		}
		dispatch_async(queue_, ^{
			if (central_ == nil) {
				central_ = [[CBCentralManager alloc] initWithDelegate:delegate_
																queue:queue_
															  options:@{ CBCentralManagerOptionShowPowerAlertKey : @YES }];
			} else {
				on_state(central_);
			}
		});
	}

	int adapter_state() const override { return state_.load(); }

	void start_scan(const std::vector<std::string> &service_uuids) override {
		NSMutableArray<CBUUID *> *uuids = [NSMutableArray array];
		for (const std::string &s : service_uuids) {
			[uuids addObject:[CBUUID UUIDWithString:to_ns(s)]];
		}
		dispatch_async(queue_, ^{
			if (!powered_on("start_scan")) {
				return;
			}
			[discovered_ removeAllObjects];
			[central_ scanForPeripheralsWithServices:(uuids.count ? uuids : nil)
											 options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @NO }];
		});
	}

	void stop_scan() override {
		dispatch_async(queue_, ^{
			if (central_ && central_.state == CBManagerStatePoweredOn) {
				[central_ stopScan];
			}
		});
	}

	bool connect(const std::string &id) override {
		NSString *ident = to_ns(id);
		dispatch_async(queue_, ^{
			if (!powered_on("connect")) {
				return;
			}
			CBPeripheral *p = discovered_[ident];
			if (p == nil) {
				// Not seen in this scan: try a peripheral known to the system (reconnect).
				NSUUID *nsuuid = [[NSUUID alloc] initWithUUIDString:ident];
				if (nsuuid) {
					p = [central_ retrievePeripheralsWithIdentifiers:@[ nsuuid ]].firstObject;
				}
			}
			if (p == nil) {
				Event e;
				e.type = EventType::ConnectFailed;
				e.id = to_std(ident);
				e.error = "unknown peripheral (scan first)";
				push(std::move(e));
				return;
			}
			if (peripheral_ && peripheral_ != p) {
				[central_ cancelPeripheralConnection:peripheral_];
			}
			[central_ stopScan];
			peripheral_ = p;
			peripheral_.delegate = delegate_;
			[characteristics_ removeAllObjects];
			[pending_reads_ removeAllObjects];
			can_send_ = false;
			[central_ connectPeripheral:p options:nil];
		});
		return true;
	}

	void disconnect() override {
		dispatch_async(queue_, ^{
			if (central_ && peripheral_ && central_.state == CBManagerStatePoweredOn) {
				[central_ cancelPeripheralConnection:peripheral_];
			}
		});
	}

	bool read(const std::string &char_uuid) override {
		NSString *key = to_ns(char_uuid);
		dispatch_async(queue_, ^{
			CBCharacteristic *c = characteristic(key, "read");
			if (c) {
				[pending_reads_ addObject:key.lowercaseString];
				[peripheral_ readValueForCharacteristic:c];
			}
		});
		return peripheral_connected_.load();
	}

	bool write(const std::string &char_uuid, const std::vector<uint8_t> &data, bool with_response) override {
		NSString *key = to_ns(char_uuid);
		NSData *payload = [NSData dataWithBytes:data.data() length:data.size()];
		if (!with_response && !can_send_.load()) {
			return false; // caller keeps the latest state and retries on ready_to_send
		}
		dispatch_async(queue_, ^{
			CBCharacteristic *c = characteristic(key, "write");
			if (c == nil) {
				return;
			}
			if (with_response) {
				[peripheral_ writeValue:payload forCharacteristic:c type:CBCharacteristicWriteWithResponse];
			} else if (peripheral_.canSendWriteWithoutResponse) {
				[peripheral_ writeValue:payload forCharacteristic:c type:CBCharacteristicWriteWithoutResponse];
				can_send_ = peripheral_.canSendWriteWithoutResponse;
			} else {
				can_send_ = false;
			}
		});
		return peripheral_connected_.load();
	}

	bool set_notify(const std::string &char_uuid, bool enabled) override {
		NSString *key = to_ns(char_uuid);
		dispatch_async(queue_, ^{
			CBCharacteristic *c = characteristic(key, "set_notify");
			if (c) {
				[peripheral_ setNotifyValue:enabled forCharacteristic:c];
			}
		});
		return peripheral_connected_.load();
	}

	int max_write_length(bool with_response) const override {
		return with_response ? max_write_with_response_.load() : max_write_without_response_.load();
	}

	bool can_send_without_response() const override { return can_send_.load(); }

	// ------------------------------------------------------------------
	// Delegate callbacks (always on queue_).

	void on_state(CBCentralManager *central) {
		state_ = (int)central.state;
		if (central.state != CBManagerStatePoweredOn) {
			peripheral_connected_ = false;
			can_send_ = false;
		}
		Event e;
		e.type = EventType::AdapterState;
		e.state = (int)central.state;
		push(std::move(e));
	}

	void on_discover(CBPeripheral *p, NSDictionary<NSString *, id> *adv, NSNumber *rssi) {
		NSString *ident = p.identifier.UUIDString;
		discovered_[ident] = p; // keep a strong reference, required to connect later
		NSString *local = adv[CBAdvertisementDataLocalNameKey];
		Event e;
		e.type = EventType::PeripheralFound;
		e.id = to_std(ident);
		e.name = to_std(local ?: p.name ?: @"");
		e.rssi = rssi.intValue;
		push(std::move(e));
	}

	void on_connect(CBPeripheral *p) {
		if (p != peripheral_) {
			return;
		}
		peripheral_connected_ = true;
		max_write_with_response_ = (int)[p maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse];
		max_write_without_response_ = (int)[p maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse];
		can_send_ = p.canSendWriteWithoutResponse;
		Event e;
		e.type = EventType::Connected;
		e.id = to_std(p.identifier.UUIDString);
		e.name = to_std(p.name ?: @"");
		push(std::move(e));
		pending_services_ = 0;
		[p discoverServices:nil];
	}

	void on_fail(CBPeripheral *p, NSError *error) {
		if (p == peripheral_) {
			peripheral_ = nil;
		}
		Event e;
		e.type = EventType::ConnectFailed;
		e.id = to_std(p.identifier.UUIDString);
		e.error = error_text(error);
		push(std::move(e));
	}

	void on_disconnect(CBPeripheral *p, NSError *error) {
		if (p == peripheral_) {
			peripheral_.delegate = nil;
			peripheral_ = nil;
			[characteristics_ removeAllObjects];
			[pending_reads_ removeAllObjects];
			peripheral_connected_ = false;
			can_send_ = false;
		}
		Event e;
		e.type = EventType::Disconnected;
		e.id = to_std(p.identifier.UUIDString);
		e.error = error_text(error);
		push(std::move(e));
	}

	void on_services(CBPeripheral *p, NSError *error) {
		if (error) {
			push_error("discover services: " + error_text(error));
			return;
		}
		pending_services_ = (int)p.services.count;
		if (pending_services_ == 0) {
			services_ready();
		}
		for (CBService *s in p.services) {
			[p discoverCharacteristics:nil forService:s];
		}
	}

	void on_characteristics(CBService *service, NSError *error) {
		if (error) {
			push_error("discover characteristics: " + error_text(error));
		}
		for (CBCharacteristic *c in service.characteristics) {
			characteristics_[c.UUID.UUIDString.lowercaseString] = c;
		}
		if (--pending_services_ <= 0) {
			services_ready();
		}
	}

	void on_value(CBCharacteristic *c, NSError *error) {
		NSString *key = c.UUID.UUIDString.lowercaseString;
		bool was_read = [pending_reads_ containsObject:key];
		[pending_reads_ removeObject:key];
		if (error) {
			push_error("value " + to_std(key) + ": " + error_text(error));
			return;
		}
		Event e;
		e.type = was_read ? EventType::ValueRead : EventType::Notified;
		e.uuid = to_std(key);
		NSData *value = c.value;
		if (value.length) {
			const uint8_t *bytes = (const uint8_t *)value.bytes;
			e.data.assign(bytes, bytes + value.length);
		}
		push(std::move(e));
	}

	void on_write(CBCharacteristic *c, NSError *error) {
		Event e;
		e.type = EventType::WriteCompleted;
		e.uuid = uuid_key(c.UUID);
		e.error = error_text(error);
		push(std::move(e));
	}

	void on_notify_state(CBCharacteristic *c, NSError *error) {
		if (error) {
			push_error("notify " + uuid_key(c.UUID) + ": " + error_text(error));
		}
		Event e;
		e.type = EventType::NotifyStateChanged;
		e.uuid = uuid_key(c.UUID);
		e.flag = c.isNotifying;
		push(std::move(e));
	}

	void on_ready_to_send() {
		can_send_ = true;
		Event e;
		e.type = EventType::ReadyToSend;
		push(std::move(e));
	}

private:
	bool powered_on(const char *op) {
		if (central_ && central_.state == CBManagerStatePoweredOn) {
			return true;
		}
		push_error(std::string(op) + ": Bluetooth is not powered on");
		return false;
	}

	CBCharacteristic *characteristic(NSString *key, const char *op) {
		if (peripheral_ == nil) {
			push_error(std::string(op) + ": not connected");
			return nil;
		}
		CBCharacteristic *c = characteristics_[key.lowercaseString];
		if (c == nil) {
			push_error(std::string(op) + ": unknown characteristic " + to_std(key));
		}
		return c;
	}

	void services_ready() {
		Event e;
		e.type = EventType::ServicesDiscovered;
		for (NSString *key in characteristics_) {
			e.uuids.push_back(to_std(key));
		}
		push(std::move(e));
	}

	void push_error(const std::string &message) {
		Event e;
		e.type = EventType::Error;
		e.error = message;
		push(std::move(e));
	}

	dispatch_queue_t queue_;
	GMBleDelegate *delegate_ = nil;
	CBCentralManager *central_ = nil;
	CBPeripheral *peripheral_ = nil;
	NSMutableDictionary<NSString *, CBPeripheral *> *discovered_ = nil;
	NSMutableDictionary<NSString *, CBCharacteristic *> *characteristics_ = nil;
	NSMutableSet<NSString *> *pending_reads_ = nil;
	int pending_services_ = 0;

	std::atomic<int> state_{ STATE_UNKNOWN };
	std::atomic<bool> peripheral_connected_{ false };
	std::atomic<bool> can_send_{ false };
	std::atomic<int> max_write_with_response_{ 20 };
	std::atomic<int> max_write_without_response_{ 20 };
};

std::unique_ptr<Backend> create_backend() {
	return std::make_unique<AppleBackend>();
}

} // namespace gmble

@implementation GMBleDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
	if (self.owner) {
		self.owner->on_state(central);
	}
}

- (void)centralManager:(CBCentralManager *)central
		didDiscoverPeripheral:(CBPeripheral *)peripheral
			advertisementData:(NSDictionary<NSString *, id> *)advertisementData
						 RSSI:(NSNumber *)RSSI {
	if (self.owner) {
		self.owner->on_discover(peripheral, advertisementData, RSSI);
	}
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
	if (self.owner) {
		self.owner->on_connect(peripheral);
	}
}

- (void)centralManager:(CBCentralManager *)central
		didFailToConnectPeripheral:(CBPeripheral *)peripheral
							 error:(NSError *)error {
	if (self.owner) {
		self.owner->on_fail(peripheral, error);
	}
}

- (void)centralManager:(CBCentralManager *)central
		didDisconnectPeripheral:(CBPeripheral *)peripheral
						  error:(NSError *)error {
	if (self.owner) {
		self.owner->on_disconnect(peripheral, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
	if (self.owner) {
		self.owner->on_services(peripheral, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
		didDiscoverCharacteristicsForService:(CBService *)service
									   error:(NSError *)error {
	if (self.owner) {
		self.owner->on_characteristics(service, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
		didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
								  error:(NSError *)error {
	if (self.owner) {
		self.owner->on_value(characteristic, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
		didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
								 error:(NSError *)error {
	if (self.owner) {
		self.owner->on_write(characteristic, error);
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
		didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
											  error:(NSError *)error {
	if (self.owner) {
		self.owner->on_notify_state(characteristic, error);
	}
}

- (void)peripheralIsReadyToSendWriteWithoutResponse:(CBPeripheral *)peripheral {
	if (self.owner) {
		self.owner->on_ready_to_send();
	}
}

@end
