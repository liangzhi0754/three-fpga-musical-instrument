"""Tang Nano 20K seven-key visual host.

The FPGA remains the synthesizer. This program only receives sensor status and
draws a live instrument panel. It uses tkinter and pyserial, both already
prepared on this computer.
"""
import queue
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

import serial
from serial.tools import list_ports


KEY_NAMES = ("Do", "Re", "Mi", "Fa", "Sol", "La", "Si")
FRAME_LENGTH = 12
DISPLAY_HOLD_SECONDS = 0.07


class FrameParser:
    def __init__(self):
        self.buf = bytearray()

    def feed(self, data):
        self.buf.extend(data)
        frames = []
        while True:
            start = self.buf.find(b"\xAA\x55")
            if start < 0:
                self.buf = self.buf[-1:]
                break
            if start:
                del self.buf[:start]
            if len(self.buf) < FRAME_LENGTH:
                break
            frame = bytes(self.buf[:FRAME_LENGTH])
            del self.buf[:FRAME_LENGTH]
            # bytes 2..9 are sequence, touch, ADC low/high, volume low/high,
            # flags and timbre; byte 10 is their 8-bit sum, byte 11 is 0D.
            if frame[11] != 0x0D:
                continue
            expected = sum(frame[2:10]) & 0xFF
            if frame[10] != expected:
                continue
            frames.append({
                "touch": frame[3] & 0x7F,
                "pitch": frame[4] | (frame[5] << 8),
                "volume": frame[6] | (frame[7] << 8),
                "mpr": bool(frame[8] & 0x01),
                "ads": bool(frame[8] & 0x02),
                "adc_valid": bool(frame[8] & 0x04),
                "volume_valid": bool(frame[8] & 0x08),
                "timbre": frame[9] & 0x03,
            })
        return frames


