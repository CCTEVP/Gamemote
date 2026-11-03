"""Transport-agnostic Gamemote device logic (reference behaviour for firmware).

`SimDevice` takes CMD frames and a millisecond clock, and returns the EVT frames
to notify. `tools/gm_sim.py` wraps it in a real BLE peripheral; the unit tests
drive it directly.
"""

from __future__ import annotations

import json
import math
from typing import Any, Callable, Optional

from . import protocol as P
from . import routine as R

DEFAULT_DESCRIPTOR: dict[str, Any] = {
    "proto": 0,
    "name": "Gamemote Sim",
    "fw": "sim-0.1",
    "channels": [
        {"id": 1, "name": "LED", "kind": "level", "min": 0, "max": 255, "neutral": 0},
        {"id": 2, "name": "Servo", "kind": "angle", "min": 0, "max": 180, "neutral": 90},
        {"id": 3, "name": "Motor", "kind": "speed", "min": -100, "max": 100, "neutral": 0},
    ],
    "actions": [
        {"id": 1, "name": "Beep", "params": [{"name": "ms", "min": 10, "max": 2000, "default": 200}]},
    ],
    "telemetry": [{"name": "Knob", "min": 0, "max": 4095}],
    "routines": {"transfer": True, "max_bytes": 512, "max_loop_depth": 4},
}

FAILSAFE_MS = 500
TELEMETRY_PERIOD_MS = 200


