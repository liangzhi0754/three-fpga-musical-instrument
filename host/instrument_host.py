"""Serial monitor and command UI. All audio synthesis stays on the FPGAs."""
import queue
import threading
import time
import tkinter as tk
from tkinter import messagebox

import serial
from serial.tools import list_ports

from instrument_panel import InstrumentPanel, BG, RED, MINT, MUTED
from three_board_protocol import FrameParser, command_packet

DISPLAY_HOLD_SECONDS = 0.025


class InstrumentHost(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("弦 · 竹 | FPGA 实时电子乐器 · OLED同源波形 v25")
        self.geometry("1280x920")
        self.minsize(1080, 780)
        self.configure(bg=BG)
        self.serial_port = None
        self.reader_thread = None
        self.stop_reader = threading.Event()
        self.inbox = queue.Queue()
        self.last_frame_time = 0.0
        self.visible_touch = 0
        self.key_hold_until = [0.0] * 7
        self.command_sequence = 0
        self.pending_command = None
        self.monitor_only = tk.BooleanVar(value=False)
        self.current = {"touch": 0, "pitch": 0, "volume": 0, "mpr": False,
                        "ads": False, "adc_valid": False, "volume_valid": False,
                        "timbre": 0, "extended": False}
        self.panel = InstrumentPanel(self, self.refresh_ports,
                                     self.toggle_connection, self.toggle_fullscreen,
                                     self.send_command)
        self.panel.pack(fill="both", expand=True)
        tk.Checkbutton(self.panel.mode_row, text="电脑仅监视（关闭电脑控制）",
                       variable=self.monitor_only, command=self.change_control_mode,
                       bg=BG).pack(side="left")
        self.change_control_mode()
        self.refresh_ports()
        self.after(8, self.process_inbox)
        self.after(250, self.refresh_connection_state)
        self.bind("<Escape>", lambda event: self.attributes("-fullscreen", False))
        self.protocol("WM_DELETE_WINDOW", self.close)

    def toggle_fullscreen(self):
        self.attributes("-fullscreen", not self.attributes("-fullscreen"))

    def refresh_ports(self):
        info = list(list_ports.comports())
        ports = sorted({p.device for p in info})
        current = self.panel.port_combo.get()
        self.panel.port_combo["values"] = ports
        if current in ports:
            self.panel.port_combo.set(current)
        elif ports:
            adapter = next((p.device for p in info
                            if p.vid == 0x1A86 and p.pid == 0x7523), None)
            self.panel.port_combo.set(adapter or ports[0])
        else:
            self.panel.port_combo.set("")

    def toggle_connection(self):
        self.disconnect() if self.serial_port else self.connect()

    def connect(self):
        name = self.panel.port_combo.get().strip()
        if not name:
            messagebox.showwarning("没有串口", "请连接 USB-TTL 模块后刷新。")
            return
        try:
            self.serial_port = serial.Serial(name, 115200, timeout=0.01,
                                              write_timeout=0.2)
        except (serial.SerialException, OSError) as exc:
            messagebox.showerror("串口打开失败", f"{name}\n{exc}")
            return
        self.stop_reader = threading.Event()
        self.reader_thread = threading.Thread(target=self.read_serial,
            args=(self.serial_port, self.stop_reader), daemon=True)
        self.reader_thread.start()
        self.last_frame_time = 0.0
        self.panel.connect_button.configure(text="断开")
        self.panel.connection_label.configure(text=f"已连接 {name}", fg=MINT)
        self.panel.frame_label.configure(text="等待 FPGA 状态帧", fg=MUTED)

    def disconnect(self):
        self.stop_reader.set()
        if self.reader_thread:
            self.reader_thread.join(timeout=0.3)
        if self.serial_port:
            try:
                self.serial_port.close()
            except (serial.SerialException, OSError):
                pass
        self.serial_port = None
        self.last_frame_time = 0.0
        self.pending_command = None
        self.current["touch"] = 0
        self.current["extended"] = False
        self.key_hold_until = [0.0] * 7
        self.visible_touch = 0
        while not self.inbox.empty():
            self.inbox.get_nowait()
        self.panel.reset_touch()
        self.panel.set_commands_enabled(False)
        self.panel.connect_button.configure(text="连接")
        self.panel.connection_label.configure(text="未连接", fg=RED)
        self.panel.frame_label.configure(text="等待 FPGA 数据", fg=MUTED)

    def read_serial(self, port, stop):
        parser = FrameParser()
        while not stop.is_set():
            try:
                data = port.read(1)
                if data:
                    data += port.read(port.in_waiting)
            except (serial.SerialException, OSError):
                break
            for frame in parser.feed(data):
                self.inbox.put(frame)

    def send_command(self, opcode, argument=0):
        if self.monitor_only.get():
            self.panel.command_label.configure(text="仅监视：请用手机或实体按键控制", fg=MUTED)
            return
        if (not self.serial_port or not self.current.get("extended") or
                time.monotonic() - self.last_frame_time > 2):
            return
        if self.pending_command and opcode != 0x12:
            self.panel.command_label.configure(text="上一条指令等待回执", fg=MUTED)
            return
        if opcode in (0x10, 0x11, 0x13, 0x14):
            state = self.current.get("store_status", 0)
            flags = self.current.get("store_flags", 0)
            if state in (1, 2, 3, 4, 5, 6, 15):
                self.panel.command_label.configure(text="存储忙，请先停止并等待收尾完成", fg=MUTED)
                return
            if opcode == 0x11 and not flags & 4:
                self.panel.command_label.configure(text="请先准备录制区，等到显示可录制再开始", fg=RED)
                return
        if opcode == 0x10 and not messagebox.askyesno(
                "清空录制区", "将删除已有演奏记录，参数区保留。继续吗？"):
            return
        # Avoid matching an old receipt immediately after restarting this UI.
        self.command_sequence = (self.current.get("command_sequence", self.command_sequence) % 255) + 1
        try:
            packet = command_packet(self.command_sequence, opcode, argument)
            if self.serial_port.write(packet) != len(packet):
                raise serial.SerialTimeoutException("指令未完整发送")
        except (serial.SerialException, OSError) as exc:
            self.panel.command_label.configure(text=f"发送失败：{exc}", fg=RED)
            return
        self.pending_command = (self.command_sequence, time.monotonic())
        self.panel.command_label.configure(text="等待板 A 接收", fg=MUTED)

    def process_inbox(self):
        received = False
        pressed_during_batch = 0
        while True:
            try:
                frame = self.inbox.get_nowait()
            except queue.Empty:
                break
            if frame.get("kind") == "waveform":
                self.panel.update_waveform(frame)
                continue
            received = True
            self.current = frame
            self.last_frame_time = time.monotonic()
            pressed_during_batch |= frame["touch"]
            if (self.pending_command and frame.get("command_sequence") ==
                    self.pending_command[0]):
                self.pending_command = None
                self.panel.command_label.configure(text="指令已接收", fg=MINT)
        now = time.monotonic()
        missed = pressed_during_batch & ~self.current["touch"] & ~self.visible_touch
        for i in range(7):
            if missed & (1 << i):
                self.key_hold_until[i] = now + DISPLAY_HOLD_SECONDS
        visible = self.current["touch"]
        for i in range(7):
            if now < self.key_hold_until[i]:
                visible |= 1 << i
        if received or visible != self.visible_touch:
            self.visible_touch = visible
            self.panel.update_state(self.current, visible)
        if received:
            self.panel.frame_label.configure(text="三板协议实时接收" if
                self.current.get("extended") else "单板旧协议：仅监测", fg=MINT)
            self.panel.connection_label.configure(
                text=f"已连接 {self.panel.port_combo.get()}", fg=MINT)
            self.panel.set_commands_enabled(self.current.get("extended", False)
                                            and not self.monitor_only.get())
        self.after(8, self.process_inbox)

    def refresh_connection_state(self):
        now = time.monotonic()
        if self.serial_port and self.last_frame_time and now - self.last_frame_time > 2:
            self.panel.connection_label.configure(text="通信中断", fg=RED)
            self.panel.set_commands_enabled(False)
            self.panel.reset_touch()
        if self.pending_command and now - self.pending_command[1] > 1:
            self.pending_command = None
            self.panel.command_label.configure(text="未收到电脑回执：请核对 v11 A板程序及 TXD→A86、RXD→A52", fg=RED)
        self.after(250, self.refresh_connection_state)

    def change_control_mode(self):
        self.pending_command = None
        monitor = self.monitor_only.get()
        online = bool(self.serial_port and self.current.get("extended") and
                      time.monotonic() - self.last_frame_time <= 2)
        self.panel.set_commands_enabled(online and not monitor)
        self.panel.command_label.configure(text=(
            "电脑仅监视；手机和实体按键照常控制"
            if monitor else
            "双端控制：USB-TTL TXD→A86、RXD→A52；ESP32仍用A80/A76"), fg=MUTED)

    def close(self):
        self.disconnect()
        self.destroy()


if __name__ == "__main__":
    InstrumentHost().mainloop()
