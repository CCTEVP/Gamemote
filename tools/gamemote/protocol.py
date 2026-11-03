"""Gamemote BLE protocol v0: frame encoding/decoding.

Reference implementation of protocol/PROTOCOL.md. Pure Python, no BLE dependency,
so it can be unit-tested anywhere.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Any

SERVICE_UUID = "4afc0001-28d2-43f3-abb0-be04c0c1413f"
CMD_UUID = "4afc0002-28d2-43f3-abb0-be04c0c1413f"
EVT_UUID = "4afc0003-28d2-43f3-abb0-be04c0c1413f"
INFO_UUID = "4afc0004-28d2-43f3-abb0-be04c0c1413f"

MAX_FRAME = 20
MAX_SET_PAIRS = 6
MAX_CHUNK = 16

# App -> device
SET = 0x01
TRIGGER = 0x02
STOP_ALL = 0x03
PING = 0x04
ROUTINE_BEGIN = 0x10
ROUTINE_CHUNK = 0x11
ROUTINE_END = 0x12
ROUTINE_RUN = 0x13
ROUTINE_STOP = 0x14

# Device -> app
ACK = 0x81
PONG = 0x82
TELEMETRY = 0x83
LOG = 0x84
ROUTINE_STATE = 0x85

TYPE_NAMES = {
    SET: "SET", TRIGGER: "TRIGGER", STOP_ALL: "STOP_ALL", PING: "PING",
    ROUTINE_BEGIN: "ROUTINE_BEGIN", ROUTINE_CHUNK: "ROUTINE_CHUNK",
    ROUTINE_END: "ROUTINE_END", ROUTINE_RUN: "ROUTINE_RUN", ROUTINE_STOP: "ROUTINE_STOP",
    ACK: "ACK", PONG: "PONG", TELEMETRY: "TELEMETRY", LOG: "LOG",
    ROUTINE_STATE: "ROUTINE_STATE",
}
NAME_TYPES = {v: k for k, v in TYPE_NAMES.items()}

# ACK status
OK = 0
UNKNOWN_TYPE = 1
BAD_LENGTH = 2
BAD_ID = 3
BUSY = 4
BAD_PROGRAM = 5
UNSUPPORTED = 6
TOO_LARGE = 7

STATUS_NAMES = {
    OK: "OK", UNKNOWN_TYPE: "UNKNOWN_TYPE", BAD_LENGTH: "BAD_LENGTH", BAD_ID: "BAD_ID",
    BUSY: "BUSY", BAD_PROGRAM: "BAD_PROGRAM", UNSUPPORTED: "UNSUPPORTED", TOO_LARGE: "TOO_LARGE",
}

# TELEMETRY flags
FLAG_ROUTINE_RUNNING = 0x01
FLAG_FAILSAFE_TRIPPED = 0x02
FLAG_LIVE_ACTIVE = 0x04

NO_STEP = 0xFFFF

# ROUTINE_STATE.state
RS_IDLE = 0
RS_RUNNING = 1
RS_FINISHED = 2
RS_STOPPED = 3
RS_ERROR = 4


class ProtocolError(ValueError):
    pass


@dataclass
class Frame:
    type: int
    seq: int
    fields: dict[str, Any] = field(default_factory=dict)

    @property
    def name(self) -> str:
        return TYPE_NAMES.get(self.type, f"0x{self.type:02X}")


def crc16_ccitt_false(data: bytes) -> int:
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no xorout."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def _hdr(t: int, seq: int) -> bytes:
    return bytes((t & 0xFF, seq & 0xFF))


# ---------------------------------------------------------------- encoders

def encode_set(seq: int, pairs: list[tuple[int, int]]) -> bytes:
    if not 1 <= len(pairs) <= MAX_SET_PAIRS:
        raise ProtocolError(f"SET needs 1..{MAX_SET_PAIRS} pairs")
    out = bytearray(_hdr(SET, seq))
    for ch, value in pairs:
        out += struct.pack("<Bh", ch, value)
    return bytes(out)


def encode_trigger(seq: int, action: int, params: list[int] = ()) -> bytes:
    out = bytearray(_hdr(TRIGGER, seq)) + bytes((action,))
    for p in params:
        out += struct.pack("<h", p)
    if len(out) > MAX_FRAME:
        raise ProtocolError("TRIGGER too long")
    return bytes(out)


def encode_stop_all(seq: int) -> bytes:
    return _hdr(STOP_ALL, seq)


def encode_ping(seq: int, t: int) -> bytes:
    return _hdr(PING, seq) + struct.pack("<I", t & 0xFFFFFFFF)


def encode_routine_begin(seq: int, slot: int, length: int) -> bytes:
    return _hdr(ROUTINE_BEGIN, seq) + struct.pack("<BH", slot, length)


def encode_routine_chunk(seq: int, offset: int, data: bytes) -> bytes:
    if not 1 <= len(data) <= MAX_CHUNK:
        raise ProtocolError(f"chunk must be 1..{MAX_CHUNK} bytes")
    return _hdr(ROUTINE_CHUNK, seq) + struct.pack("<H", offset) + bytes(data)


def encode_routine_end(seq: int, crc: int) -> bytes:
    return _hdr(ROUTINE_END, seq) + struct.pack("<H", crc)


def encode_routine_run(seq: int, slot: int) -> bytes:
    return _hdr(ROUTINE_RUN, seq) + bytes((slot,))


def encode_routine_stop(seq: int) -> bytes:
    return _hdr(ROUTINE_STOP, seq)


def encode_ack(seq: int, ref_seq: int, status: int) -> bytes:
    return _hdr(ACK, seq) + bytes((ref_seq & 0xFF, status))


def encode_pong(seq: int, t: int) -> bytes:
    return _hdr(PONG, seq) + struct.pack("<I", t & 0xFFFFFFFF)


def encode_telemetry(seq: int, flags: int, step: int, values: list[int]) -> bytes:
    out = bytearray(_hdr(TELEMETRY, seq)) + struct.pack("<BH", flags, step)
    for v in values:
        out += struct.pack("<h", v)
    if len(out) > MAX_FRAME:
        raise ProtocolError("TELEMETRY too long")
    return bytes(out)


def encode_log(seq: int, text: str) -> bytes:
    data = text.encode("utf-8")[: MAX_FRAME - 2]
    return _hdr(LOG, seq) + data


def encode_routine_state(seq: int, state: int, step: int) -> bytes:
    return _hdr(ROUTINE_STATE, seq) + struct.pack("<BH", state, step)


def encode_routine_upload(first_seq: int, slot: int, program: bytes) -> list[bytes]:
    """Return the full list of frames to upload a program (BEGIN, CHUNKs, END)."""
    seq = first_seq
    frames = [encode_routine_begin(seq, slot, len(program))]
    for off in range(0, len(program), MAX_CHUNK):
        seq += 1
        frames.append(encode_routine_chunk(seq, off, program[off:off + MAX_CHUNK]))
    seq += 1
    frames.append(encode_routine_end(seq, crc16_ccitt_false(program)))
    return frames


# ---------------------------------------------------------------- decoder

def decode(frame: bytes) -> Frame:
    """Decode any frame (either direction). Raises ProtocolError on malformed input."""
    if len(frame) < 2:
        raise ProtocolError("frame shorter than header")
    if len(frame) > MAX_FRAME:
        raise ProtocolError("frame longer than 20 bytes")
    t, seq = frame[0], frame[1]
    p = bytes(frame[2:])
    f: dict[str, Any] = {}

    def need(n: int) -> None:
        if len(p) != n:
            raise ProtocolError(f"{TYPE_NAMES.get(t, t)}: expected {n} payload bytes, got {len(p)}")

    if t == SET:
        if len(p) == 0 or len(p) % 3:
            raise ProtocolError("SET: payload must be N*3 bytes")
        f["pairs"] = [list(struct.unpack_from("<Bh", p, i)) for i in range(0, len(p), 3)]
    elif t == TRIGGER:
        if len(p) < 1 or (len(p) - 1) % 2:
            raise ProtocolError("TRIGGER: bad length")
        f["action"] = p[0]
        f["params"] = [struct.unpack_from("<h", p, i)[0] for i in range(1, len(p), 2)]
    elif t in (STOP_ALL, ROUTINE_STOP):
        need(0)
    elif t in (PING, PONG):
        need(4)
        f["t"] = struct.unpack("<I", p)[0]
    elif t == ROUTINE_BEGIN:
        need(3)
        f["slot"], f["length"] = struct.unpack("<BH", p)
    elif t == ROUTINE_CHUNK:
        if not 3 <= len(p) <= 2 + MAX_CHUNK:
            raise ProtocolError("ROUTINE_CHUNK: bad length")
        f["offset"] = struct.unpack_from("<H", p)[0]
        f["data"] = p[2:].hex()
    elif t == ROUTINE_END:
        need(2)
        f["crc"] = struct.unpack("<H", p)[0]
    elif t == ROUTINE_RUN:
        need(1)
        f["slot"] = p[0]
    elif t == ACK:
        need(2)
        f["ref_seq"], f["status"] = p[0], p[1]
    elif t == TELEMETRY:
        if len(p) < 3 or (len(p) - 3) % 2:
            raise ProtocolError("TELEMETRY: bad length")
        f["flags"], f["step"] = struct.unpack_from("<BH", p)
        f["values"] = [struct.unpack_from("<h", p, i)[0] for i in range(3, len(p), 2)]
    elif t == LOG:
        f["text"] = p.decode("utf-8", errors="replace")
    elif t == ROUTINE_STATE:
        need(3)
        f["state"], f["step"] = struct.unpack("<BH", p)
    else:
        raise ProtocolError(f"unknown frame type 0x{t:02X}")
    return Frame(t, seq, f)


def encode_from_dict(d: dict[str, Any]) -> bytes:
    """Encode a frame from the dict form used in test_vectors.json."""
    t = NAME_TYPES[d["type"]]
    seq = d["seq"]
    if t == SET:
        return encode_set(seq, [tuple(x) for x in d["pairs"]])
    if t == TRIGGER:
        return encode_trigger(seq, d["action"], d.get("params", []))
    if t == STOP_ALL:
        return encode_stop_all(seq)
    if t == PING:
        return encode_ping(seq, d["t"])
    if t == PONG:
        return encode_pong(seq, d["t"])
    if t == ROUTINE_BEGIN:
        return encode_routine_begin(seq, d["slot"], d["length"])
    if t == ROUTINE_CHUNK:
        return encode_routine_chunk(seq, d["offset"], bytes.fromhex(d["data"]))
    if t == ROUTINE_END:
        return encode_routine_end(seq, d["crc"])
    if t == ROUTINE_RUN:
        return encode_routine_run(seq, d["slot"])
    if t == ROUTINE_STOP:
        return encode_routine_stop(seq)
    if t == ACK:
        return encode_ack(seq, d["ref_seq"], d["status"])
    if t == TELEMETRY:
        return encode_telemetry(seq, d["flags"], d["step"], d["values"])
    if t == LOG:
        return encode_log(seq, d["text"])
    if t == ROUTINE_STATE:
        return encode_routine_state(seq, d["state"], d["step"])
    raise ProtocolError(f"cannot encode {d['type']}")
