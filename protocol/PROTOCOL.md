# Gamemote BLE Protocol — v0

Status: **draft for the PoC**. Anything may change until v1; bump `proto` in the capability
descriptor whenever a change breaks compatibility.

A device is **Gamemote-compatible** when it:

1. is a BLE peripheral that advertises the Gamemote service UUID,
2. exposes the three characteristics below, and
3. describes its channels and actions in the INFO characteristic.

The device can be any board. The ESP32-S3 firmware and the Python simulator
(`tools/gm_sim.py`) are reference implementations.

---

## 1. GATT profile

| Item | UUID | Properties | Direction |
|---|---|---|---|
| Service | `4afc0001-28d2-43f3-abb0-be04c0c1413f` | — | advertised |
| CMD | `4afc0002-28d2-43f3-abb0-be04c0c1413f` | Write, Write Without Response | app → device |
| EVT | `4afc0003-28d2-43f3-abb0-be04c0c1413f` | Notify | device → app |
| INFO | `4afc0004-28d2-43f3-abb0-be04c0c1413f` | Read | device → app |

Advertising rules:
- Put the **128-bit service UUID in the advertising packet**, because iOS scans by service UUID.
  The UUID takes 18 of the 31 bytes, so put the local name in the scan response or keep it short
  (≤ 10 characters).
- Re-advertise straight after a disconnect.

## 2. Frames (CMD and EVT)

```
┌──────────┬──────────┬───────────────────────┐
│ type: u8 │ seq: u8  │ payload (0–18 bytes)  │
└──────────┴──────────┴───────────────────────┘
```

- One frame per GATT write or notification. **Max 20 bytes in v0**, which fits the default
  ATT MTU of 23. Larger MTUs may be used in v1.
- All multi-byte integers are **little-endian**.
- `seq` counts up (wrapping at 255) independently on each side. The device echoes the app's `seq`
  in `ACK.ref_seq`.
- Unknown `type`: the device replies `ACK` with status `UNKNOWN_TYPE` and otherwise ignores the frame.

### 2.1 App → device (CMD)

| Type | Name | Payload | GATT write | Reply |
|---|---|---|---|---|
| `0x01` | `SET` | `N × (ch: u8, value: i16)`, N = 1…6 | without response | — |
| `0x02` | `TRIGGER` | `action: u8, params: i16 × P` (P from INFO) | with response | `ACK` |
| `0x03` | `STOP_ALL` | — | with response | `ACK` |
| `0x04` | `PING` | `t: u32` (app clock, ms) | without response | `PONG` |
| `0x10` | `ROUTINE_BEGIN` | `slot: u8, length: u16` | with response | `ACK` |
| `0x11` | `ROUTINE_CHUNK` | `offset: u16, data: u8 × 1…16` | with response | — |
| `0x12` | `ROUTINE_END` | `crc: u16` (CRC-16/CCITT-FALSE of the whole program) | with response | `ACK` |
| `0x13` | `ROUTINE_RUN` | `slot: u8` | with response | `ACK` |
| `0x14` | `ROUTINE_STOP` | — | with response | `ACK` |

### 2.2 Device → app (EVT)

| Type | Name | Payload | When |
|---|---|---|---|
| `0x81` | `ACK` | `ref_seq: u8, status: u8` | After frames that ask for one |
| `0x82` | `PONG` | `t: u32` (copied from PING) | After every PING |
| `0x83` | `TELEMETRY` | `flags: u8, step: u16, values: i16 × T` (T from INFO) | 5 Hz while connected |
| `0x84` | `LOG` | UTF-8 text (≤ 18 bytes) | Any time (debugging) |
| `0x85` | `ROUTINE_STATE` | `state: u8, step: u16` | When a transferred routine changes state |

`ACK.status` values:

| Value | Name | Meaning |
|---|---|---|
| 0 | `OK` | |
| 1 | `UNKNOWN_TYPE` | Frame type not supported |
| 2 | `BAD_LENGTH` | Payload length wrong for the type |
| 3 | `BAD_ID` | Unknown channel, action or slot |
| 4 | `BUSY` | Not allowed now (e.g. upload while a routine is running) |
| 5 | `BAD_PROGRAM` | CRC, length or bytecode validation failed |
| 6 | `UNSUPPORTED` | Feature not supported by this device (e.g. routine transfer) |
| 7 | `TOO_LARGE` | Program bigger than `routines.max_bytes` |

`TELEMETRY.flags` bits: `0` routine running · `1` failsafe tripped since the last frame ·
`2` live control active. `step` is the running routine's instruction index, or `0xFFFF` when
no routine is running.

`ROUTINE_STATE.state`: `0` idle · `1` running · `2` finished · `3` stopped · `4` error.

