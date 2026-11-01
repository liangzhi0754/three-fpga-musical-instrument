import time
import unittest
from unittest.mock import Mock
from instrument_host import InstrumentHost


class ControlModeTests(unittest.TestCase):
    def host(self, monitor=True):
        host = object.__new__(InstrumentHost)
        host.monitor_only = Mock()
        host.monitor_only.get.return_value = monitor
        host.panel = Mock()
        host.serial_port = Mock()
        host.current = {"extended": True}
        host.last_frame_time = time.monotonic()
        host.pending_command = None
        host.command_sequence = 0
        return host

    def test_monitor_never_writes_even_if_called_directly(self):
        host = self.host()
        host.send_command(2, 2)
        host.serial_port.write.assert_not_called()
        self.assertIsNone(host.pending_command)

    def test_monitor_clears_old_ack_and_disables_buttons(self):
        host = self.host()
        host.pending_command = (3, time.monotonic())
        host.change_control_mode()
        self.assertIsNone(host.pending_command)
        host.panel.set_commands_enabled.assert_called_once_with(False)

    def test_pc_mode_can_write_existing_protocol(self):
        host = self.host(False)
        host.serial_port.write.side_effect = len
        host.change_control_mode()
        host.panel.set_commands_enabled.assert_called_once_with(True)
        host.send_command(2, 2)
        self.assertEqual(host.serial_port.write.call_args.args[0][:2], b"CM")
        self.assertEqual(host.pending_command[0], 1)

    def test_pc_mode_cannot_enable_on_stale_data(self):
        host = self.host(False)
        host.last_frame_time -= 3
        host.change_control_mode()
        host.panel.set_commands_enabled.assert_called_once_with(False)

    def test_new_sequence_differs_from_last_pc_receipt(self):
        host = self.host(False)
        host.current["command_sequence"] = 1
        host.serial_port.write.side_effect = len
        host.send_command(1, 2)
        self.assertEqual(host.pending_command[0], 2)
        host.current["command_sequence"] = 255
        host.pending_command = None
        host.send_command(1, 1)
        self.assertEqual(host.pending_command[0], 1)

    def test_stop_can_replace_pending_receipt(self):
        host = self.host(False)
        host.serial_port.write.side_effect = len
        host.pending_command = (5, time.monotonic())
        host.send_command(0x12)
        self.assertEqual(host.serial_port.write.call_args.args[0][3], 0x12)

    def test_record_requires_prepared_and_does_not_queue_while_busy(self):
        host = self.host(False)
        host.send_command(0x11)
        host.serial_port.write.assert_not_called()
        host.current.update(store_status=2, store_flags=4)
        host.send_command(0x11)
        host.serial_port.write.assert_not_called()
        host.current.update(store_status=0, store_flags=4)
        host.serial_port.write.side_effect = len
        host.send_command(0x11)
        host.serial_port.write.assert_called_once()


if __name__ == "__main__":
    unittest.main()
