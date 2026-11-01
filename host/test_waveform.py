import queue
import time
import unittest
from unittest.mock import Mock
from instrument_host import InstrumentHost
from three_board_protocol import FrameParser

def wave_packet(values=None):
    values = values or list(range(-64, 64))
    body = bytes((7, 1, 1, 4, 0, 4, 4, 0)) + bytes(v & 255 for v in values)
    return b"\xaa\x5a" + body + bytes((sum(body) & 255, 13))

class WaveformTests(unittest.TestCase):
    def test_fragmented_real_samples_and_corruption(self):
        wire = wave_packet()
        parser = FrameParser()
        self.assertEqual(parser.feed(wire[:30]), [])
        frame, = parser.feed(wire[30:])
        self.assertEqual(frame['samples'], list(range(-64, 64)))
        self.assertEqual(frame['peak'], 1024)
        self.assertEqual(frame['sample_rate'], 13183.59375)
        damaged = bytearray(wire)
        damaged[55] ^= 1
        frames = parser.feed(damaged + wire)
        self.assertEqual(len(frames), 1)

    def test_wave_frame_does_not_replace_control_state_or_ack(self):
        host = object.__new__(InstrumentHost)
        host.inbox = queue.Queue()
        host.inbox.put(FrameParser().feed(wave_packet())[0])
        host.current = dict(touch=0, extended=True, command_sequence=9)
        host.visible_touch = 0
        host.key_hold_until = [0.0]*7
        host.pending_command = (10, time.monotonic())
        host.last_frame_time = 123
        host.panel = Mock()
        host.after = Mock()
        host.process_inbox()
        host.panel.update_waveform.assert_called_once()
        host.panel.update_state.assert_not_called()
        self.assertEqual(host.current['command_sequence'], 9)
        self.assertEqual(host.pending_command[0], 10)
        self.assertEqual(host.last_frame_time, 123)

if __name__ == '__main__':
    unittest.main()
