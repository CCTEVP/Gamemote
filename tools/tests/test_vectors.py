"""Run protocol/test_vectors.json against the Python reference implementation.

    python -m unittest discover -s tools/tests -t tools
"""

import binascii
import json
import pathlib
import unittest

from gamemote import protocol as P
from gamemote import routine as R

VECTORS = json.loads(
    (pathlib.Path(__file__).resolve().parents[2] / "protocol" / "test_vectors.json").read_text()
)


def unhex(s: str) -> bytes:
    return bytes.fromhex(s.replace(" ", ""))


class CrcTests(unittest.TestCase):
    def test_check_value(self):
        for v in VECTORS["crc"]:
            self.assertEqual(P.crc16_ccitt_false(v["data_ascii"].encode()), v["crc"])

    def test_matches_binascii(self):
        for r in VECTORS["routines"]:
            data = unhex(r["program_hex"])
            self.assertEqual(P.crc16_ccitt_false(data), binascii.crc_hqx(data, 0xFFFF))


class FrameTests(unittest.TestCase):
    def test_encode(self):
        for v in VECTORS["frames"]:
            with self.subTest(v["name"]):
                self.assertEqual(P.encode_from_dict(v["frame"]).hex(), v["hex"])

    def test_decode(self):
        for v in VECTORS["frames"]:
            with self.subTest(v["name"]):
                f = P.decode(unhex(v["hex"]))
                expected = dict(v["frame"])
                self.assertEqual(f.name, expected.pop("type"))
                self.assertEqual(f.seq, expected.pop("seq"))
                self.assertEqual(f.fields, expected)

    def test_invalid(self):
        for v in VECTORS["invalid_frames"]:
            with self.subTest(v["name"]):
                with self.assertRaises(P.ProtocolError):
                    P.decode(unhex(v["hex"]))

    def test_upload_frames(self):
        program = unhex(VECTORS["routines"][0]["program_hex"])
        frames = P.encode_routine_upload(10, 0, program)
        self.assertEqual(frames[0].hex(), "100a002300")
        rebuilt = b"".join(bytes.fromhex(P.decode(f).fields["data"]) for f in frames[1:-1])
        self.assertEqual(rebuilt, program)
        self.assertEqual(P.decode(frames[-1]).fields["crc"], VECTORS["routines"][0]["crc"])
        self.assertTrue(all(len(f) <= P.MAX_FRAME for f in frames))


class RoutineTests(unittest.TestCase):
    dev = VECTORS["test_device"]

    def test_compile(self):
        for r in VECTORS["routines"]:
            with self.subTest(r["name"]):
                c = R.compile_routine(r["ast"])
                self.assertEqual(c.program.hex(), r["program_hex"].replace(" ", ""))
                self.assertEqual(len(c.program), r["length"])
                self.assertEqual(P.crc16_ccitt_false(c.program), r["crc"])
                self.assertEqual(c.step_blocks, r["step_blocks"])

    def test_trace(self):
        for r in VECTORS["routines"]:
            with self.subTest(r["name"]):
                events = []
                now = [0]
                sink = R.Sink(
                    set=lambda ch, v: events.append([now[0], "set", ch, v]),
                    trigger=lambda a, p: events.append([now[0], "trigger", a, list(p)]),
                    stop_all=lambda: events.append([now[0], "stop_all"]),
                )
                instrs = R.parse_program(unhex(r["program_hex"]), set(self.dev["channel_ids"]),
                                         set(self.dev["action_ids"]), self.dev["max_loop_depth"])
                vm = R.VM(instrs, sink)
                vm.start(0)
                finished_at = None
                limit = r.get("trace_until_ms", 10000)
                while now[0] <= limit:
                    vm.tick(now[0])
                    if vm.finished:
                        finished_at = now[0]
                        break
                    now[0] += 10
                self.assertEqual(events, r["trace"])
                self.assertEqual(finished_at, r["finished_at_ms"])

    def test_invalid_programs(self):
        for v in VECTORS["invalid_programs"]:
            with self.subTest(v["name"]):
                with self.assertRaises(R.CompileError):
                    R.parse_program(unhex(v["hex"]), set(self.dev["channel_ids"]),
                                    set(self.dev["action_ids"]), self.dev["max_loop_depth"])


if __name__ == "__main__":
    unittest.main()
