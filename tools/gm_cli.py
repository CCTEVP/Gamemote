#!/usr/bin/env python3
"""Gamemote reference client (BLE central) for testing devices without the app.

    gm_cli.py scan
    gm_cli.py info
    gm_cli.py ping -n 50
    gm_cli.py set 2 180 1 255 --hold 3
    gm_cli.py trigger 1 300
    gm_cli.py stop
    gm_cli.py run routine.json            # Live mode: this computer runs the VM
    gm_cli.py run routine.json --transfer # Transferred mode: upload and run on the device
    gm_cli.py monitor

Use --device NAME_OR_ADDRESS to pick a device; by default the first one advertising
the Gamemote service is used. Works on macOS, Linux and Windows (bleak).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import pathlib
import statistics
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from gamemote import protocol as P  # noqa: E402
from gamemote import routine as R  # noqa: E402

try:
    from bleak import BleakClient, BleakScanner  # noqa: E402
except ImportError:  # pragma: no cover
    sys.exit("bleak is not installed: pip install -r tools/requirements.txt")


def ms() -> int:
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


class Session:
    def __init__(self, client: BleakClient, verbose: bool) -> None:
        self.client = client
        self.verbose = verbose
        self.seq = 0
        self.events: asyncio.Queue[P.Frame] = asyncio.Queue()
        self.info: dict = {}

    def next_seq(self) -> int:
        s = self.seq
        self.seq = (self.seq + 1) & 0xFF
        return s

    async def start(self) -> None:
        await self.client.start_notify(P.EVT_UUID, self._on_evt)
        self.info = json.loads(bytes(await self.client.read_gatt_char(P.INFO_UUID)))

    def _on_evt(self, _sender, data: bytearray) -> None:
        try:
            f = P.decode(bytes(data))
        except P.ProtocolError as e:
            print(f"bad EVT {bytes(data).hex()}: {e}")
            return
        if self.verbose or f.type in (P.LOG, P.ROUTINE_STATE):
            print(f"  <- {f.name} {f.fields}")
        self.events.put_nowait(f)

    async def send(self, frame: bytes, response: bool) -> None:
        if self.verbose:
            print(f"  -> {P.decode(frame).name} {frame.hex()}")
        await self.client.write_gatt_char(P.CMD_UUID, frame, response=response)

    async def wait_for(self, type_: int, timeout: float = 2.0, ref_seq: int | None = None) -> P.Frame:
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError(f"no {P.TYPE_NAMES[type_]} within {timeout}s")
            f = await asyncio.wait_for(self.events.get(), left)
            if f.type == type_ and (ref_seq is None or f.fields.get("ref_seq") == ref_seq):
                return f

    async def request(self, frame: bytes) -> int:
        """Send a frame that expects an ACK; return the ACK status."""
        await self.send(frame, response=True)
        ack = await self.wait_for(P.ACK, ref_seq=frame[1])
        status = ack.fields["status"]
        if status != P.OK:
            print(f"  ACK status {P.STATUS_NAMES.get(status, status)}")
        return status


async def find_device(name_or_addr: str | None, timeout: float = 8.0):
    if name_or_addr:
        dev = await BleakScanner.find_device_by_filter(
            lambda d, adv: name_or_addr.lower() in ((d.name or "").lower(), d.address.lower()),
            timeout=timeout)
    else:
        dev = await BleakScanner.find_device_by_filter(
            lambda d, adv: P.SERVICE_UUID in [u.lower() for u in adv.service_uuids], timeout=timeout)
    if dev is None:
        sys.exit("no Gamemote device found (is the simulator or board advertising?)")
    return dev


async def cmd_scan(args) -> None:
    found = await BleakScanner.discover(timeout=args.timeout, return_adv=True)
    rows = [(adv.rssi, d.name or "?", d.address) for d, adv in found.values()
            if P.SERVICE_UUID in [u.lower() for u in adv.service_uuids]]
    if not rows:
        print("no Gamemote devices found")
    for rssi, name, addr in sorted(rows, reverse=True):
        print(f"{rssi:4d} dBm  {name:16s} {addr}")


async def with_session(args, fn) -> None:
    dev = await find_device(args.device)
    print(f"connecting to {dev.name} ({dev.address})...")
    async with BleakClient(dev) as client:
        s = Session(client, args.verbose)
        await s.start()
        print(f"connected: {s.info.get('name')} fw={s.info.get('fw')} proto={s.info.get('proto')}")
        await fn(s)


async def keepalive(s: Session, seconds: float, frame_fn=None) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        await s.send(frame_fn() if frame_fn else P.encode_ping(s.next_seq(), ms()), response=False)
        await asyncio.sleep(0.1)


async def cmd_info(s: Session, args) -> None:
    print(json.dumps(s.info, indent=2))


async def cmd_ping(s: Session, args) -> None:
    rtts = []
    for _ in range(args.count):
        t = ms()
        await s.send(P.encode_ping(s.next_seq(), t), response=False)
        try:
            while True:
                pong = await s.wait_for(P.PONG, timeout=1.0)
                if pong.fields["t"] == t:
                    break
            rtts.append(ms() - t)
        except TimeoutError:
            print("  timeout")
        await asyncio.sleep(0.05)
    if rtts:
        rtts.sort()
        p95 = rtts[min(len(rtts) - 1, int(len(rtts) * 0.95))]
        print(f"RTT ms: n={len(rtts)} min={rtts[0]} p50={statistics.median(rtts):.0f} "
              f"p95={p95} max={rtts[-1]}")


async def cmd_set(s: Session, args) -> None:
    vals = [int(v) for v in args.pairs]
    if len(vals) % 2:
        sys.exit("set takes CH VALUE pairs")
    pairs = list(zip(vals[::2], vals[1::2]))
    print(f"holding {pairs} for {args.hold}s (device fails safe when we stop)")
    await keepalive(s, args.hold, lambda: P.encode_set(s.next_seq(), pairs))


async def cmd_trigger(s: Session, args) -> None:
    await s.request(P.encode_trigger(s.next_seq(), args.action, [int(p) for p in args.params]))


async def cmd_stop(s: Session, args) -> None:
    await s.request(P.encode_stop_all(s.next_seq()))


async def cmd_monitor(s: Session, args) -> None:
    s.verbose = True
    print("monitoring (Ctrl+C to quit)")
    await keepalive(s, 10 ** 9)


async def cmd_run(s: Session, args) -> None:
    ast = json.loads(pathlib.Path(args.file).read_text())
    compiled = R.compile_routine(ast)
    print(f"compiled {len(compiled.program)} bytes")
    if args.transfer:
        if not (s.info.get("routines") or {}).get("transfer"):
            sys.exit("device does not support routine transfer")
        first = s.next_seq()
        frames = P.encode_routine_upload(first, 0, compiled.program)
        s.seq = (first + len(frames)) & 0xFF
        for frame in frames:
            if frame[0] == P.ROUTINE_CHUNK:
                await s.send(frame, response=True)
            elif await s.request(frame) != P.OK:
                sys.exit("upload failed")
        if await s.request(P.encode_routine_run(s.next_seq(), 0)) != P.OK:
            sys.exit("run failed")
        print("running on the device; waiting for it to finish (Ctrl+C leaves it running)")
        while True:
            f = await s.wait_for(P.ROUTINE_STATE, timeout=3600)
            if f.fields["state"] != P.RS_RUNNING:
                break
        return

    # Live mode: run the VM here and stream frames.
    pending: dict[int, int] = {}
    triggers: list[tuple[int, list]] = []
    sink = R.Sink(set=lambda ch, v: pending.__setitem__(ch, v),
                  trigger=lambda a, p: triggers.append((a, p)),
                  stop_all=lambda: triggers.append((-1, [])))
    vm = R.VM(R.parse_program(compiled.program), sink)
    t0 = time.monotonic()
    vm.start(0)
    last_send = 0.0
    try:
        while vm.running:
            now = (time.monotonic() - t0) * 1000
            vm.tick(now)
            for a, p in triggers:
                await s.request(P.encode_stop_all(s.next_seq()) if a < 0 else
                                P.encode_trigger(s.next_seq(), a, p))
            triggers.clear()
            if pending:
                items = list(pending.items())
                pending.clear()
                for i in range(0, len(items), P.MAX_SET_PAIRS):
                    await s.send(P.encode_set(s.next_seq(), items[i:i + P.MAX_SET_PAIRS]), response=False)
                last_send = now
            elif now - last_send > 250:
                await s.send(P.encode_ping(s.next_seq(), ms()), response=False)
                last_send = now
            await asyncio.sleep(0.01)
    finally:
        await s.request(P.encode_stop_all(s.next_seq()))
    print("routine finished")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", help="name or address (default: first Gamemote device)")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("scan")
    p.add_argument("--timeout", type=float, default=5.0)
    sub.add_parser("info")
    p = sub.add_parser("ping")
    p.add_argument("-n", "--count", type=int, default=20)
    p = sub.add_parser("set")
    p.add_argument("pairs", nargs="+", help="CH VALUE [CH VALUE ...]")
    p.add_argument("--hold", type=float, default=2.0)
    p = sub.add_parser("trigger")
    p.add_argument("action", type=int)
    p.add_argument("params", nargs="*")
    sub.add_parser("stop")
    sub.add_parser("monitor")
    p = sub.add_parser("run")
    p.add_argument("file")
    p.add_argument("--transfer", action="store_true")
    args = ap.parse_args()

    handlers = {"info": cmd_info, "ping": cmd_ping, "set": cmd_set, "trigger": cmd_trigger,
                "stop": cmd_stop, "monitor": cmd_monitor, "run": cmd_run}
    try:
        if args.cmd == "scan":
            asyncio.run(cmd_scan(args))
        else:
            asyncio.run(with_session(args, lambda s: handlers[args.cmd](s, args)))
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
