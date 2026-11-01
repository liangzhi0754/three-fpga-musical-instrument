"""Byte protocol only. No synthesizer or PCM playback runs on the PC."""


def command_packet(sequence, opcode, argument=0):
    body = bytes((sequence & 255, opcode & 255, argument & 255,
                  (argument >> 8) & 255))
    return b"CM" + body + bytes((sum(body) & 255, 13))


class FrameParser:
    def __init__(self):
        self.buf = bytearray()

    def feed(self, data):
        self.buf.extend(data)
        frames = []
        while self.buf:
            if self.buf[0] != 0xAA:
                del self.buf[0]
                continue
            if len(self.buf) < 2:
                break
            size = {0x55: 12, 0x56: 38, 0x57: 74, 0x58: 88, 0x59: 108, 0x5A: 140}.get(self.buf[1])
            if size is None:
                del self.buf[0]
                continue
            if len(self.buf) < size:
                break
            frame = self.buf[:size]
            if frame[-1] != 13 or frame[-2] != sum(frame[2:-2]) & 255:
                del self.buf[0]
                continue
            del self.buf[:size]
            if size == 140:
                if frame[3] == 1 and frame[5] == 4 and frame[8] <= 9:
                    frames.append(dict(kind="waveform", sequence=frame[2],
                        online=bool(frame[4] & 1), decimation=frame[5],
                        peak=int.from_bytes(frame[6:8], "little"), shift=frame[8],
                        sample_rate=52734.375 / frame[5],
                        samples=[v if v < 128 else v-256 for v in frame[10:138]]))
            elif size == 12:
                frames.append(dict(touch=frame[3] & 127,
                    pitch=int.from_bytes(frame[4:6], 'little'),
                    volume=int.from_bytes(frame[6:8], 'little'),
                    mpr=bool(frame[8] & 1), ads=bool(frame[8] & 2),
                    adc_valid=bool(frame[8] & 4), volume_valid=bool(frame[8] & 8),
                    timbre=frame[9] & 3, extended=False))
            elif frame[3] == 1:
                decoded=dict(touch=frame[4] & 127, timbre=frame[5] & 7,
                    pitch=int.from_bytes(frame[6:8], 'little'),
                    volume=int.from_bytes(frame[8:10], 'little'),
                    mpr=bool(frame[10] & 1), ads=bool(frame[10] & 2),
                    adc_valid=bool(frame[10] & 4), volume_valid=bool(frame[10] & 8),
                    features=frame[11] & 7, ads_online=frame[12] & 7,
                    aux_online=frame[13] & 3, links=frame[14], store_status=frame[15] & 15, store_fault_code=frame[15] >> 4,
                    store_flags=frame[16], command_sequence=frame[17],
                    encoder_status=int.from_bytes(frame[18:20], 'little'),
                    encoder_active=bool(frame[19] & 0x80),
                    encoder_direction=bool(frame[19] & 0x40),
                    encoder_depth=(int.from_bytes(frame[18:20], 'little') & 0x3fff),
                    distance=0,
                    gesture=frame[20], pressure_valid=frame[21],
                    pressure=[int.from_bytes(frame[22+i*2:24+i*2], 'little')
                              for i in range(7)], extended=True)
                if frame[12] & 0x80:
                    decoded['encoder_diagnostic'] = dict(
                        raw_a=bool(frame[10] & 0x20), raw_b=bool(frame[10] & 0x10),
                        seen_a=bool(frame[10] & 0x80), seen_b=bool(frame[10] & 0x40),
                        filtered_a=bool(frame[12] & 0x10), filtered_b=bool(frame[12] & 0x08),
                        legal_seen=bool(frame[12] & 0x20), illegal_seen=bool(frame[12] & 0x40),
                        count=frame[13] >> 2)
                if size >= 74:
                    names=('audio_frames','audio_bad_b','audio_bad_c','audio_crc_b',
                           'audio_crc_c','audio_sequence_b','audio_sequence_c',
                           'audio_version_b','audio_version_c')
                    decoded.update({name:int.from_bytes(frame[36+i*4:40+i*4],'little')
                                    for i,name in enumerate(names)})
                if size >= 88:
                    raw=frame[72:86]
                    decoded['aux_diagnostic']=dict(
                        pc=raw[0]|((raw[1]&1)<<8), state=(raw[1]>>1)&7,
                        busy=bool(raw[1]&16), scl=bool(raw[1]&32), sda=bool(raw[1]&64),
                        valid=bool(raw[1]&128), error=raw[2],
                        fail_pc=raw[3]|((raw[4]&1)<<8), chip=(raw[4]>>1)&1,
                        fail_reg=raw[5], model_id=raw[6], fail_read=raw[7],
                        range_status=raw[8], attempts=raw[9], ranges=raw[10],
                        transactions=raw[11], last_reg=raw[12], bus_fault=raw[13]&7)
                if size == 108:
                    raw=frame[86:106]
                    bits=int.from_bytes(raw[4:20], 'little')
                    decoded['aux_probe']=dict(phase=raw[0], flags=raw[1], rounds=raw[2],
                        ack_count=raw[3], addresses=[i for i in range(8,120) if bits & (1<<i)])
                frames.append(decoded)
        return frames