class PianoHost(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("FPGA 实时电子乐器 · 七键演奏监视器")
        self.geometry("1120x700")
        self.minsize(900, 580)
        self.configure(bg="#101923")
        self.serial_port = None
        self.reader_thread = None
        self.stop_reader = threading.Event()
        self.inbox = queue.Queue()
        self.last_frame_time = 0.0
        self.visible_touch = 0
        self.key_hold_until = [0.0] * 7
        self.current = {"touch": 0, "pitch": 0, "volume": 0, "mpr": False,
                        "ads": False, "adc_valid": False,
                        "volume_valid": False, "timbre": 0}
        self.key_widgets = []
        self.build_ui()
        self.refresh_ports()
        self.after(8, self.process_inbox)
        self.after(250, self.refresh_connection_state)
        self.protocol("WM_DELETE_WINDOW", self.close)

    def build_ui(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Panel.TFrame", background="#172532")
        style.configure("Title.TLabel", background="#101923", foreground="#f5f8fa",
                        font=("Microsoft YaHei UI", 20, "bold"))
        style.configure("Sub.TLabel", background="#101923", foreground="#9cb0bf",
                        font=("Microsoft YaHei UI", 10))
        style.configure("Panel.TLabel", background="#172532", foreground="#e8f0f5",
                        font=("Microsoft YaHei UI", 11))
        style.configure("Value.TLabel", background="#172532", foreground="#72e6c2",
                        font=("Consolas", 17, "bold"))
        style.configure("TButton", padding=(10, 6))

        top = ttk.Frame(self, style="Panel.TFrame", padding=18)
        top.pack(fill="x", padx=18, pady=(18, 10))
        ttk.Label(top, text="FPGA 实时电子乐器", style="Title.TLabel").pack(anchor="w")
        ttk.Label(top, text="七键触摸演奏 · FPGA 状态实时反馈", style="Sub.TLabel").pack(anchor="w", pady=(4, 0))

        conn = ttk.Frame(top, style="Panel.TFrame")
        conn.pack(anchor="e", fill="x", pady=(0, 0))
        ttk.Label(conn, text="串口", style="Panel.TLabel").pack(side="left", padx=(0, 8))
        self.port_combo = ttk.Combobox(conn, width=12, state="readonly")
        self.port_combo.pack(side="left")
        ttk.Button(conn, text="刷新", command=self.refresh_ports).pack(side="left", padx=6)
        self.connect_button = ttk.Button(conn, text="连接", command=self.toggle_connection)
        self.connect_button.pack(side="left")
        self.connection_label = ttk.Label(conn, text="未连接", style="Panel.TLabel")
        self.connection_label.pack(side="left", padx=12)

        body = ttk.Frame(self, style="Panel.TFrame", padding=18)
        body.pack(fill="both", expand=True, padx=18, pady=10)
        ttk.Label(body, text="演奏键盘", style="Title.TLabel", font=("Microsoft YaHei UI", 15, "bold")).pack(anchor="w")
        self.keyboard = tk.Frame(body, bg="#0b1117", height=290)
        self.keyboard.pack(fill="x", pady=(14, 24))
        self.keyboard.pack_propagate(False)
        for i, name in enumerate(KEY_NAMES):
            key = tk.Frame(self.keyboard, bg="#edf3f5", bd=1, relief="solid", cursor="hand2")
            key.place(relx=i / 7, rely=0, relwidth=1 / 7, relheight=1)
            label = tk.Label(key, text=name, bg="#edf3f5", fg="#253746",
                             font=("Microsoft YaHei UI", 15, "bold"))
            label.pack(side="bottom", pady=22)
            self.key_widgets.append((key, label))

        stats = ttk.Frame(body, style="Panel.TFrame")
        stats.pack(fill="x")
        self.pitch_value = self.add_stat(stats, "音高控制 A0", 0)
        self.volume_value = self.add_stat(stats, "音量控制 A1", 1)
        self.timbre_value = self.add_stat(stats, "当前音色", 2)
        self.sensor_value = self.add_stat(stats, "传感器状态", 3)

        self.progress_pitch = ttk.Progressbar(body, maximum=26400, length=400)
        self.progress_pitch.pack(fill="x", pady=(24, 8))
        self.progress_volume = ttk.Progressbar(body, maximum=26400, length=400)
        self.progress_volume.pack(fill="x")
        self.hint = ttk.Label(body, text="等待 FPGA 状态帧……烧录新工程后点击连接。",
                              style="Sub.TLabel")
        self.hint.pack(anchor="w", pady=(20, 0))

    def add_stat(self, parent, title, column):
        panel = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        panel.grid(row=0, column=column, sticky="nsew", padx=5)
        parent.columnconfigure(column, weight=1)
        ttk.Label(panel, text=title, style="Panel.TLabel").pack(anchor="w")
        value = ttk.Label(panel, text="--", style="Value.TLabel")
        value.pack(anchor="w", pady=(8, 0))
        return value

    def refresh_ports(self):
        port_info = list(list_ports.comports())
        ports = sorted({p.device for p in port_info}, key=lambda x: int(x[3:]) if x[3:].isdigit() else x)
        self.port_combo["values"] = ports
        if ports:
            # The verified HW-597 adapter enumerates as CH340. Bluetooth COM
            # ports can also appear and should not be chosen by default.
            adapter = next((p.device for p in port_info
                            if p.vid == 0x1A86 and p.pid == 0x7523), None)
            preferred = adapter or ports[0]
            self.port_combo.set(preferred)
        else:
            self.port_combo.set("")

    def toggle_connection(self):
        if self.serial_port:
            self.disconnect()
        else:
            self.connect()

    def connect(self):
        name = self.port_combo.get().strip()
        if not name:
            messagebox.showwarning("没有串口", "请先点击刷新，再选择 COM8 或 COM9。")
            return
        try:
            self.serial_port = serial.Serial(name, 115200, timeout=0.01)
        except serial.SerialException as exc:
            messagebox.showerror("串口打开失败", f"{name}\n{exc}")
            return
        self.stop_reader.clear()
        self.reader_thread = threading.Thread(target=self.read_serial, daemon=True)
        self.reader_thread.start()
        self.connect_button.configure(text="断开")
        self.connection_label.configure(text=f"已连接 {name}")
        self.hint.configure(text="正在等待 FPGA 状态帧……")

    def disconnect(self):
        self.stop_reader.set()
        if self.serial_port:
            try:
                self.serial_port.close()
            except serial.SerialException:
                pass
        self.serial_port = None
        self.current["touch"] = 0
        self.key_hold_until = [0.0] * 7
        self.visible_touch = 0
        for key, label in self.key_widgets:
            key.configure(bg="#edf3f5")
            label.configure(bg="#edf3f5")
        self.connect_button.configure(text="连接")
        self.connection_label.configure(text="未连接")

    def read_serial(self):
        parser = FrameParser()
        port = self.serial_port
        while not self.stop_reader.is_set():
            try:
                data = port.read(1)
                if data:
                    data += port.read(port.in_waiting)
            except (serial.SerialException, OSError):
                break
            for frame in parser.feed(data):
                self.inbox.put(frame)

    def process_inbox(self):
        received = False
        pressed_during_batch = 0
        while True:
            try:
                frame = self.inbox.get_nowait()
            except queue.Empty:
                break
            received = True
            self.current = frame
            now = time.monotonic()
            self.last_frame_time = now
            pressed_during_batch |= frame["touch"]
        now = time.monotonic()
        missed_taps = pressed_during_batch & ~self.current["touch"] & ~self.visible_touch
        for i in range(7):
            if missed_taps & (1 << i):
                self.key_hold_until[i] = now + DISPLAY_HOLD_SECONDS
        visible = self.current["touch"]
        for i in range(7):
            if now < self.key_hold_until[i]:
                visible |= 1 << i
        if received or visible != self.visible_touch:
            self.visible_touch = visible
            self.render(self.current, visible)
        self.after(8, self.process_inbox)

    def render(self, data, touch):
        for i, (key, label) in enumerate(self.key_widgets):
            active = bool(touch & (1 << i))
            key.configure(bg="#38d6a4" if active else "#edf3f5")
            label.configure(bg="#38d6a4" if active else "#edf3f5")
        pitch = data["pitch"]
        volume = data["volume"]
        self.pitch_value.configure(text=f"{pitch / 26400 * 100:5.1f}%")
        self.volume_value.configure(text=f"{volume / 26400 * 100:5.1f}%")
        self.progress_pitch["value"] = min(pitch, 26400)
        self.progress_volume["value"] = min(volume, 26400)
        names = ("正弦", "锯齿", "方波", "大提琴32")
        self.timbre_value.configure(text=names[data["timbre"]])
        self.sensor_value.configure(text=f"MPR121 {'在线' if data['mpr'] else '离线'} / ADS1115 {'在线' if data['ads'] else '离线'}")
        self.hint.configure(text="已接收 FPGA 状态帧 · 触摸铜箔时对应琴键会点亮")

    def refresh_connection_state(self):
        if self.serial_port and self.last_frame_time and time.monotonic() - self.last_frame_time > 2:
            self.connection_label.configure(text=f"已连接 {self.port_combo.get()} · 无数据")
        self.after(250, self.refresh_connection_state)

    def close(self):
        self.disconnect()
        self.destroy()


if __name__ == "__main__":
    PianoHost().mainloop()
