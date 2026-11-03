# Gamemote — Proof of Concept Plan

> **Goal of the PoC:** prove the whole pipeline end to end, from an iPhone app built in
> Godot, through a native CoreBluetooth bridge and a BLE protocol, to firmware on a
> microcontroller that moves real things. The app supports two ways to control the device:
>
> 1. **Live control**: a game-controller-style UI (joystick, buttons, slider) bound to device actions.
> 2. **Routines**: sequences built in a Scratch-like block editor and run from the app.
>
> The PoC is meant to answer *"does this stack work, and is it pleasant to build on?"*.
> It is not a first version of the product.

---

## 0. Scope

| In the PoC | Deferred to later phases |
|---|---|
| iOS app (Godot 4.x), single device connection | Android build (architecture keeps it possible) |
| One reference board (ESP32-S3) running our firmware | Many board types, OTA firmware updates |
| GATT protocol v0 with a capability descriptor | Pairing/bonding, encryption, auth |
| One fixed controller layout with re-bindable controls | Layout designer (drag controls around) |
| Block editor: set, trigger, wait, repeat, stop | Conditions, sensors, variables, events, functions |
| Routines run **in the app** | Routines uploaded to and run **on the device** |
| Local storage of layouts and routines | Cloud sync, sharing |

### PoC exit criteria (measurable)

| # | Criterion | Target |
|---|---|---|
| 1 | Scan → connected → ready | ≤ 3 s |
| 2 | Live control round-trip (PING/PONG) while streaming at 30 Hz | p95 ≤ 60 ms |
| 3 | Failsafe: actuators go neutral after link loss, app kill or app backgrounding | ≤ 500 ms |
| 4 | Auto-reconnect after a device reboot, without restarting the app | works 10/10 |
| 5 | Routine timing error per step | ≤ 50 ms, no cumulative drift |
| 6 | Stability | 30-minute session with no crash |

---

## 1. Hard constraints to design around

These are facts about the platform. They shape every later decision.

1. **iOS only talks BLE (GATT) to non-MFi hardware.** Bluetooth Classic serial (SPP; HC-05/HC-06
   modules, ESP32 `BluetoothSerial`) **will not work** on iPhone without Apple's MFi program. A
   "compatible micro circuit" therefore means *a BLE peripheral that implements the Gamemote GATT profile*.
2. **CoreBluetooth does not work in the iOS Simulator.** Every BLE test needs a real iPhone. The
   same CoreBluetooth code does run on **macOS**, which gives us a fast desktop test bench.
3. **iOS builds need a Mac with Xcode.** A free Apple ID can sideload to your own phone (the
   provisioning expires after 7 days). The Apple Developer Program ($99/yr) is needed for TestFlight.
4. **`NSBluetoothAlwaysUsageDescription` must be in Info.plist**, or the app is killed the
   first time it touches CoreBluetooth.
5. **iOS hides MAC addresses.** Peripherals get a per-app UUID. Find devices by **advertised
   service UUID**, not by address.
6. **iOS suspends apps in the background**, which drops the BLE link. The device must fail safe
   on its own; it cannot rely on the app.
7. **BLE timing:** iOS connection intervals are typically 15–30 ms, and the default ATT payload is
   20 bytes (iOS usually negotiates a larger MTU, often 185+). Keep live-control frames small and
   send *state*, not deltas.

---

## 2. Architecture

