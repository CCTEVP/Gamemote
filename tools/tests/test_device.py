"""Behavioural tests for the reference device logic (failsafe, upload, run modes)."""

import unittest

from gamemote import protocol as P
from gamemote import routine as R
from gamemote.device import SimDevice

WAVE = {"blocks": [
    {"id": "b1", "op": "set", "ch": 2, "value": 0},
    {"id": "b2", "op": "repeat", "times": 2, "body": [
        {"id": "b3", "op": "set", "ch": 2, "value": 180},
        {"id": "b4", "op": "wait", "ms": 500},
    ]},
]}


def frames(out):
    return [P.decode(f) for f in out]


class DeviceTests(unittest.TestCase):
    def setUp(self):
        self.d = SimDevice(log=lambda s: None)
        self.d.on_connect(0)

    def upload(self, program, now=0):
        acks = []
        for f in P.encode_routine_upload(1, 0, program):
            acks += frames(self.d.handle_cmd(f, now))
        return acks

    def test_info_fits(self):
        self.assertLessEqual(len(self.d.info_bytes), 512)

    def test_set_clamps_and_failsafe(self):
        self.d.handle_cmd(P.encode_set(0, [(2, 999)]), 0)
        self.assertEqual(self.d.values[2], 180)
        self.d.tick(400)
        self.assertEqual(self.d.values[2], 180)
        self.d.tick(501)
        self.assertEqual(self.d.values[2], 90)  # neutral
        self.assertTrue(self.d.failsafe_tripped)

    def test_ping_keeps_alive(self):
        self.d.handle_cmd(P.encode_set(0, [(1, 200)]), 0)
        for t in range(250, 2000, 250):
            self.d.handle_cmd(P.encode_ping(1, t), t)
            self.d.tick(t)
        self.assertEqual(self.d.values[1], 200)

    def test_disconnect_goes_neutral(self):
        self.d.handle_cmd(P.encode_set(0, [(3, 50)]), 0)
        self.d.on_disconnect(10)
        self.assertEqual(self.d.values[3], 0)

    def test_trigger_ack(self):
        out = frames(self.d.handle_cmd(P.encode_trigger(7, 1, [100]), 0))
        self.assertEqual((out[0].name, out[0].fields), ("ACK", {"ref_seq": 7, "status": P.OK}))
        out = frames(self.d.handle_cmd(P.encode_trigger(8, 9), 0))
        self.assertEqual(out[0].fields["status"], P.BAD_ID)

    def test_upload_run_finish(self):
        prog = R.compile_routine(WAVE).program
        acks = self.upload(prog)
        self.assertEqual([a.fields["status"] for a in acks], [P.OK, P.OK])
        out = frames(self.d.handle_cmd(P.encode_routine_run(9, 0), 0))
        self.assertEqual([f.name for f in out], ["ACK", "ROUTINE_STATE"])
        self.d.tick(0)
        self.assertEqual(self.d.values[2], 180)
        # Disconnect: transferred routine keeps running, no failsafe.
        self.d.on_disconnect(100)
        self.d.tick(700)
        self.assertTrue(self.d.routine_running)
        self.assertEqual(self.d.values[2], 180)
        self.d.tick(1000)
        self.assertFalse(self.d.routine_running)
        self.assertEqual(self.d.values[2], 90)  # neutral at end

    def test_set_ignored_while_running(self):
        self.upload(R.compile_routine(WAVE).program)
        self.d.handle_cmd(P.encode_routine_run(9, 0), 0)
        self.d.tick(0)
        out = frames(self.d.handle_cmd(P.encode_set(1, [(2, 10)]), 10))
        self.assertEqual(out[0].name, "LOG")
        self.assertEqual(self.d.values[2], 180)

    def test_stop_all_stops_routine(self):
        self.upload(R.compile_routine(WAVE).program)
        self.d.handle_cmd(P.encode_routine_run(9, 0), 0)
        self.d.tick(0)
        out = frames(self.d.handle_cmd(P.encode_stop_all(10), 50))
        self.assertEqual(out[0].name, "ACK")
        self.assertIn(("ROUTINE_STATE", P.RS_STOPPED), [(f.name, f.fields.get("state")) for f in out])
        self.assertFalse(self.d.routine_running)
        self.assertEqual(self.d.values[2], 90)

    def test_bad_crc_rejected(self):
        prog = R.compile_routine(WAVE).program
        fs = P.encode_routine_upload(1, 0, prog)
        fs[-1] = P.encode_routine_end(99, 0x0000)
        statuses = [P.decode(o).fields["status"] for f in fs for o in self.d.handle_cmd(f, 0)]
        self.assertEqual(statuses, [P.OK, P.BAD_PROGRAM])

    def test_too_large(self):
        out = frames(self.d.handle_cmd(P.encode_routine_begin(1, 0, 4096), 0))
        self.assertEqual(out[0].fields["status"], P.TOO_LARGE)

    def test_telemetry_rate(self):
        n = sum(len(self.d.tick(t)) for t in range(0, 1000, 20))
        self.assertEqual(n, 5)

    def test_unknown_type(self):
        out = frames(self.d.handle_cmd(bytes([0x7E, 4]), 0))
        self.assertEqual(out[0].fields, {"ref_seq": 4, "status": P.UNKNOWN_TYPE})


if __name__ == "__main__":
    unittest.main()
