import queue
import time
import unittest

from piano_host import FrameParser, PianoHost


def make_frame(sequence, touch):
    payload = bytes((sequence, touch, 0, 0, 0, 0, 3, 0))
    return bytes((0xAA, 0x55)) + payload + bytes((sum(payload) & 0xFF, 0x0D))


class HostLatencyTests(unittest.TestCase):
    def test_fragmented_press_and_release_frames(self):
        parser = FrameParser()
        stream = make_frame(1, 1) + make_frame(2, 0)
        self.assertEqual(parser.feed(stream[:5]), [])
        self.assertEqual([frame["touch"] for frame in parser.feed(stream[5:])], [1, 0])

    def test_quick_tap_remains_visible_for_one_redraw(self):
        host = object.__new__(PianoHost)
        host.inbox = queue.Queue()
        host.current = {"touch": 0}
        host.key_hold_until = [0.0] * 7
        host.visible_touch = 0
        host.last_frame_time = 0.0
        rendered = []
        host.render = lambda frame, touch: rendered.append(touch)
        host.after = lambda delay, callback: None
        host.inbox.put({"touch": 1})
        host.inbox.put({"touch": 0})
        host.process_inbox()
        self.assertEqual(rendered, [1])
        self.assertEqual(host.current["touch"], 0)
        host.key_hold_until[0] = time.monotonic() - 1
        host.process_inbox()
        self.assertEqual(rendered, [1, 0])


if __name__ == "__main__":
    unittest.main()