```
┌──────────────────────────────── iPhone ─────────────────────────────────┐
│  Godot app (GDScript)                                                    │
│                                                                          │
│   ┌──────────────┐     ┌────────────────────────┐    ┌───────────────┐   │
│   │ Controller   │     │ Routine editor (blocks)│    │ Debug overlay │   │
│   │ screen       │     │ + Routine VM           │    │ RTT/RSSI/log  │   │
│   └──────┬───────┘     └───────────┬────────────┘    └───────────────┘   │
│          └────────── actions ──────┘                                     │
│                         ▼                                                │
│   ActionRegistry  ◄──── capability JSON (read from device INFO char)     │
│                         ▼                                                │
│   DeviceService (connection state machine, 30 Hz ControlStreamer)        │
│                         ▼                                                │
│   Protocol (pure GDScript: encode/decode frames, unit-tested)            │
│                         ▼                                                │
│   Transport  ──  BleTransport │ MockTransport │ (WebSocketTransport later)│
│                         ▼                                                │
│   GDExtension "gamemote_ble" (Objective-C++ / CoreBluetooth)             │
│   (generic BLE central with no protocol knowledge; also builds for macOS) │
└─────────────────────────┬────────────────────────────────────────────────┘
                          │ BLE GATT
                          │  CMD  (write without response)   app → device
                          │  EVT  (notify)                   device → app
                          │  INFO (read)                     capability JSON
┌─────────────────────────▼──────────────── ESP32-S3 ──────────────────────┐
│  NimBLE GATT server → frame parser → channel/action dispatcher           │
│       → actuators (RGB LED, servo, buzzer)                               │
│  failsafe watchdog (500 ms)        telemetry notifier (5 Hz)             │
└──────────────────────────────────────────────────────────────────────────┘
```

**The main design idea is that "actions" are the shared vocabulary.** The device *describes* what
it can do: continuous **channels** (motor speed, servo angle, LED brightness) and discrete
**actions** (beep, blink pattern). The controller maps touches to actions, and routines sequence
the same actions. Both paths produce the same protocol frames, so firmware never knows which UI
sent a command, and any board that implements the profile and describes itself is "compatible".

---

## 3. Stage-by-stage recommendations

### Stage 1 — Hardware (reference device)

**Recommendation: ESP32-S3 dev board** (e.g. ESP32-S3-DevKitC-1, or Seeed XIAO ESP32-S3 for a small form factor).

- BLE 5, a large community, cheap, Arduino and ESP-IDF support, and **Wi-Fi as a bonus** (later
  uses: OTA updates and a WebSocket debug transport).
- PoC kit (≈ $25–35): dev board (many have an on-board WS2812 RGB LED), **SG90 micro servo**,
  **passive buzzer**, **potentiometer** (an analog input, so telemetry shows device→app data),
  breadboard and jumpers. Optional: DRV8833 + 2 small DC motors if you want a mini-rover demo.
- Power the servo from 5 V (USB) rather than the 3.3 V rail, and share ground.
- **Alternative:** nRF52840 (Seeed XIAO nRF52840, Adafruit Feather) if the final product is
  battery-first, because its BLE power consumption is much better. The protocol is portable,
  so the board choice can change later.
- **Avoid:** HC-05/HC-06 (Bluetooth Classic, see constraint 1). HM-10 (BLE UART) works on iOS
  but leaves logic on a second MCU, so it is more complex than needed.

### Stage 2 — Firmware

**Recommendation: PlatformIO + Arduino-ESP32 core + NimBLE-Arduino.**

- NimBLE uses much less RAM and flash than the default Bluedroid stack and is the usual
  choice for BLE-only ESP32 projects. It is Apache-2.0 licensed.
- PlatformIO gives a reproducible build (`platformio.ini` pins versions) and a CLI that runs in CI.
- Module layout:
  - `ble_service.*`: advertising (service UUID in the advertising packet, name in the scan
    response) and the GATT server with CMD/EVT/INFO.
  - `protocol.*`: frame parsing and building, with constants shared with the app spec.
  - `channels.*`: maps channel IDs to actuators (LED PWM/RGB, servo, buzzer).
  - `failsafe.*`: **if no valid frame arrives for 500 ms, set every channel to neutral.** This
    also runs on disconnect.
  - `telemetry.*`: notifies battery/pot value/flags at 5 Hz while connected.
- Threading: BLE callbacks run in the NimBLE task. Push frames into a FreeRTOS queue and apply
  them in `loop()`, so actuators are only touched from one place.
