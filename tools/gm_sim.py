#!/usr/bin/env python3
"""Gamemote device simulator: a real BLE peripheral that speaks protocol v0.

Run it on your Mac, then connect to it from the Gamemote app on an iPhone or iPad.
It stands in for the microcontroller until you have hardware.

    python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
    .venv/bin/python tools/gm_sim.py                 # transfer mode supported
    .venv/bin/python tools/gm_sim.py --no-transfer   # behave like a Live-only board

macOS asks for Bluetooth permission for your terminal app the first time.
Note: a Mac cannot connect to its own simulator; use the iPhone/iPad (or another
computer running tools/gm_cli.py) as the central.
"""

from __future__ import annotations

import argparse
import asyncio
import collections
import copy
import logging
import pathlib
import sys
import time
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from gamemote import protocol as P  # noqa: E402
from gamemote.device import DEFAULT_DESCRIPTOR, SimDevice  # noqa: E402

try:
    from bless import BlessServer  # noqa: E402
    from bless import GATTAttributePermissions as Perms  # noqa: E402
    from bless import GATTCharacteristicProperties as Props  # noqa: E402
except ImportError:  # pragma: no cover
    sys.exit("bless is not installed: pip install -r tools/requirements.txt")

T0 = time.monotonic()


def now_ms() -> float:
    return (time.monotonic() - T0) * 1000.0


def log(msg: str) -> None:
    print(f"{now_ms() / 1000:8.2f}s  {msg}", flush=True)


async def run(args: argparse.Namespace) -> None:
    loop = asyncio.get_running_loop()
    inbox: asyncio.Queue[bytes] = asyncio.Queue()
    outbox: collections.deque[bytes] = collections.deque(maxlen=64)

    desc = copy.deepcopy(DEFAULT_DESCRIPTOR)
    desc["name"] = args.name
    if args.no_transfer:
        desc.pop("routines", None)
    dev = SimDevice(desc, log=log)

    if len(args.name) > 10:
        log("warning: names longer than 10 characters push the service UUID out of the "
            "advertisement on macOS, so the app will not find the simulator")

    server = BlessServer(name=args.name, loop=loop)
    # INFO is a static value, so CoreBluetooth answers reads itself; this is a fallback.
    server.read_request_func = lambda characteristic, **_: characteristic.value

    def on_write(characteristic, value) -> None:
        # Called from the CoreBluetooth queue: hand the frame over to the asyncio loop.
        if characteristic is not None and str(uuid.UUID(str(characteristic.uuid))) == P.CMD_UUID:
            loop.call_soon_threadsafe(inbox.put_nowait, bytes(value))

    server.write_request_func = on_write

    await server.add_new_service(P.SERVICE_UUID)
    await server.add_new_characteristic(
        P.SERVICE_UUID, P.CMD_UUID, Props.write | Props.write_without_response, None, Perms.writeable)
    await server.add_new_characteristic(P.SERVICE_UUID, P.EVT_UUID, Props.notify, None, Perms.readable)
    await server.add_new_characteristic(
        P.SERVICE_UUID, P.INFO_UUID, Props.read, bytearray(dev.info_bytes), Perms.readable)
    await server.start()
    log(f"advertising as '{args.name}' (service {P.SERVICE_UUID})")
    log(f"routine transfer: {'supported' if dev.transfer_supported else 'not supported'}")

    evt = server.get_characteristic(P.EVT_UUID)
    last_status = ""
    last_status_ms = 0.0

    def notify(frames: list[bytes]) -> None:
        outbox.extend(frames)
        while outbox:
            evt.value = bytearray(outbox[0])
            if server.update_value(P.SERVICE_UUID, P.EVT_UUID) is False:
                return  # transmit queue full; retry on the next loop iteration
            frame = outbox.popleft()
            if args.verbose:
                log(f"  -> {P.decode(frame).name} {frame.hex()}")

    try:
        while True:
            t = now_ms()
            connected = await server.is_connected()
            if connected and not dev.connected:
                dev.on_connect(t)
            elif not connected and dev.connected:
                dev.on_disconnect(t)
                outbox.clear()

            while not inbox.empty():
                data = inbox.get_nowait()
                if args.verbose:
                    try:
                        log(f"<-  {P.decode(data).name} {data.hex()}")
                    except P.ProtocolError:
                        log(f"<-  ?? {data.hex()}")
                notify(dev.handle_cmd(data, t))
            notify(dev.tick(t))

            status = "  ".join(f"{c['name']}={dev.values[c['id']]}" for c in desc["channels"])
            if dev.routine_running:
                status += f"   routine step {dev.step}"
            if status != last_status and t - last_status_ms >= 100:
                log(status)
                last_status, last_status_ms = status, t
            await asyncio.sleep(0.01)
    finally:
        await server.stop()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default="GM-Sim", help="advertised name, max 10 chars (default GM-Sim)")
    ap.add_argument("--no-transfer", action="store_true", help="do not support routine transfer")
    ap.add_argument("-v", "--verbose", action="store_true", help="print every frame")
    args = ap.parse_args()
    logging.basicConfig(level=logging.WARNING)
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
