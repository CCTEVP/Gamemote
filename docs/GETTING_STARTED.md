# Getting started: run the tracer bullet on your iPhone / iPad

> **Note (2026-11-13):** this guide is for the Godot app, now on the `Godot` branch. `main` is the
> native Xcode app: see the README's "Open in Xcode" section.

This guide covers the PoC workflow end to end: pull `main` → build the native
Bluetooth extension → try the app on your Mac → export to Xcode → install on
iPhone/iPad → connect to the simulated device running on your Mac.

You do **not** need a microcontroller yet: `tools/gm_sim.py` turns your Mac into a
Gamemote-compatible BLE device.

---

## 0. What you need (once)

| Item | Notes |
|---|---|
| Mac with **Xcode** (current version) | Open Xcode once so it installs its components. |
| **Godot 4.7.2** (standard, not .NET) | <https://godotengine.org/download>. 4.5 or newer works too. |
| Godot **export templates** | In Godot: *Editor → Manage Export Templates → Download and Install*. |
| **Python 3.10+** (3.12 recommended) | `brew install python@3.12`. The `python3` that comes with Xcode is 3.9: too old (PyObjC then tries to compile and fails). |
| iPhone and/or iPad + USB cable | iOS/iPadOS 16+: turn on *Settings → Privacy & Security → Developer Mode* (it restarts the device). |
| A free **Apple ID** signed in to Xcode | *Xcode → Settings → Accounts → +*. The $99/year program is **not** needed (see the end of this guide). |

## 1. Get the code

First time:

```bash
git clone --recurse-submodules https://github.com/CCTEVP/Gamemote.git
cd Gamemote
```

Later updates:

```bash
git pull origin main
git submodule update --init
```

## 2. Build the Bluetooth extension (iOS + macOS)

```bash
./native/gamemote_ble/build_apple.sh
```

- The first run takes a few minutes because it compiles godot-cpp. Later runs are incremental.
- It installs SCons into `native/gamemote_ble/.venv` if you don't have it.
- Output goes to `app/addons/gamemote_ble/bin/` (git-ignored).
- Re-run it whenever `native/` changes. App-only changes don't need it.

## 3. Try the app on your Mac (mock device)

1. Open Godot, *Import*, and pick `app/project.godot`.
2. Press **Run** (F5). On a desktop the app uses the built-in **Mock device**.
3. Press *Scan* → `GM-Mock` → *Connect*. Move the sliders, press *Beep* and *STOP*, and run the
   demo routine with *Run live* and *Transfer & run*.

That proves the app logic. Bluetooth itself is tested on the phone (steps 4–6).

> Desktop preview of device sizes: *Project → Project Settings → Editor → Run → Main Run Args* =
> `-- --ui-scale=2`, then resize the window (e.g. 1688×780 is an iPhone in landscape).

## 4. Start the simulated device on your Mac

```bash
python3.12 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
.venv/bin/python tools/gm_sim.py
```

- macOS asks to allow Bluetooth for your terminal app the first time. Allow it, then re-run.
- The simulator advertises as **GM-Sim** and prints every channel change, action and routine step.
- `--no-transfer` makes it behave like a board that only supports Live mode. `-v` prints every frame.
- Leave it running. The Mac can't connect to itself, so the iPhone/iPad is the client.

## 5. Export to Xcode

1. In Godot: *Project → Export… →* select the **iOS** preset (already in the repo).
2. Fill in:
   - **App Store Team ID**: your 10-character team ID. With a free account, if you don't know it
     yet, type any placeholder (e.g. `AAAAAAAAAA`), finish this step and step 6, then read the
     real ID from the exported project:
     `grep -m1 DEVELOPMENT_TEAM build/ios/Gamemote.xcodeproj/project.pbxproj`, and put it in the preset.
   - **Bundle Identifier**: `com.cctevp.gamemote` is preset. Free accounts need an ID nobody else
     has registered; if Xcode complains, change it (e.g. `com.<yourname>.gamemote`).
3. The preset already sets: *Export Project Only* (Godot writes an Xcode project instead of
   building), **iPhone & iPad**, the Bluetooth permission text, and full-screen on iPad.
4. Click **Export Project**, choose `build/ios/Gamemote.ipa` (the folder `build/` is git-ignored),
   and keep *Export With Debug* on.

## 6. Install from Xcode

1. Open `build/ios/Gamemote.xcodeproj`.
2. Select the **Gamemote** target → *Signing & Capabilities* → tick *Automatically manage signing*
   and choose your **Personal Team**.
3. Plug in the iPhone/iPad, select it as the run destination, and press **Run (⌘R)**.
4. The first time, the device refuses to open the app: go to *Settings → General → VPN & Device
   Management →* your Apple ID *→ Trust*, then run again.

After you change the Godot project: export again into the same folder (step 5.4) and press Run
in Xcode. With the real Team ID in the preset, you don't need to re-select the team.