- Logging: serial at 115200 baud, plus an optional `LOG` notify frame so logs show up in the app.
- Re-advertise immediately on disconnect so auto-reconnect works.

### Stage 3 — BLE protocol v0

**Recommendation: one custom service with three characteristics (a UART-style split), and small
little-endian binary frames.** Spec lives in `protocol/PROTOCOL.md`. **Golden test vectors** in
`protocol/test_vectors.json` are run by *both* the app tests and the firmware tests, so the two
sides cannot drift apart.

| Characteristic | UUID | Properties | Purpose |
|---|---|---|---|
| Service | `4afc0001-28d2-43f3-abb0-be04c0c1413f` | — | Advertised; used for scan filtering |
| CMD | `4afc0002-28d2-43f3-abb0-be04c0c1413f` | Write, Write Without Response | App → device frames |
| EVT | `4afc0003-28d2-43f3-abb0-be04c0c1413f` | Notify | Device → app frames |
| INFO | `4afc0004-28d2-43f3-abb0-be04c0c1413f` | Read | Capability descriptor (JSON, ≤ 512 B) |

Frame: `[type:u8][seq:u8][payload…]`, one frame per write, ≤ 20 bytes for now.

| Type | Dir | Payload | Notes |
|---|---|---|---|
| `0x01 SET` | → | `(ch:u8, value:i16) × N` | Continuous channels. Idempotent, last write wins. Sent at 30 Hz while controls are active. |
| `0x02 TRIGGER` | → | `action:u8, params…` | Discrete one-shot; device replies `ACK`. |
| `0x03 STOP_ALL` | → | — | Emergency stop: all channels neutral. Always sent with response. |
| `0x04 PING` | → | `t:u32` | RTT measurement + keepalive (4 Hz when nothing else is being sent). |
| `0x81 ACK` | ← | `seq:u8, status:u8` | For TRIGGER/STOP_ALL. |
| `0x82 PONG` | ← | `t:u32` | Echo of PING. |
| `0x83 TELEMETRY` | ← | `battery_mV:u16, flags:u8, values…` | 5 Hz. |
| `0x84 LOG` | ← | UTF-8 text | Debug. |

Capability descriptor (INFO) example:

```json
{
  "proto": 0,
  "name": "Gamemote PoC",
  "channels": [
    {"id": 1, "name": "LED",   "kind": "level", "min": 0, "max": 255, "neutral": 0},
    {"id": 2, "name": "Servo", "kind": "angle", "min": 0, "max": 180, "neutral": 90}
  ],
  "actions": [
    {"id": 1, "name": "Beep", "params": [{"name": "ms", "min": 10, "max": 2000, "default": 200}]}
  ],
  "telemetry": [{"name": "Knob", "min": 0, "max": 4095}]
}
```

Why these choices:
- **State streaming with write-without-response** for live control gives low latency, and a
  dropped packet does not matter because the next one carries the full state. **Write-with-response
  + ACK** is used where delivery matters (STOP_ALL, triggers).
- **Self-describing device (INFO):** the app builds controller bindings and the block palette
  from the device, so new hardware needs no app update.
- **Binary over text:** fits in 20 bytes, is trivial to parse on an MCU, and test vectors keep
  it debuggable. A text protocol is easier to read in nRF Connect, but it is slower to parse and
  easy to get wrong.

### Stage 4 — Native iOS bridge (highest risk, so it is tackled early in M2)

**Recommendation: write our own small GDExtension in Objective-C++ with `godot-cpp`, targeting
iOS and macOS from the same source.**

- **Keep the bridge generic and protocol-agnostic** (~400–600 LOC). All protocol logic lives in
  GDScript, where it is easy to change and test. A later Android version (a Godot Android plugin
  in Kotlin) only needs to implement the same small API.
