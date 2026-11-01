import unittest

from aux_diagnostic import format_aux_diagnostic


class DiagnosticTests(unittest.TestCase):
    def data(self):
        return dict(aux_online=0, aux_diagnostic=dict(
            pc=218, state=0, error=1, chip=0, bus_fault=1, fail_pc=1,
            fail_reg=0xC0, fail_read=0, model_id=0, valid=False,
            attempts=1, transactions=2, ranges=0, scl=True, sda=True))

    def test_missing_sensor_is_not_hidden_by_absent_gesture(self):
        self.assertIn("地址写入无应答", format_aux_diagnostic(self.data()))

    def test_timeout_and_bad_id_are_distinct(self):
        data = self.data()
        data['aux_diagnostic']['error'] = 2
        self.assertIn("就绪超时", format_aux_diagnostic(data))
        data['aux_diagnostic'].update(error=3, fail_read=0xEA)
        self.assertIn("0xEA", format_aux_diagnostic(data))

    def test_old_firmware_and_range_validity(self):
        self.assertIn("旧版", format_aux_diagnostic({}))
        data = self.data()
        data['aux_online'] = 1
        self.assertIn("等待有效距离", format_aux_diagnostic(data))
        data['aux_diagnostic']['valid'] = True
        self.assertIn("距离有效", format_aux_diagnostic(data))

    def test_probe_distinguishes_no_ack_and_pin_failure(self):
        data = self.data()
        data['aux_probe'] = dict(phase=255, flags=127, rounds=1,
                                 addresses=[], ack_count=0)
        self.assertIn("应答地址：无", format_aux_diagnostic(data))
        data['aux_probe']['addresses'] = [0x29]
        self.assertIn("0x29", format_aux_diagnostic(data))
        data['aux_probe'].update(phase=254, flags=127 & ~(1 << 4))
        self.assertIn("SDA未能拉低", format_aux_diagnostic(data))

    def test_gesture_identity_error_is_shown(self):
        data = self.data()
        data['aux_diagnostic'].update(chip=1, error=3, fail_read=0x21,
                                      fail_reg=0, fail_pc=162)
        data['aux_probe'] = dict(phase=255, flags=127, rounds=2,
                                addresses=[0x73], ack_count=1)
        text = format_aux_diagnostic(data)
        self.assertIn('手势寄存器校验失败', text)
        self.assertIn('0x21', text)
        self.assertIn('初始化未完成', text)

    def test_gesture_online_is_independent_of_distance(self):
        data = self.data()
        data['aux_online'] = 2
        data['aux_probe'] = dict(phase=255, flags=127, rounds=1,
                                addresses=[], ack_count=0)
        text = format_aux_diagnostic(data)
        self.assertIn('初始化完成，正在读取动作', text)
        self.assertIn('SCL→A54 / SDA→A55', text)

    def test_encoder_evidence_is_visible_without_enabling_effect(self):
        data = dict(encoder_status=0, features=0, aux_online=2,
                    encoder_diagnostic=dict(raw_a=True, raw_b=False,
                    seen_a=True, seen_b=False, count=3, legal_seen=True,
                    illegal_seen=False))
        text = format_aux_diagnostic(data)
        self.assertIn('A25=1 B56=0', text)
        self.assertIn('动作计数=3', text)
        self.assertIn('A变化=有 B变化=无', text)