## 3. Capability descriptor (INFO)

UTF-8 JSON, at most 512 bytes. iOS performs long reads automatically. Serve the descriptor as a
**static value** so the BLE stack handles read offsets.

```json
{
  "proto": 0,
  "name": "Gamemote Sim",
  "fw": "sim-0.1",
  "channels": [
    {"id": 1, "name": "LED",   "kind": "level", "min": 0,    "max": 255, "neutral": 0},
    {"id": 2, "name": "Servo", "kind": "angle", "min": 0,    "max": 180, "neutral": 90},
    {"id": 3, "name": "Motor", "kind": "speed", "min": -100, "max": 100, "neutral": 0}
  ],
  "actions": [
    {"id": 1, "name": "Beep", "params": [{"name": "ms", "min": 10, "max": 2000, "default": 200}]}
  ],
  "telemetry": [{"name": "Knob", "min": 0, "max": 4095}],
  "routines": {"transfer": true, "max_bytes": 512, "max_loop_depth": 4}
}
```

- `kind` is a UI hint: `level` (0…max), `angle`, or `speed` (signed, centred on `neutral`).
- If `routines` is absent, or `transfer` is `false`, the app only offers **Live** routine mode.

## 4. Safety rules (device side, mandatory)

1. **Failsafe:** in Live mode, if no valid frame arrives for **500 ms**, or the link drops, every
   channel goes to `neutral`. The app sends `PING` every 250 ms as a keepalive.
2. `STOP_ALL` sets every channel to neutral **and** stops any running routine.
3. While a **transferred** routine runs, the failsafe is suspended, because outliving the
   connection is the point of this mode. `SET` frames are ignored (the device sends `LOG "busy"` once),
   and `STOP_ALL` / `ROUTINE_STOP` still work.
4. When a routine ends (`HALT`, stop or error), every channel returns to neutral. This applies in
   both modes.

## 5. Routines

### 5.1 Two run modes

| Mode | Who executes | On disconnect | Requires |
|---|---|---|---|
| **Live** | The app's VM, which sends `SET`/`TRIGGER` frames | Device failsafe → neutral | Nothing extra |
| **Transferred** | The device's VM, after upload | Keeps running until done or stopped | `routines.transfer = true` |

Both modes run **the same bytecode**, so a routine behaves identically either way, apart from
timing precision.

### 5.2 Bytecode v0

```
program := "G" "M" version:u8(=0) instruction* HALT
```

| Op | Name | Operands | Size |
|---|---|---|---|
| `0x00` | `HALT` | — | 1 |
| `0x01` | `SET` | `ch: u8, value: i16` | 4 |
| `0x02` | `TRIGGER` | `action: u8, n: u8, params: i16 × n` | 3 + 2n |
| `0x03` | `WAIT` | `ms: u32` | 5 |
| `0x04` | `LOOP` | `count: u16` (0 = forever) | 3 |
| `0x05` | `END_LOOP` | — | 1 |
| `0x06` | `STOP_ALL` | — | 1 |

Validation (on the device, before accepting `ROUTINE_END`):
- magic and version match, the CRC matches, the length matches `ROUTINE_BEGIN.length`,
- every instruction is complete, `LOOP`/`END_LOOP` are balanced, the depth is ≤ `max_loop_depth`,
  and the program ends with `HALT`,
- every channel and action ID exists.

`step` (in TELEMETRY and ROUTINE_STATE) is the **instruction index**, counted from 0 and
excluding the 3-byte header. The app keeps an index → block map, so it can highlight the running
block.

Timing: each `WAIT` deadline is computed from the previous deadline, not from "now", so long
routines don't drift.

### 5.3 Upload sequence

```
app                                  device
 │ ROUTINE_BEGIN slot=0 len=L  ───►  │ allocate, reset buffer
 │ ◄───────────────────────  ACK OK  │
 │ ROUTINE_CHUNK off=0  data[16] ─►  │ (write with response; offset must equal bytes received)
 │ ROUTINE_CHUNK off=16 data[16] ─►  │
 │ …                                 │
 │ ROUTINE_END crc     ───────────►  │ validate
 │ ◄──────────────  ACK OK / BAD_…   │
 │ ROUTINE_RUN slot=0  ───────────►  │ start VM, failsafe suspended
 │ ◄───────────────────────  ACK OK  │
 │ ◄──── ROUTINE_STATE running, 0    │
 │ ◄──── TELEMETRY (step=…)  5 Hz    │
 │       (app may disconnect here; routine keeps running)
 │ ◄──── ROUTINE_STATE finished      │
```

## 6. Test vectors

`protocol/test_vectors.json` holds frames and compiled routines with their exact bytes. Every
implementation (Python tools, the Godot app, firmware) must pass them.
