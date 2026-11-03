"""Drive gm_cli's Session/run logic against SimDevice through a fake BLE client."""

import argparse
import asyncio
import importlib.util
import pathlib
import time
import unittest

from gamemote import protocol as P
from gamemote.device import SimDevice

ROOT = pathlib.Path(__file__).resolve().parents[1]
try:
    spec = importlib.util.spec_from_file_location("gm_cli", ROOT / "gm_cli.py")
    gm_cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm_cli)
except SystemExit:  # bleak not installed
    gm_cli = None


class FakeClient:
    """Routes CMD writes into SimDevice and its EVT frames back to the notify callback."""

    def __init__(self, dev: SimDevice):
        self.dev = dev
        self.cb = None
        self.t0 = time.monotonic()
        self.ticker = None

    def now(self):
        return (time.monotonic() - self.t0) * 1000

    async def start_notify(self, uuid, cb):
        self.cb = cb
        self.dev.on_connect(self.now())
        self.ticker = asyncio.create_task(self._tick())

    async def _tick(self):
        while True:
            for f in self.dev.tick(self.now()):
                self.cb(None, bytearray(f))
            await asyncio.sleep(0.01)

    async def read_gatt_char(self, uuid):
        return bytearray(self.dev.info_bytes)

    async def write_gatt_char(self, uuid, data, response=None):
        for f in self.dev.handle_cmd(bytes(data), self.now()):
            self.cb(None, bytearray(f))


@unittest.skipIf(gm_cli is None, "bleak not installed")
class CliLoopbackTests(unittest.TestCase):
    def run_routine(self, transfer: bool):
        dev = SimDevice(log=lambda s: None)
        seen = []
        orig = dev._apply
        dev._apply = lambda ch, v: (seen.append((ch, v)), orig(ch, v))

        async def go():
            client = FakeClient(dev)
            s = gm_cli.Session(client, verbose=False)
            await s.start()
            args = argparse.Namespace(file=str(ROOT / "routines" / "wave.json"), transfer=transfer)
            await gm_cli.cmd_run(s, args)
            client.ticker.cancel()

        asyncio.run(asyncio.wait_for(go(), 10))
        return dev, seen

    def test_live(self):
        dev, seen = self.run_routine(transfer=False)
        self.assertIn((2, 180), seen)
        self.assertEqual(dev.values[2], 90)  # STOP_ALL at the end

    def test_transfer(self):
        dev, seen = self.run_routine(transfer=True)
        self.assertEqual(seen.count((2, 180)), 3)
        self.assertFalse(dev.routine_running)


if __name__ == "__main__":
    unittest.main()