class SimDevice:
    def __init__(self, descriptor: Optional[dict[str, Any]] = None,
                 log: Callable[[str], None] = print) -> None:
        self.desc = descriptor or DEFAULT_DESCRIPTOR
        self.log = log
        self.channels = {c["id"]: c for c in self.desc["channels"]}
        self.actions = {a["id"]: a for a in self.desc["actions"]}
        rt = self.desc.get("routines") or {}
        self.transfer_supported = bool(rt.get("transfer"))
        self.max_bytes = int(rt.get("max_bytes", 0))
        self.max_loop_depth = int(rt.get("max_loop_depth", 4))

        self.values = {cid: c["neutral"] for cid, c in self.channels.items()}
        self.seq = 0
        self.connected = False
        self.last_frame_ms = 0.0
        self.last_telemetry_ms = 0.0
        self.failsafe_tripped = False
        self.live_active = False
        self.busy_logged = False

        self.upload: Optional[bytearray] = None
        self.upload_len = 0
        self.upload_error = False
        self.program: Optional[list[R.Instruction]] = None
        self.vm: Optional[R.VM] = None
        self.step = P.NO_STEP

    # ------------------------------------------------------------ helpers

    @property
    def info_bytes(self) -> bytes:
        data = json.dumps(self.desc, separators=(",", ":")).encode()
        if len(data) > 512:
            raise ValueError("capability descriptor exceeds 512 bytes")
        return data

    @property
    def routine_running(self) -> bool:
        return self.vm is not None and self.vm.running

    def _next_seq(self) -> int:
        s = self.seq
        self.seq = (self.seq + 1) & 0xFF
        return s

    def _ack(self, ref_seq: int, status: int) -> bytes:
        return P.encode_ack(self._next_seq(), ref_seq, status)

    def _apply(self, ch: int, value: int) -> None:
        c = self.channels.get(ch)
        if c is None:
            return
        value = max(c["min"], min(c["max"], int(value)))
        self.values[ch] = value

    def _neutral_all(self, reason: str) -> None:
        changed = any(self.values[cid] != c["neutral"] for cid, c in self.channels.items())
        for cid, c in self.channels.items():
            self.values[cid] = c["neutral"]
        self.live_active = False
        if changed:
            self.log(f"  all channels -> neutral ({reason})")

    def _trigger(self, action: int, params: list[int]) -> None:
        a = self.actions[action]
        names = [p["name"] for p in a.get("params", [])]
        defaults = [p.get("default", 0) for p in a.get("params", [])]
        full = list(params) + defaults[len(params):]
        desc = ", ".join(f"{n}={v}" for n, v in zip(names, full))
        self.log(f"  [{a['name']}] ({desc})")

    def _stop_routine(self, state: int) -> list[bytes]:
        if self.vm is None or (not self.vm.running and state != P.RS_FINISHED):
            return []
        self.vm.stop()
        self.step = P.NO_STEP
        self._neutral_all("routine ended")
        self.log(f"  routine {'finished' if state == P.RS_FINISHED else 'stopped'}")
        return [P.encode_routine_state(self._next_seq(), state, P.NO_STEP)]

    # ------------------------------------------------------------ events

    def on_connect(self, now_ms: float) -> None:
        self.connected = True
        self.last_frame_ms = now_ms
        self.last_telemetry_ms = now_ms - TELEMETRY_PERIOD_MS  # report state right away
        self.busy_logged = False
        self.log("central connected")

    def on_disconnect(self, now_ms: float) -> None:
        self.connected = False
        self.log("central disconnected")
        if not self.routine_running:
            self._neutral_all("link lost")

    def handle_cmd(self, data: bytes, now_ms: float) -> list[bytes]:
        """Process one CMD write. Returns EVT frames to notify."""
        try:
            f = P.decode(bytes(data))
        except P.ProtocolError as e:
            if len(data) >= 2:
                status = P.UNKNOWN_TYPE if data[0] not in P.TYPE_NAMES else P.BAD_LENGTH
                return [self._ack(data[1], status)]
            self.log(f"  bad frame: {e}")
            return []

        self.last_frame_ms = now_ms
        self.failsafe_tripped = False
        t, fl = f.type, f.fields
        out: list[bytes] = []

        if t == P.SET:
            if self.routine_running:
                if not self.busy_logged:
                    self.busy_logged = True
                    out.append(P.encode_log(self._next_seq(), "busy"))
                return out
            for ch, value in fl["pairs"]:
                self._apply(ch, value)
            self.live_active = True
        elif t == P.TRIGGER:
            if fl["action"] not in self.actions:
                return [self._ack(f.seq, P.BAD_ID)]
            self._trigger(fl["action"], fl["params"])
            out.append(self._ack(f.seq, P.OK))
        elif t == P.STOP_ALL:
            out += self._stop_routine(P.RS_STOPPED)
            self._neutral_all("STOP_ALL")
            out.insert(0, self._ack(f.seq, P.OK))
        elif t == P.PING:
            out.append(P.encode_pong(self._next_seq(), fl["t"]))
        elif t == P.ROUTINE_BEGIN:
            if not self.transfer_supported:
                return [self._ack(f.seq, P.UNSUPPORTED)]
            if self.routine_running:
                return [self._ack(f.seq, P.BUSY)]
            if fl["slot"] != 0:
                return [self._ack(f.seq, P.BAD_ID)]
            if fl["length"] > self.max_bytes:
                return [self._ack(f.seq, P.TOO_LARGE)]
            self.upload = bytearray()
            self.upload_len = fl["length"]
            self.upload_error = False
            out.append(self._ack(f.seq, P.OK))
        elif t == P.ROUTINE_CHUNK:
            chunk = bytes.fromhex(fl["data"])
            if (self.upload is None or fl["offset"] != len(self.upload)
                    or len(self.upload) + len(chunk) > self.upload_len):
                self.upload_error = True
            else:
                self.upload += chunk
        elif t == P.ROUTINE_END:
            ok = (self.upload is not None and not self.upload_error
                  and len(self.upload) == self.upload_len
                  and P.crc16_ccitt_false(bytes(self.upload)) == fl["crc"])
            if ok:
                try:
                    self.program = R.parse_program(bytes(self.upload), set(self.channels),
                                                   set(self.actions), self.max_loop_depth)
                except R.CompileError as e:
                    self.log(f"  program rejected: {e}")
                    ok = False
            self.upload = None
            if ok:
                self.log(f"  program stored ({self.upload_len} bytes, {len(self.program)} steps)")
            out.append(self._ack(f.seq, P.OK if ok else P.BAD_PROGRAM))
        elif t == P.ROUTINE_RUN:
            if fl["slot"] != 0 or self.program is None:
                return [self._ack(f.seq, P.BAD_ID)]
            if self.routine_running:
                return [self._ack(f.seq, P.BUSY)]
            sink = R.Sink(set=self._apply, trigger=self._trigger,
                          stop_all=lambda: self._neutral_all("routine STOP_ALL"),
                          step=self._on_step)
            self.vm = R.VM(self.program, sink)
            self.vm.start(now_ms)
            self.busy_logged = False
            self.log("  routine running (transferred mode)")
            out.append(self._ack(f.seq, P.OK))
            out.append(P.encode_routine_state(self._next_seq(), P.RS_RUNNING, 0))
        elif t == P.ROUTINE_STOP:
            out.append(self._ack(f.seq, P.OK))
            out += self._stop_routine(P.RS_STOPPED)
        else:
            out.append(self._ack(f.seq, P.UNKNOWN_TYPE))
        return out

    def _on_step(self, step: int) -> None:
        self.step = step

    def tick(self, now_ms: float) -> list[bytes]:
        """Advance time. Returns EVT frames to notify (if connected)."""
        out: list[bytes] = []
        if self.vm is not None and self.vm.running:
            self.vm.tick(now_ms)
            if self.vm.finished:
                out += self._stop_routine(P.RS_FINISHED)
        elif self.live_active and now_ms - self.last_frame_ms > FAILSAFE_MS:
            self.failsafe_tripped = True
            self._neutral_all("failsafe: no frames for 500 ms")

        if self.connected and now_ms - self.last_telemetry_ms >= TELEMETRY_PERIOD_MS:
            self.last_telemetry_ms = now_ms
            flags = 0
            if self.routine_running:
                flags |= P.FLAG_ROUTINE_RUNNING
            if self.failsafe_tripped:
                flags |= P.FLAG_FAILSAFE_TRIPPED
            if self.live_active:
                flags |= P.FLAG_LIVE_ACTIVE
            knob = int(2047 + 2047 * math.sin(now_ms / 2000.0))
            out.append(P.encode_telemetry(self._next_seq(), flags,
                                          self.step if self.routine_running else P.NO_STEP, [knob]))
        return out if self.connected else []