- Proposed API (class `GamemoteBle`):
  - Methods: `start_scan(service_uuids: PackedStringArray)`, `stop_scan()`, `connect_peripheral(id)`,
    `disconnect_peripheral()`, `read(char_uuid)`, `write(char_uuid, data: PackedByteArray, with_response: bool)`,
    `set_notify(char_uuid, enabled)`, `get_max_write_length()`, `can_send_without_response()`, `poll()`.
  - Signals: `adapter_state_changed(state)`, `peripheral_found(id, name, rssi)`, `connected(id)`,
    `disconnected(id, error)`, `services_discovered()`, `value_read(char_uuid, data)`,
    `notified(char_uuid, data)`, `write_completed(char_uuid, error)`, `ready_to_send()`.
- **Threading:** run `CBCentralManager` on its own serial dispatch queue. Callbacks push events
  into a mutex-protected queue, and `poll()`, called from `_process` on Godot's main thread,
  drains the queue and emits signals. This avoids races with the engine and behaves the same on
  macOS and iOS.
- **Flow control:** for write-without-response, respect `canSendWriteWithoutResponse` and
  `peripheralIsReadyToSendWriteWithoutResponse`. The streamer **coalesces** frames: only the
  newest SET is sent, and stale ones are dropped instead of queued.
- **Info.plist:** add `NSBluetoothAlwaysUsageDescription` through the iOS export preset's
  `application/additional_plist_content`, then check the exported `Info.plist`.
- **macOS build of the same extension** gives real-BLE testing on the desktop without deploying
  to the phone each time. Caveat: macOS asks for Bluetooth permission per app, so the editor
  binary may be denied. Fall back to an exported macOS build if that happens.
- Packaging: build static libraries with SCons (`platform=ios arch=arm64`, `platform=macos`) and
  wrap the iOS one into an `.xcframework` (godot-cpp ships a reference script). **Pin
  `godot-cpp` to the same minor version as the Godot editor.** iOS GDExtension packaging changed
  in 4.3, so version mismatch is the most common failure.

Options considered:
- *Existing Asset Library BLE plugins* (e.g. GDBLE, Rust/btleplug-based): worth **a 2-hour
  timeboxed evaluation**, because btleplug has a CoreBluetooth backend. The listings don't confirm
  iOS export support, so don't depend on one without trying it.
- *SimpleBLE (C++)*: cross-platform and convenient, but **BUSL-1.1 since Jan 2025**, so commercial
  use needs a paid licence. Avoid it unless that is acceptable.
- *Swift via SwiftGodot*: nicer language, but one more toolchain layer to debug. Revisit after the PoC.
- *Classic `.gdip` iOS plugin*: iOS-only, so it loses the macOS test bench. GDExtension is preferred.

### Stage 5 — Godot app architecture

**Recommendation: Godot 4.6.x (latest stable, pinned in the repo), GDScript only, autoload
services, and a transport abstraction with a mock.**

- **Autoloads:**
  - `DeviceService`: state machine `IDLE → SCANNING → CONNECTING → DISCOVERING → READY →
    RECONNECTING`, owns the active `Transport`, and emits app-level signals.
  - `ActionRegistry`: built from INFO JSON; lists channels, actions and parameter ranges.
  - `ControlStreamer`: collects current channel values from the active inputs, sends `SET` at
    30 Hz when values change and `PING` at 4 Hz otherwise. Measures RTT.
  - `Storage`: JSON files under `user://` for layouts and routines.
- **Transports** (one GDScript interface):
  - `BleTransport` wraps the GDExtension.
  - `MockTransport` is a simulated device inside the app: it serves the same INFO JSON, answers
    PING, and logs SETs. **All UI work can happen on any desktop with no hardware.**
  - `WebSocketTransport` (later): ESP32 over Wi-Fi, or a Python simulator.
- **Project settings for an app (not a game):** enable `application/run/low_processor_mode`
  (saves battery by not redrawing every frame), stretch mode `canvas_items` + aspect `expand`,
  respect `DisplayServer.get_display_safe_area()` (notch), and lock to landscape for the PoC.
