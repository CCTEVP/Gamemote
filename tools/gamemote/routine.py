"""Routine compiler (block AST -> bytecode v0) and VM.

The same bytecode and VM semantics are used by:
  * the app (Live mode: the VM runs on the phone and emits SET/TRIGGER frames),
  * the device (Transferred mode: the VM runs on the microcontroller / simulator).
See protocol/PROTOCOL.md section 5.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

MAGIC = b"GM"
VERSION = 0
HEADER = MAGIC + bytes((VERSION,))

OP_HALT = 0x00
OP_SET = 0x01
OP_TRIGGER = 0x02
OP_WAIT = 0x03
OP_LOOP = 0x04
OP_END_LOOP = 0x05
OP_STOP_ALL = 0x06

MAX_INSTRUCTIONS_PER_TICK = 64


class CompileError(ValueError):
    pass


@dataclass
class Compiled:
    program: bytes
    step_blocks: list[Optional[str]]  # instruction index -> block id (for highlighting)


def compile_routine(ast: dict[str, Any]) -> Compiled:
    """Compile a routine AST ({"blocks": [...]}) into bytecode."""
    out = bytearray(HEADER)
    steps: list[Optional[str]] = []

    def emit(block: dict[str, Any]) -> None:
        op = block.get("op")
        bid = block.get("id")
        if op == "set":
            out.extend(struct.pack("<BBh", OP_SET, int(block["ch"]), int(block["value"])))
            steps.append(bid)
        elif op == "trigger":
            params = [int(p) for p in block.get("params", [])]
            out.extend(struct.pack("<BBB", OP_TRIGGER, int(block["action"]), len(params)))
            for p in params:
                out.extend(struct.pack("<h", p))
            steps.append(bid)
        elif op == "wait":
            ms = int(block["ms"])
            if ms < 0:
                raise CompileError("wait: negative ms")
            out.extend(struct.pack("<BI", OP_WAIT, ms))
            steps.append(bid)
        elif op in ("repeat", "forever"):
            count = 0 if op == "forever" else int(block["times"])
            if op == "repeat" and not 1 <= count <= 0xFFFF:
                raise CompileError("repeat: times must be 1..65535")
            out.extend(struct.pack("<BH", OP_LOOP, count))
            steps.append(bid)
            for child in block.get("body", []):
                emit(child)
            out.append(OP_END_LOOP)
            steps.append(bid)
        elif op == "stop_all":
            out.append(OP_STOP_ALL)
            steps.append(bid)
        else:
            raise CompileError(f"unknown block op {op!r}")

    for b in ast.get("blocks", []):
        emit(b)
    out.append(OP_HALT)
    steps.append(None)
    return Compiled(bytes(out), steps)


@dataclass
class Instruction:
    offset: int
    op: int
    args: tuple


def parse_program(
    program: bytes,
    channel_ids: Optional[set[int]] = None,
    action_ids: Optional[set[int]] = None,
    max_loop_depth: int = 4,
) -> list[Instruction]:
    """Validate and decode a program. Raises CompileError when invalid."""
    if not program.startswith(HEADER):
        raise CompileError("bad magic/version")
    i = len(HEADER)
    instrs: list[Instruction] = []
    depth = 0
    halted = False
    while i < len(program):
        op = program[i]
        start = i

        def need(n: int) -> None:
            if start + n > len(program):
                raise CompileError(f"truncated instruction at {start}")

        if op == OP_HALT:
            instrs.append(Instruction(start, op, ()))
            i += 1
            halted = True
            break
        if op == OP_SET:
            need(4)
            ch, value = struct.unpack_from("<Bh", program, i + 1)
            if channel_ids is not None and ch not in channel_ids:
                raise CompileError(f"unknown channel {ch}")
            instrs.append(Instruction(start, op, (ch, value)))
            i += 4
        elif op == OP_TRIGGER:
            need(3)
            action, n = program[i + 1], program[i + 2]
            need(3 + 2 * n)
            params = list(struct.unpack_from(f"<{n}h", program, i + 3)) if n else []
            if action_ids is not None and action not in action_ids:
                raise CompileError(f"unknown action {action}")
            instrs.append(Instruction(start, op, (action, params)))
            i += 3 + 2 * n
        elif op == OP_WAIT:
            need(5)
            (ms,) = struct.unpack_from("<I", program, i + 1)
            instrs.append(Instruction(start, op, (ms,)))
            i += 5
        elif op == OP_LOOP:
            need(3)
            (count,) = struct.unpack_from("<H", program, i + 1)
            depth += 1
            if depth > max_loop_depth:
                raise CompileError("loop nesting too deep")
            instrs.append(Instruction(start, op, (count,)))
            i += 3
        elif op == OP_END_LOOP:
            depth -= 1
            if depth < 0:
                raise CompileError("END_LOOP without LOOP")
            instrs.append(Instruction(start, op, ()))
            i += 1
        elif op == OP_STOP_ALL:
            instrs.append(Instruction(start, op, ()))
            i += 1
        else:
            raise CompileError(f"unknown opcode 0x{op:02X} at {start}")
    if not halted or i != len(program):
        raise CompileError("program must end with a single HALT")
    if depth != 0:
        raise CompileError("unbalanced LOOP/END_LOOP")
    return instrs


@dataclass
class Sink:
    """What the VM drives. Device: actuators. App (Live mode): protocol frames."""
    set: Callable[[int, int], None]
    trigger: Callable[[int, list], None]
    stop_all: Callable[[], None]
    step: Callable[[int], None] = lambda step: None


@dataclass
class _Loop:
    body_start: int   # instruction index right after LOOP
    remaining: int    # -1 = forever


@dataclass
class VM:
    instrs: list[Instruction]
    sink: Sink
    pc: int = 0
    clock_ms: float = 0.0          # virtual time; WAIT advances it (no drift)
    running: bool = False
    finished: bool = False
    loops: list[_Loop] = field(default_factory=list)

    def start(self, now_ms: float) -> None:
        self.pc = 0
        self.loops.clear()
        self.clock_ms = now_ms
        self.running = True
        self.finished = False

    def stop(self) -> None:
        self.running = False

    @property
    def step(self) -> int:
        return self.pc

    def tick(self, now_ms: float) -> None:
        """Execute every instruction that is due at `now_ms`."""
        executed = 0
        while self.running and executed < MAX_INSTRUCTIONS_PER_TICK:
            if now_ms < self.clock_ms:
                return  # still waiting
            ins = self.instrs[self.pc]
            self.sink.step(self.pc)
            executed += 1
            if ins.op == OP_HALT:
                self.running = False
                self.finished = True
                return
            if ins.op == OP_SET:
                self.sink.set(*ins.args)
                self.pc += 1
            elif ins.op == OP_TRIGGER:
                self.sink.trigger(*ins.args)
                self.pc += 1
            elif ins.op == OP_WAIT:
                self.clock_ms += ins.args[0]
                self.pc += 1
            elif ins.op == OP_LOOP:
                count = ins.args[0]
                self.loops.append(_Loop(self.pc + 1, -1 if count == 0 else count))
                self.pc += 1
            elif ins.op == OP_END_LOOP:
                loop = self.loops[-1]
                if loop.remaining > 0:
                    loop.remaining -= 1
                if loop.remaining != 0:
                    self.pc = loop.body_start
                else:
                    self.loops.pop()
                    self.pc += 1
            elif ins.op == OP_STOP_ALL:
                self.sink.stop_all()
                self.pc += 1