## 7. What to test (tracer bullet checklist)

The app opens on the **3D table**: a clay gamepad on the left (stick, face buttons, STOP) and the
routine board on the right. Press **Connect** in the top bar to connect to the first device found.
*Classic view* switches to the original test screen, which the checklist below still uses;
*Table view* there brings you back.

| On the table | Expected |
|---|---|
| Push the stick up / right | Servo / Motor follow in the simulator terminal; the stick tilts and springs back on release |
| Hold the stick and press LED with a second finger | Both work at once (multitouch); LED goes off on release |
| Drag a palette tile under the chain | It snaps in; tap it to change its value; drag it back to the palette to delete |
| ▶ Live / ⇪ Transfer | The routine runs; the running block glows |
| Drag on empty table space | The view turns and tilts to show the 3D shapes; let go and it springs back to top-down |


With `gm_sim.py` running on the Mac:

| # | Do this on the iPhone/iPad | Expected |
|---|---|---|
| 1 | Launch | iOS asks for Bluetooth permission → Allow. Status: *Idle*. |
| 2 | *Scan* | `GM-Sim` appears with an RSSI value. |
| 3 | *Connect* | Status *Connected* within ~3 s; channels LED/Servo/Motor and a *Beep* button appear. |
| 4 | Drag a slider | The simulator terminal prints the new value almost immediately. |
| 5 | Watch *Round trip* | p50/p95 values; record them (target p95 ≤ 60 ms). |
| 6 | Hold a slider away from neutral, then press the Home button / swipe up | The terminal shows *all channels → neutral* right away (the app sends STOP_ALL when it goes to the background). |
| 7 | *Run live* | Servo waves 0→180 five times, then Beep; the status shows each step. |
| 8 | *Run live*, then press *Disconnect* | The routine stops; the simulator goes neutral (Live mode needs the link). |
| 9 | Connect, *Transfer & run*, then press *Disconnect* | The simulator **keeps running** the routine to the end (Transferred mode). |
| 10 | While connected, stop `gm_sim.py` (Ctrl+C) and start it again | The app shows *Reconnecting…*, then *Connected* by itself. |
| 11 | Restart `gm_sim.py --no-transfer`, reconnect | *Transfer & run* is disabled; *Run live* still works. |
| 12 | Repeat on the iPad | The same results, and the layout uses the larger screen. |

Please send back: the RTT numbers, any row that behaved differently, and the Xcode console log
if something failed.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Xcode: `Undefined symbols … CBCentralManager` | Re-run `build_apple.sh` and export again. If it persists, add *CoreBluetooth.framework* under *Build Phases → Link Binary With Libraries* and report it. |
| App log: `Bluetooth: missing NSBluetoothAlwaysUsageDescription` | The app was exported without the Bluetooth permission text. The `Gamemote iOS export` plugin (*Project → Project Settings → Plugins*, must be enabled) adds it on every iOS export: pull, export again, and check the export log shows `Gamemote iOS export: added Info.plist keys` (or that the preset already had them). |
| Xcode log: `Could not vibrate using haptic engine: (null)` | Harmless: Godot 4.7.2 prints this after every vibration; `(null)` means no error. |
| Xcode: `Undefined symbols: _SDL_IsIPad, _SDL_IsAppleTV` | Godot 4.7.x template bug; fixed by our extension. Pull, re-run `build_apple.sh`, export again, Clean Build Folder. |
| `GM-Sim` not found | Check that Bluetooth is on on the Mac, the terminal has Bluetooth permission (*System Settings → Privacy & Security → Bluetooth*), and the name is ≤ 10 characters. Also try `python tools/gm_cli.py scan` from another computer. |
| *Bluetooth* is greyed out in the transport menu | The extension binaries weren't found: run `build_apple.sh` (step 2) before exporting. |
| App stops opening after a week | Free-account installs expire after 7 days. Press Run in Xcode again. |
| `godot-cpp/SConstruct not found` | `git submodule update --init` |
| Godot crashes when you **close** the editor the first time you open the project | A known Godot bug when an extension is loaded for the first time ([godotengine/godot#111048](https://github.com/godotengine/godot/issues/111048)). Your project is already saved; reopen it and it won't happen again. |

## Do I need the $99/year Apple Developer Program?

**No, not for this project as a hobby.** A free Apple ID ("Personal Team") can install the app
on your own iPhone and iPad from Xcode, and Bluetooth needs no special entitlement. The limits of
a free account:

- installs expire after **7 days**, so you re-run from Xcode,
- only a few sideloaded apps per device at a time (3), and a weekly limit on new app IDs,
- no TestFlight, no App Store, and some capabilities (push notifications, iCloud) are unavailable.
  The PoC uses none of them.

Pay for the program when you want to share builds with other people (TestFlight), have installs
that last a year, or publish to the App Store.