- **Tests:** gdUnit4 (or GUT) running headless in CI for `Protocol`, the routine compiler and the
  VM, using the shared test vectors.

### Stage 6 — Live controller UI

**Recommendation: custom touch controls that handle `InputEventScreenTouch`/`ScreenDrag` by
finger index, not stock `Button`s.**

- Stock Control buttons rely on emulated mouse input, which only follows the **first** touch.
  Holding the joystick while pressing a button will not work with them. Custom controls (or
  `TouchScreenButton`) give true multitouch.
- PoC layout: **left virtual joystick** (2 axes), **4 face buttons**, **1 slider**, and a large
  **STOP** button that is always visible.
- Binding model (saved as JSON):
  - axis → channel (scale, dead-zone, invert)
  - button → trigger action | momentary channel (value while held, neutral on release) | toggle
  - slider → channel
- Edit mode: tap a control, then pick a channel or action from `ActionRegistry`.
- **Cheap extra: physical gamepads.** Godot supports MFi/Xbox/PlayStation controllers on iOS.
  Route both virtual and physical input through the same binding layer.
- On release, lift the finger and the channel returns to neutral. On app background, send
  `STOP_ALL`, with the device failsafe as backup.

### Stage 7 — Routine editor (Scratch-like) and runner

**Recommendation: a custom block-stacking editor built from Godot Controls, using Godot's
built-in drag-and-drop (`_get_drag_data` / `_can_drop_data` / `_drop_data`).**

- PoC blocks:
  - **Hat:** `When run`
  - **Action:** `Set [channel] to [value]`, `Trigger [action] (params)`
  - **Control:** `Wait [ms]`, `Repeat [n] { … }` (a C-block), `Stop all`
  - Stretch goals: `Forever`, `Wait until [telemetry] > [x]`, `If … then`
- UI: palette on the left, script area as a `ScrollContainer` with nested `VBoxContainer`s
  (C-blocks hold a child container). Show an insertion marker while dragging. Parameters are
  `SpinBox` / `OptionButton` inside each block, filled from `ActionRegistry`, so typing is rarely
  needed.
- **Data model (JSON AST):**

  ```json
  {"version": 0, "name": "Wave", "blocks": [
    {"op": "set", "ch": 2, "value": 0},
    {"op": "repeat", "times": 3, "body": [
      {"op": "set", "ch": 2, "value": 180}, {"op": "wait", "ms": 500},
      {"op": "set", "ch": 2, "value": 0},   {"op": "wait", "ms": 500}
    ]},
    {"op": "trigger", "action": 1, "params": {"ms": 200}}
  ]}
  ```

- **Runner: compile the AST to a flat instruction list** (`SET`, `TRIGGER`, `WAIT`,
  `LOOP n`, `END_LOOP`, `HALT`) and step it with a small VM in `_process`.
  - Wait deadlines are computed from the *scheduled* time, not "now", so there is no drift.
  - The VM emits `step_started(block_id)` so the running block is highlighted in the editor.
  - `stop()` halts immediately and sends `STOP_ALL`.
  - **Why flat bytecode:** the same program can later be serialized and **uploaded to the MCU**
    (Phase 2), so routines keep running after a disconnect and get MCU-precise timing.

Options considered:
- *GraphEdit (built into Godot)*: fast to build, but node-and-wire graphs suit data flow, not
  step-by-step sequences, and are fiddly on a phone screen. Useful later for "advanced mode".
- *Google Blockly in a WebView*: a polished Scratch look, but Godot has no built-in iOS WebView,
  so it would need a second native plugin plus a JS bridge. Not worth it for a PoC. Reconsider
  if the editor becomes the main product.

### Stage 8 — Build, sign and deploy pipeline

