import unittest
from unittest.mock import Mock

from instrument_panel import InstrumentPanel, TIMBRES


class PanelStatusTests(unittest.TestCase):
    def test_cello_has_clear_name(self):
        self.assertEqual(TIMBRES[3], "大提琴 32")

    def panel(self):
        panel = object.__new__(InstrumentPanel)
        for name in ("screen_kicker", "screen_main", "screen_sub", "touch_count",
                     "pitch_value", "volume_value", "pitch_meter", "volume_meter",
                     "mpr_label", "ads_label", "link_label", "distance_label",
                     "store_label", "pressure_label", "audio_diagnostic_label", "aux_diagnostic_label"):
            setattr(panel, name, Mock())
        panel._draw_activity = Mock()
        panel._draw_keyboard = Mock()
        panel._draw_meter = Mock()
        panel._paint_timbre = Mock()
        panel.feature_vars = [Mock() for _ in range(3)]
        panel.view = "performance"
        panel.pitch_percent = panel.volume_percent = 0.5
        panel.display_touch = 0b10101
        panel.timbre = 3
        return panel

    def test_strings_report_all_chord_notes(self):
        panel = self.panel()
        panel._update_screen()
        self.assertEqual(panel.screen_main.configure.call_args.kwargs["text"], "3 音同时")
        self.assertIn("Mi", panel.screen_sub.configure.call_args.kwargs["text"])
        self.assertEqual(TIMBRES[4], "空灵竹笛 32")
        panel.timbre = 4
        panel._update_screen()
        self.assertEqual(panel.screen_main.configure.call_args.kwargs["text"], "3 音同时")
        panel.timbre = 0
        panel._update_screen()
        self.assertEqual(panel.screen_main.configure.call_args.kwargs["text"], "3 音同时")

    def test_toggle_changes_only_clicked_feature(self):
        panel = self.panel()
        panel.on_command = Mock()
        panel.feature_vars[1].get.return_value = 1
        panel.toggle_feature(1)
        panel.on_command.assert_called_with(3, 0x0202)
        panel.feature_vars[1].get.return_value = 0
        panel.toggle_feature(1)
        panel.on_command.assert_called_with(3, 0x0200)

    def test_pressure_bend_switch_sends_existing_bit0(self):
        panel = self.panel()
        panel.on_command = Mock()
        panel.feature_vars[0].get.return_value = 1
        panel.toggle_feature(0)
        panel.on_command.assert_called_with(3, 0x0101)
        panel.feature_vars[0].get.return_value = 0
        panel.toggle_feature(0)
        panel.on_command.assert_called_with(3, 0x0100)

    def test_busy_storage_is_not_hidden_by_prepared_flag(self):
        panel = self.panel()
        data = dict(pitch=13200, volume=13200, timbre=0, mpr=True, ads=True,
                    extended=True, links=3, features=0, distance=200,
                    aux_online=3, gesture=0, store_status=5, store_flags=4,
                    pressure_valid=127, pressure=[0] * 7)
        panel.update_state(data, 0)
        self.assertEqual(panel.store_label.configure.call_args.kwargs["text"], "保存参数中")
        data["store_status"] = 0
        panel.update_state(data, 0)
        self.assertEqual(panel.store_label.configure.call_args.kwargs["text"], "可录制")

    def test_audio_failure_counters_remain_visible_when_link_recovers(self):
        panel = self.panel()
        data = dict(pitch=13200, volume=13200, timbre=0, mpr=True, ads=True,
                    extended=True, links=3, features=0, distance=200,
                    aux_online=3, gesture=0, store_status=0, store_flags=0,
                    pressure_valid=0, pressure=[0] * 7, audio_frames=1000,
                    audio_bad_b=0, audio_bad_c=25, audio_crc_b=0, audio_crc_c=24,
                    audio_sequence_b=0, audio_sequence_c=1,
                    audio_version_b=0, audio_version_c=0)
        panel.update_state(data, 0)
        self.assertIn("C 正常", panel.link_label.configure.call_args.kwargs["text"])
        text = panel.audio_diagnostic_label.configure.call_args.kwargs["text"]
        self.assertIn("失败 B 0 / C 25", text)
        self.assertIn("CRC B 0 / C 24", text)
        self.assertIn("帧号 B 0 / C 1", text)

    def test_storage_fault_is_explained_and_stopping_is_visible(self):
        panel = self.panel()
        data = dict(pitch=0, volume=0, timbre=0, mpr=True, ads=True,
                    extended=True, links=3, features=0, gesture=0,
                    store_status=6, store_flags=0, pressure_valid=0, pressure=[0]*7)
        panel.update_state(data, 0)
        self.assertEqual(panel.store_label.configure.call_args.kwargs['text'], '停止收尾中')
        data.update(store_status=0, store_flags=8, store_fault_code=4)
        panel.update_state(data, 0)
        self.assertIn('缓存溢出', panel.store_label.configure.call_args.kwargs['text'])


if __name__ == "__main__":
    unittest.main()
