import unittest
from three_board_protocol import FrameParser, command_packet


class ProtocolTests(unittest.TestCase):
    def make_frame(self):
        frame = bytearray(38)
        frame[:4] = bytes((0xAA, 0x56, 4, 1))
        frame[4] = 5
        frame[22:24] = (26400).to_bytes(2, 'little')
        frame[-2] = sum(frame[2:-2]) & 255
        frame[-1] = 13
        return frame

    def test_chunked(self):
        parser = FrameParser()
        frame = self.make_frame()
        result = []
        for byte in frame:
            result.extend(parser.feed(bytes((byte,))))
        self.assertEqual(result[0]['touch'], 5)
        self.assertEqual(result[0]['pressure'][0], 26400)

    def test_resync(self):
        parser = FrameParser()
        bad = self.make_frame()
        bad[8] ^= 1
        self.assertEqual(len(parser.feed(b'noise' + bad + self.make_frame())), 1)

    def test_command(self):
        packet = command_packet(1, 0x30, 0x1234)
        self.assertEqual(packet[:2], b'CM')
        self.assertEqual(packet[-2], sum(packet[2:6]) & 255)

    def test_storage_fault_nibble_does_not_corrupt_base_state(self):
        frame = self.make_frame()
        frame[15] = 0x26
        frame[16] = 8
        frame[-2] = sum(frame[2:-2]) & 255
        decoded = FrameParser().feed(frame)[0]
        self.assertEqual(decoded['store_status'], 6)
        self.assertEqual(decoded['store_fault_code'], 2)

    def test_fifth_sound_is_not_truncated(self):
        frame = self.make_frame()
        frame[5] = 4
        frame[-2] = sum(frame[2:-2]) & 255
        self.assertEqual(FrameParser().feed(frame)[0]['timbre'], 4)

    def test_audio_counters_and_legacy_resync(self):
        frame=bytearray(74)
        frame[:4]=bytes((0xAA,0x57,7,1))
        frame[4]=0x41;frame[14]=3
        values=(123456,2,300,0,200,1,98,1,2)
        for i,value in enumerate(values):
            frame[36+i*4:40+i*4]=value.to_bytes(4,'little')
        frame[-2]=sum(frame[2:-2])&255;frame[-1]=13
        parser=FrameParser();decoded=[]
        for byte in b'noise'+frame+self.make_frame():
            decoded.extend(parser.feed(bytes((byte,))))
        self.assertEqual(len(decoded),2)
        self.assertEqual(decoded[0]['audio_frames'],123456)
        self.assertEqual(decoded[0]['audio_bad_c'],300)
        self.assertEqual(decoded[0]['audio_crc_c'],200)
        self.assertEqual(decoded[0]['audio_sequence_c'],98)
        self.assertEqual(decoded[0]['audio_version_c'],2)
        self.assertEqual(decoded[0]['touch'],0x41)
        self.assertEqual(decoded[1]['pressure'][0],26400)

    def test_v6_diagnostic_chunked_and_checksum(self):
        frame = bytearray(88)
        frame[:4] = bytes((0xAA, 0x58, 1, 1))
        frame[14] = 3
        frame[72:86] = bytes((25, 0xE4, 2, 25, 0, 0x83, 0xEE, 0,
                              0x58, 3, 4, 50, 0x1E, 0))
        frame[-2] = sum(frame[2:-2]) & 255
        frame[-1] = 13
        parser = FrameParser()
        damaged = frame.copy()
        damaged[80] ^= 1
        self.assertEqual(parser.feed(damaged), [])
        decoded = []
        for b in frame:
            decoded.extend(parser.feed(bytes((b,))))
        d = decoded[0]['aux_diagnostic']
        self.assertEqual(d['pc'], 25)
        self.assertEqual(d['state'], 2)
        self.assertTrue(d['valid'])
        self.assertEqual(d['fail_pc'], 25)
        self.assertEqual(d['model_id'], 0xEE)
        self.assertEqual(d['fail_reg'], 0x83)
        self.assertEqual(d['attempts'], 3)
        self.assertEqual(decoded[0]['links'], 3)

    def test_v7_probe_addresses_preserve_audio_and_aux(self):
        frame = bytearray(108)
        frame[:4] = bytes((0xAA, 0x59, 1, 1))
        frame[86:90] = bytes((255, 127, 2, 2))
        bits = (1 << 0x29) | (1 << 0x73)
        frame[90:106] = bits.to_bytes(16, 'little')
        frame[-2] = sum(frame[2:-2]) & 255
        frame[-1] = 13
        parser = FrameParser()
        out = []
        for byte in frame:
            out.extend(parser.feed(bytes((byte,))))
        self.assertEqual(out[0]['aux_probe']['addresses'], [0x29, 0x73])
        self.assertEqual(out[0]['aux_probe']['flags'], 127)
        self.assertIn('audio_frames', out[0])
        self.assertIn('aux_diagnostic', out[0])

    def test_v10_encoder_status_uses_telemetry_slot(self):
        frame = bytearray(108)
        frame[:4] = bytes((0xAA, 0x59, 1, 1))
        frame[18:20] = (0xC123).to_bytes(2, 'little')
        frame[-2] = sum(frame[2:-2]) & 255
        frame[-1] = 13
        decoded = FrameParser().feed(frame)[0]
        self.assertTrue(decoded['encoder_active'])
        self.assertTrue(decoded['encoder_direction'])
        self.assertEqual(decoded['encoder_depth'], 0x0123)

    def test_encoder_audit_reserved_bits_keep_sensor_status(self):
        frame = bytearray(108)
        frame[:4] = bytes((0xAA, 0x59, 1, 1))
        frame[10] = 0x6f
        frame[12] = 0xbf
        frame[13] = 0xb6
        frame[-2] = sum(frame[2:-2]) & 255
        frame[-1] = 13
        decoded = FrameParser().feed(frame)[0]
        self.assertEqual(decoded['ads_online'], 7)
        self.assertEqual(decoded['aux_online'], 2)
        d = decoded['encoder_diagnostic']
        self.assertTrue(d['raw_a'])
        self.assertFalse(d['raw_b'])
        self.assertTrue(d['seen_b'])
        self.assertFalse(d['seen_a'])
        self.assertEqual(d['count'], 45)
        self.assertTrue(d['legal_seen'])
        self.assertFalse(d['illegal_seen'])


if __name__ == '__main__':
    unittest.main()