| Piece | Tooling | Where it runs |
|---|---|---|
| Firmware | `pio run -t upload`, `pio device monitor` | Any OS + USB; CI: ubuntu |
| GDExtension | SCons + godot-cpp → `.xcframework` (iOS), `.framework`/dylib (macOS) | Mac; CI: `macos-latest` |
| App (desktop, Mock) | Godot editor / headless | Any OS; CI: ubuntu (tests) |
| App (iOS) | Godot export → Xcode project → sign → run on iPhone | Mac + iPhone (manual in PoC) |

- **CI (GitHub Actions), PoC level:**
  1. `firmware`: PlatformIO build plus protocol test vectors.
  2. `app-tests`: Godot headless, running gdUnit4 tests against `MockTransport`.
  3. `native`: macOS runner builds the iOS and macOS extension binaries and uploads them as artifacts.
  - iOS signing and TestFlight upload (fastlane) come after the PoC.
- Pin versions: Godot editor, export templates, godot-cpp, the PlatformIO platform and NimBLE.
  Record them in `README.md`.

### Stage 9 — Testing and debugging toolkit

Test in layers, from the device outward, so each failure points at one layer:

1. **Firmware ↔ nRF Connect / LightBlue (iPhone app store):** write raw bytes to CMD and watch
   EVT. This proves the firmware before any app code exists.
2. **Firmware ↔ `tools/gm_cli.py` (Python + `bleak`, runs on Mac/Linux/Windows):** scan,
   read INFO, send SET/TRIGGER, and print PING RTT stats (p50/p95). This is the **reference
   client** and protocol oracle.
3. **App ↔ `MockTransport`:** all UI and VM logic, on the desktop.
4. **App (macOS build) ↔ real device:** the native bridge with fast iteration.
5. **App (iPhone) ↔ real device:** the real end-to-end path.

The in-app debug overlay shows connection state, RSSI, MTU, frames per second, RTT p50/p95 and the
LOG stream. It is needed to check the exit criteria.

---

## 4. Milestones

**Tracer bullet first:** get the thinnest possible slice working on real hardware (one button on
the iPhone lights the LED) before building any of the UI. Effort is in rough developer-days.

| # | Milestone | Effort | Exit criteria |
|---|---|---|---|
| M0 | **Setup:** order hardware; install Mac/Xcode/Godot/PlatformIO; repo skeleton; `PROTOCOL.md` v0 | 1–2 d | Toolchains build "hello world" for each part |
| M1 | **Firmware + protocol:** advertise, INFO, SET/TRIGGER/STOP_ALL/PING, failsafe, telemetry; `gm_cli.py` | 2–4 d | LED, servo and buzzer driven from nRF Connect and `gm_cli.py`; RTT measured; failsafe verified |
| M2 | **Native bridge spike (go/no-go):** GDExtension scan/connect/read/write/notify; a minimal Godot scene with a Connect button and an LED toggle | 3–5 d | **Button on the iPhone toggles the LED, and telemetry appears in the log.** If this stalls past ~7 days, re-evaluate the stack (§6). |
| M3 | **App core:** DeviceService state machine, Ble + Mock transports, Protocol + tests, ActionRegistry from INFO, connect screen, auto-reconnect, debug overlay | 2–3 d | Exit criteria 1 and 4 met |
| M4 | **Live controller:** multitouch joystick/buttons/slider, bindings + edit mode, 30 Hz streamer, STOP | 3–4 d | Joystick drives the servo, a button beeps, criteria 2 and 3 met |
| M5 | **Routine editor + VM:** palette, drag/drop stacking, params, nested repeat, save/load, compile → VM, highlight, run/stop | 5–7 d | Build "wave servo 3× then beep", run it, stop it mid-run → device neutral; criterion 5 met |
| M6 | **Hardening + evaluation:** walk-away, app-kill, device-reboot and background tests; 30-min soak; demo video; retrospective | 2–3 d | All exit criteria met; written go/no-go for Phase 2 |

**Total: about 18–28 developer-days (4–6 weeks for one person).** M2 carries the most risk and
gates everything after it.

### After the PoC (likely Phase 2 candidates)

- On-device routine execution (upload bytecode via a new `ROUTINE_*` frame family).
- Layout designer (drag controls, multiple pages, gyro/tilt input).
- Sensors in blocks (`wait until`, `if`), variables, events.
- Android transport (Kotlin Godot plugin with the same API as `GamemoteBle`).
- Security: BLE bonding/encryption, signed firmware, OTA updates over BLE or Wi-Fi.

---

## 5. Repository layout

```
Gamemote/
├── app/                      # Godot 4.6.x project (GDScript)
│   ├── addons/gamemote_ble/  # .gdextension + built binaries (from native/)
│   ├── core/                 # device_service.gd, protocol.gd, action_registry.gd,
│   │                         # control_streamer.gd, storage.gd, transports/
│   ├── routines/             # ast, compiler, vm
│   ├── ui/                   # connect/, controller/, editor/, debug/
│   └── tests/
├── native/gamemote_ble/      # GDExtension source (Objective-C++), SConstruct
│   └── godot-cpp/            # git submodule, pinned to the Godot minor version
├── firmware/                 # PlatformIO project (ESP32-S3, NimBLE-Arduino)
├── protocol/                 # PROTOCOL.md, test_vectors.json, capability.schema.json
├── tools/                    # gm_cli.py (bleak), device simulator
├── docs/                     # this plan, decisions (ADRs), wiring diagrams
└── .github/workflows/        # firmware, app-tests, native
```

---

## 6. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Godot iOS native toolchain friction (xcframework packaging, plugin docs lagging behind 4.6) | High | Do M2 first, pin versions, keep the bridge tiny and generic, use the macOS build of the same code for fast loops. **Fallback stack: Flutter + flutter_blue_plus.** |
| Multitouch issues with stock Controls | Medium | Custom touch controls keyed by finger index (Stage 6) |
| BLE latency and jitter on iOS | Medium | State streaming, coalescing, write-without-response, measure RTT from day one |
| Link loss while actuators are moving | High (safety) | Device-side 500 ms failsafe, STOP_ALL on background, always-visible STOP button |
| Battery and heat from continuous rendering | Low–Med | `low_processor_mode`; render only on change |
| Godot is weaker than native UI for text entry and accessibility | Low (PoC) | Touch-first editor with pickers and spin boxes; little typing |
| Licensing surprises | Medium | Godot (MIT), godot-cpp (MIT), NimBLE (Apache-2.0), bleak (MIT); avoid BUSL libraries (SimpleBLE) unless licensed |

### Stack alternatives (if the M2 gate fails)

| Stack | BLE | Scratch-like editor | Controller UI | Notes |
|---|---|---|---|---|
| **Godot + own GDExtension** (chosen) | Custom bridge (~500 LOC) | Custom, native feel | Excellent; gamepad support built in | Best fit for game-like UX; cross-platform UI |
| Flutter + flutter_blue_plus | Mature, iOS + Android | Custom widgets or Blockly in a WebView | Good | Strongest fallback |
| SwiftUI + CoreBluetooth | Best on iOS | Custom | Good | iOS only |
| React Native + ble-plx | Mature | Blockly in a WebView | OK | JS bridge latency to watch |

---

## 7. Open questions (they change details, not the plan's shape)

1. **What will the final device control?** (rover/robot, lights, animatronic, toy, …) This sets
   the channel types and how strict the real-time needs are.
2. **Do you have a Mac and an iPhone available?** Will you join the Apple Developer Program for TestFlight?
3. **Your experience** with Godot/GDScript, C++/Objective-C and embedded C++: this decides where to
   put more scaffolding or tutorials.
4. **Is Android needed later?** The plan keeps it open either way.
5. **Multiple devices at once** (e.g. two robots)? That affects `DeviceService` and the protocol addressing.
6. **Should routines keep running after the phone disconnects** in v1? If yes, move on-device
   execution earlier.
7. **Commercial product or hobby/open source?** This affects licensing choices and security priorities.
