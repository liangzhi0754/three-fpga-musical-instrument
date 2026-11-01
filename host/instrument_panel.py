from aux_diagnostic import format_aux_diagnostic
"""Responsive instrument-style display for the FPGA status stream."""
import tkinter as tk
import math
import time
from tkinter import ttk


KEY_NAMES = ("Do", "Re", "Mi", "Fa", "Sol", "La", "Si")
KEY_PITCHES = ("C4", "D4", "E4", "F4", "G4", "A4", "B4")
TIMBRES = ("正弦", "锯齿", "方波", "大提琴 32", "空灵竹笛 32")

BG = "#080b14"
PANEL = "#0f1422"
PANEL_LIGHT = "#171e30"
SCREEN = "#131125"
TEXT = "#edf4ff"
MUTED = "#9aa9c2"
MINT = "#00f0ff"
AMBER = "#ff2080"
PURPLE = "#9040ff"
RED = "#ff789f"
WHITE_KEY = "#e8eef7"
WHITE_ACTIVE = "#12677e"
LINE = "#252d42"
KEYBED = "#0c1320"


class InstrumentPanel(tk.Frame):
    def __init__(self, master, on_refresh, on_connect, on_fullscreen, on_command=None):
        super().__init__(master, bg=BG)
        self.on_refresh = on_refresh
        self.on_connect = on_connect
        self.on_fullscreen = on_fullscreen
        self.on_command = on_command or (lambda *_: None)
        self.command_controls = []
        self.storage_controls = {}
        self.controls_enabled = False
        self.last_storage = (0, 0)
        self.display_touch = 0
        self.view = "performance"
        self.pitch_percent = 0.0
        self.volume_percent = 0.0
        self.timbre = 0
        self._wave_job = None
        self._wave_amp = 0.0
        self._wave_last = 0.0
        self._wave_time = 0.0
        self._wave_size = None
        self._wave_rays = []
        self._feature_cache = {}
        self._build()
        self.set_commands_enabled(False)
        self.bind("<Destroy>", self._dispose_animation, add="+")

    def _label(self, parent, text, size=10, color=TEXT, bg=PANEL, bold=False):
        return tk.Label(parent, text=text, font=("Microsoft YaHei UI", size, "bold" if bold else "normal"),
                        fg=color, bg=bg, anchor="w")

    def _button(self, parent, text, command, accent=False, width=None):
        button = tk.Button(parent, text=text, command=command, font=("Microsoft YaHei UI", 10, "bold"),
                           bg=MINT if accent else PANEL_LIGHT, fg=BG if accent else TEXT,
                           activebackground="#65f6ff" if accent else "#243049",
                           activeforeground=TEXT,
                           relief="flat", bd=0, padx=12, pady=5, cursor="hand2", width=width)
        return button

    def _pad(self, parent, text, command, color, variable=None):
        common = dict(text=text, command=command,
                      font=("Microsoft YaHei UI", 10, "bold"),
                      bg=color, fg="#101426", activebackground=color,
                      activeforeground="#101426", disabledforeground="#68738a",
                      relief="flat", bd=0, padx=10, pady=6, cursor="hand2",
                      anchor="w", highlightthickness=1, highlightbackground=color)
        if variable is None:
            return tk.Button(parent, **common)
        return tk.Checkbutton(parent, variable=variable, indicatoron=False,
                              selectcolor=color, **common)

    def _build(self):
        # Presentation only. Command callbacks, widget attributes and variables
        # match the original panel; the serial host is unmodified.
        stripe = tk.Canvas(self, height=3, bg=BG, bd=0, highlightthickness=0)
        stripe.pack(fill="x")
        stripe.bind("<Configure>", lambda event: self._draw_gradient(stripe))
        header = tk.Frame(self, bg=BG, height=64)
        header.pack(fill="x")
        header.pack_propagate(False)
        brand = tk.Frame(header, bg=BG)
        brand.pack(side="left", padx=28, pady=4)
        self._label(brand, "弦 · 竹", 17, TEXT, BG, True).pack(anchor="w")
        self._label(brand, "REALTIME INSTRUMENT  /  NEON STUDIO", 8, MUTED, BG).pack(anchor="w")
        controls = tk.Frame(header, bg=BG)
        controls.pack(side="right", padx=26, pady=12)
        self._label(controls, "设备串口", 9, MUTED, BG).pack(side="left", padx=(0, 10))
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Port.TCombobox", padding=6, fieldbackground=BG,
                        background=PANEL_LIGHT, foreground=TEXT, bordercolor=LINE,
                        arrowcolor=MINT)
        style.map("Port.TCombobox", fieldbackground=[("readonly", PANEL_LIGHT)],
                  foreground=[("readonly", TEXT)], selectbackground=[("readonly", PANEL_LIGHT)],
                  selectforeground=[("readonly", TEXT)])
        style.configure("Details.TNotebook", background=BG, borderwidth=0,
                        tabmargins=(0, 0, 0, 0), bordercolor=LINE,
                        lightcolor=LINE, darkcolor=LINE)
        style.configure("Details.TNotebook.Tab", font=("Microsoft YaHei UI", 9),
                        padding=(16, 5), background=PANEL_LIGHT, foreground=MUTED,
                        bordercolor=LINE, lightcolor=LINE, darkcolor=LINE)
        style.configure("Vertical.TScrollbar", background=PANEL_LIGHT, troughcolor=PANEL,
                        bordercolor=LINE, arrowcolor=MUTED, lightcolor=LINE, darkcolor=LINE)
        style.map("Details.TNotebook.Tab", background=[("selected", PANEL)],
                  foreground=[("selected", MINT)])
        self.port_combo = ttk.Combobox(controls, width=9, state="readonly", style="Port.TCombobox")
        self.port_combo.pack(side="left", padx=(0, 8))
        self._button(controls, "刷新", self.on_refresh).pack(side="left", padx=3)
        self.connect_button = self._button(controls, "连接", self.on_connect, accent=True, width=5)
        self.connect_button.pack(side="left", padx=3)
        self._button(controls, "全屏", self.on_fullscreen).pack(side="left", padx=(8, 0))

        status = tk.Frame(self, bg=BG, height=30)
        status.pack(fill="x")
        status.pack_propagate(False)
        self.connection_label = self._label(status, "●  未连接", 9, RED, BG, True)
        self.connection_label.pack(side="left", padx=28)
        self.frame_label = self._label(status, "等待 FPGA 数据", 9, MUTED, BG)
        self.frame_label.pack(side="right", padx=28)
        main = tk.Frame(self, bg=BG)
        main.pack(fill="both", expand=True, padx=24, pady=(3, 10))

        top = tk.Frame(main, bg=BG, height=90)
        top.pack(fill="x", pady=(0, 10))
        top.pack_propagate(False)
        section = tk.Frame(top, bg=BG)
        section.pack(side="left", fill="both", expand=True, pady=5)
        self._label(section, "01   音色选择    /    SOUND ENGINE", 9, MUTED, BG).pack(anchor="w", pady=(0, 8))
        modes = tk.Frame(section, bg=BG)
        modes.pack(fill="x")
        self.timbre_labels = []
        self.timbre_var = tk.IntVar(value=0)
        for index, name in enumerate(TIMBRES):
            subtitle = ("SINE", "SAW", "SQUARE", "CELLO / 32", "BAMBOO / 32")[index]
            chip = tk.Radiobutton(modes, text=name + "\n" + subtitle, indicatoron=False,
                variable=self.timbre_var, value=index,
                command=lambda n=index: self.on_command(1, n),
                font=("Microsoft YaHei UI", 10, "bold"),
                bg=PANEL, fg=MUTED, selectcolor="#17304a",
                activebackground=PANEL_LIGHT, activeforeground=TEXT,
                disabledforeground="#66758e", padx=12, pady=6, relief="flat", bd=0,
                highlightthickness=1, highlightbackground=LINE, anchor="w")
            chip.pack(side="left", fill="x", expand=True, padx=(0, 6))
            self.timbre_labels.append(chip)
            self.command_controls.append(chip)
        self._paint_timbre(0)
        right = tk.Frame(top, bg=PANEL)
        # Retain legacy view callbacks without occupying the approved layout.
        tabs = tk.Frame(right, bg=PANEL)
        tabs.pack()
        self.performance_button = self._button(tabs, "演奏", lambda: self.set_view("performance"))
        self.performance_button.pack(side="left", padx=(0, 5))
        self.monitor_button = self._button(tabs, "监测", lambda: self.set_view("monitor"))
        self.monitor_button.pack(side="left")
        self._paint_tabs()

        console = tk.Frame(main, bg=PANEL, height=154, highlightbackground=LINE, highlightthickness=1)
        console.pack(fill="x", pady=(0, 10))
        console.pack_propagate(False)
        self._console = console
        self.bind("<Configure>", self._resize_console, add="+")
        left = tk.Frame(console, bg=PANEL, width=156)
        left.pack(side="left", fill="y", padx=(18, 20), pady=8)
        left.pack_propagate(False)
        self.pitch_meter = self._meter(left, "音高 / A0", MINT)
        self.volume_meter = self._meter(left, "音量 / A1", AMBER)
        screen_edge = tk.Frame(console, bg=LINE)
        screen_edge.pack(side="left", fill="both", expand=True, pady=12, padx=(0, 14))
        screen = tk.Frame(screen_edge, bg=SCREEN)
        screen.pack(fill="both", expand=True, padx=1, pady=1)
        screen_header = tk.Frame(screen, bg=SCREEN)
        screen_header.pack(fill="x", padx=14, pady=(6, 0))
        self.screen_kicker = self._label(screen_header, "实际音频波形 · 等待A板波形数据", 9, MUTED, SCREEN)
        self.screen_kicker.pack(side="left")
        self.wave_timbre = self._label(screen_header, TIMBRES[0], 9, MINT, SCREEN)
        self.wave_timbre.pack(side="right")
        screen_footer = tk.Frame(screen, bg=SCREEN)
        screen_footer.pack(side="bottom", fill="x", padx=14, pady=(0, 6))
        self.screen_main = self._label(screen_footer, "等待演奏", 9, TEXT, SCREEN)
        self.screen_main.pack(side="right")
        self.screen_sub = self._label(screen_footer, "无按键", 9, MUTED, SCREEN)
        self.screen_sub.pack(side="left")
        self.activity = tk.Canvas(screen, bg=SCREEN, height=118, bd=0, highlightthickness=0)
        self.activity.pack(fill="both", expand=True, padx=8, pady=3)
        self.activity.bind("<Configure>", lambda event: self._draw_activity())
        sensors = tk.Frame(console, bg=PANEL, width=174)
        # Device labels remain updated and appear in the diagnostic tab below.
        sensors.pack_propagate(False)
        self._label(sensors, "设备状态", 9, MUTED).pack(anchor="w", pady=(0, 5))
        self.mpr_label = self._label(sensors, "●  MPR121  --", 10, MUTED, PANEL, True)
        self.mpr_label.pack(anchor="w", pady=(0, 2))
        self.ads_label = self._label(sensors, "●  ADS1115  --", 10, MUTED, PANEL, True)
        self.ads_label.pack(anchor="w", pady=(0, 2))
        touch_row = tk.Frame(sensors, bg=PANEL)
        touch_row.pack(fill="x", pady=(3, 0))
        self._label(touch_row, "演奏按键", 9, MUTED).pack(side="left")
        self.touch_count = self._label(touch_row, "0 / 7", 12, TEXT, PANEL, True)
        self.touch_count.pack(side="right")
        self.link_label = self._label(sensors, "B --  /  C --", 9, MUTED)
        self.link_label.pack(anchor="w", pady=(5, 0))

        # Less-used statistics/calibration occupy their own presentation tab.
        # No fields or actions are removed, and state updates run in both tabs.
        notebook = ttk.Notebook(main, height=177, style="Details.TNotebook")
        notebook.pack(fill="x", pady=(0, 3))
        expansion = tk.Frame(notebook, bg=PANEL)
        details_page = tk.Frame(notebook, bg=PANEL)
        detail_scroll = ttk.Scrollbar(details_page, orient="vertical")
        detail_scroll.pack(side="right", fill="y")
        detail_canvas = tk.Canvas(details_page, bg=PANEL, highlightthickness=0,
                                  yscrollcommand=detail_scroll.set)
        detail_canvas.pack(side="left", fill="both", expand=True)
        detail_scroll.configure(command=detail_canvas.yview)
        details = tk.Frame(detail_canvas, bg=PANEL)
        detail_window = detail_canvas.create_window(0, 0, window=details, anchor="nw")
        details.bind("<Configure>", lambda event:
                     detail_canvas.configure(scrollregion=detail_canvas.bbox("all")))
        detail_canvas.bind("<Configure>", lambda event:
                           detail_canvas.itemconfigure(detail_window, width=event.width))
        self.diagnostic_canvas = detail_canvas
        notebook.add(expansion, text="演奏控制")
        notebook.add(details_page, text="诊断与校准")
        self.details_notebook = notebook
        self.mode_row = tk.Frame(details, bg=BG)
        self.mode_row.pack(fill="x", padx=12, pady=(5, 2))
        self.mode_row.bind("<Map>", lambda event: self._style_monitor_switch())
        self.command_label = self._label(main, "", 9, MUTED, BG)
        self.command_label.pack(fill="x", pady=(0, 6))
        groups = tk.Frame(expansion, bg=PANEL)
        groups.pack(fill="x", padx=10, pady=(4, 2))
        groups.columnconfigure(0, weight=3, uniform="groups")
        groups.columnconfigure(1, weight=2, uniform="groups")
        settings = tk.Frame(groups, bg=PANEL, highlightbackground=LINE, highlightthickness=1)
        settings.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        recorder = tk.Frame(groups, bg=PANEL, highlightbackground=LINE, highlightthickness=1)
        recorder.grid(row=0, column=1, sticky="nsew")
        self._label(settings, "演奏与设置  /  PERFORMANCE", 9, TEXT, PANEL, True).pack(anchor="w", padx=10, pady=(6, 5))
        self._label(recorder, "录制与重演  /  RECORDER", 9, TEXT, PANEL, True).pack(anchor="w", padx=10, pady=(6, 5))
        setting_grid = tk.Frame(settings, bg=PANEL)
        setting_grid.pack(fill="x", padx=8, pady=(0, 7))
        record_grid = tk.Frame(recorder, bg=PANEL)
        record_grid.pack(fill="x", padx=8, pady=(0, 7))
        for col in range(3): setting_grid.columnconfigure(col, weight=1, uniform="pads")
        for col in range(2): record_grid.columnconfigure(col, weight=1, uniform="pads")
        self.feature_vars = [tk.IntVar(value=0) for _ in range(3)]
        self.feature_controls = []
        self.feature_names = ("压力弯音", "编码器颤音", "手势切换")
        self.feature_colors = ("#d7bd80", "#d3cf56", "#55c9e7")
        for i, name in enumerate(self.feature_names):
            control = self._pad(setting_grid, name + "  ·  关闭", lambda n=i: self.toggle_feature(n),
                                self.feature_colors[i], self.feature_vars[i])
            control.grid(row=0, column=i, sticky="ew", padx=3, pady=3)
            self.command_controls.append(control)
            self.feature_controls.append(control)
            self.feature_vars[i].trace_add("write", lambda *args, n=i: self._paint_feature(n))
            self._paint_feature(i)
        control = self._pad(setting_grid, "重试手势", lambda: self.on_command(0x40), "#b291ed")
        control.grid(row=1, column=0, sticky="ew", padx=3, pady=3)
        self.command_controls.append(control)
        status_row = tk.Frame(expansion, bg=PANEL)
        status_row.pack(fill="x", padx=12)
        self.distance_label = self._label(status_row, "编码器 -- / 手势 --", 9, MUTED)
        self.distance_label.pack(side="left")
        record_colors = ("#ff954f", "#ff997d", "#ec79cf", "#ff736b")
        for name, op in (("准备录制区", 0x10), ("● 录制", 0x11),
                         ("■ 停止", 0x12), ("▶ 重演", 0x13),
                         ("保存参数", 0x14), ("压力零点", 0x30)):
            if op <= 0x13:
                index = op - 0x10
                control = self._pad(record_grid, name, lambda n=op: self.on_command(n), record_colors[index])
                control.grid(row=index // 2, column=index % 2, sticky="ew", padx=3, pady=3)
            else:
                col, color = (1, "#de80ad") if op == 0x14 else (2, "#69b8ed")
                control = self._pad(setting_grid, name, lambda n=op: self.on_command(n), color)
                control.grid(row=1, column=col, sticky="ew", padx=3, pady=3)
            self.command_controls.append(control)
            self.storage_controls[op] = control
        self.store_label = self._label(status_row, "存储 --", 9, MUTED)
        self.store_label.pack(side="right")
        sensors.destroy()
        sensors = tk.Frame(details, bg=PANEL)
        sensors.pack(fill="x", padx=12, pady=(5, 0))
        self.mpr_label = self._label(sensors, "● MPR121 --", 9, MUTED)
        self.ads_label = self._label(sensors, "● ADS1115 --", 9, MUTED)
        self.touch_count = self._label(sensors, "0 / 7", 9, MUTED)
        self.link_label = self._label(sensors, "B -- / C --", 9, MUTED)
        for label in (self.mpr_label, self.ads_label, self.touch_count, self.link_label):
            label.pack(side="left", padx=(0, 20))
        row = tk.Frame(details, bg=PANEL)
        row.pack(fill="x", padx=12, pady=(6, 2))
        self.cal_key = ttk.Combobox(row, values=KEY_NAMES, width=5, state="readonly", style="Port.TCombobox")
        self.cal_key.current(0)
        self.cal_key.pack(side="left", padx=(0, 7))
        control = self._button(row, "记录此键压力满点",
            lambda: self.on_command(0x31, 1 << self.cal_key.current()))
        control.configure(pady=3)
        control.pack(side="left")
        self.command_controls.append(control)
        self.pressure_label = self._label(row, "压力 ADC：--", 9, MUTED)
        self.pressure_label.pack(side="left", padx=16)
        self.audio_diagnostic_label = self._label(details, "音频校验：等待统计", 9, MUTED)
        self.audio_diagnostic_label.configure(justify="left")
        self.audio_diagnostic_label.pack(anchor="w", padx=12)
        self.aux_diagnostic_label = self._label(details, "辅助诊断：等待设备状态", 9, MUTED)
        self.aux_diagnostic_label.configure(wraplength=1160, justify="left")
        self.aux_diagnostic_label.pack(anchor="w", padx=12)

        keyboard_band = tk.Frame(main, bg=KEYBED, highlightbackground=LINE, highlightthickness=1)
        keyboard_band.pack(fill="both", expand=True)
        key_header = tk.Frame(keyboard_band, bg=KEYBED, height=35)
        key_header.pack(fill="x")
        key_header.pack_propagate(False)
        self._label(key_header, "02   七键演奏", 10, TEXT, KEYBED, True).pack(side="left", padx=18)
        self._label(key_header, "触摸铜箔 · 对应琴键亮起", 9, MUTED, KEYBED).pack(side="right", padx=18)
        stage = tk.Frame(keyboard_band, bg=KEYBED)
        stage.pack(fill="both", expand=True)
        self.decor_left = tk.Canvas(stage, bg=KEYBED, bd=0, highlightthickness=0)
        self.decor_left.place(relx=0, rely=0, relwidth=0.085, relheight=1)
        self.decor_right = tk.Canvas(stage, bg=KEYBED, bd=0, highlightthickness=0)
        self.decor_right.place(relx=0.915, rely=0, relwidth=0.085, relheight=1)
        keyboard_holder = tk.Frame(stage, bg=KEYBED)
        keyboard_holder.place(relx=0.085, rely=0, relwidth=0.83, relheight=1)
        self.keyboard = tk.Canvas(keyboard_holder, bg=KEYBED, bd=0, highlightthickness=0)
        self.keyboard.pack(fill="both", expand=True, padx=3, pady=(5, 16))
        self.decor_left.bind("<Configure>", lambda event: self._draw_decorations())
        self.decor_right.bind("<Configure>", lambda event: self._draw_decorations())
        self.keyboard.bind("<Configure>", lambda event: self._draw_keyboard())

    def _meter(self, parent, title, color):
        row = tk.Frame(parent, bg=PANEL)
        row.pack(fill="x", pady=(0, 6))
        self._label(row, title, 9, MUTED).pack(anchor="w")
        value = self._label(row, "--", 14, color, PANEL, True)
        value.pack(anchor="w")
        bar = tk.Canvas(row, height=9, bg=LINE, bd=0, highlightthickness=0)
        bar.pack(fill="x", pady=(3, 0))
        bar.bind("<Configure>", lambda event, c=bar, col=color: self._draw_meter(c, col))
        if title.startswith("音高"):
            self.pitch_value = value
        else:
            self.volume_value = value
        return bar

    def _draw_meter(self, canvas, color):
        fraction = self.pitch_percent if canvas == self.pitch_meter else self.volume_percent
        canvas.delete("all")
        width = max(1, canvas.winfo_width())
        canvas.create_rectangle(0, 0, width * fraction, 9, fill=color, outline="")

    def _resize_console(self, event):
        if event.widget is self:
            desired = 190 if event.height >= 830 else 154
            if int(self._console.cget("height")) != desired:
                self._console.configure(height=desired)

    @staticmethod
    def _mix_color(left, right, amount):
        channels = [round(int(left[n:n+2], 16) * (1-amount) + int(right[n:n+2], 16) * amount)
                    for n in (1, 3, 5)]
        return "#" + "".join(f"{value:02x}" for value in channels)

    def _draw_gradient(self, canvas):
        canvas.delete("all")
        width = max(1, canvas.winfo_width())
        for x in range(0, width, 4):
            u = x / width
            color = self._mix_color(MINT, PURPLE, u*2) if u < .5 else self._mix_color(PURPLE, AMBER, (u-.5)*2)
            canvas.create_rectangle(x, 0, x+4, 3, fill=color, outline="")

    def _style_monitor_switch(self):
        # The serial host creates this existing switch after building the panel.
        for widget in self.mode_row.winfo_children():
            if isinstance(widget, tk.Checkbutton):
                widget.configure(bg=BG, fg=MUTED, activebackground=BG,
                                 activeforeground=TEXT, selectcolor=PANEL_LIGHT,
                                 font=("Microsoft YaHei UI", 9))

    def _paint_feature(self, index):
        enabled = bool(self.feature_vars[index].get())
        if self._feature_cache.get(index) == enabled:
            return
        self._feature_cache[index] = enabled
        color = self.feature_colors[index]
        self.feature_controls[index].configure(
            text=self.feature_names[index] + ("  ·  开启" if enabled else "  ·  关闭"),
            bg=color if enabled else self._mix_color(PANEL, color, .17),
            fg="#101426" if enabled else TEXT)

    def _paint_timbre(self, selected):
        self.timbre_var.set(selected)
        for index, label in enumerate(self.timbre_labels):
            on = index == selected
            label.configure(bg="#17304a" if on else PANEL, fg=MINT if on else MUTED,
                            selectcolor="#17304a", highlightbackground=MINT if on else LINE)
        if hasattr(self, "wave_timbre"):
            self.wave_timbre.configure(text=TIMBRES[selected] if 0 <= selected < len(TIMBRES) else "未知音色")

    def _paint_tabs(self):
        for name, button in (("performance", self.performance_button), ("monitor", self.monitor_button)):
            on = self.view == name
            button.configure(bg=AMBER if on else PANEL_LIGHT, fg=SCREEN if on else TEXT)

    def set_view(self, view):
        self.view = view
        self._paint_tabs()
        self._update_screen()

    def _update_screen(self):
        active = [i for i in range(7) if self.display_touch & (1 << i)]
        if self.view == "performance":
            if not active:
                self.screen_main.configure(text="--")
                self.screen_sub.configure(text="无按键")
            elif len(active) == 1:
                index = active[0]
                self.screen_main.configure(text=f"{KEY_NAMES[index]}   {KEY_PITCHES[index][0]}{3 if self.timbre == 3 else 4}")
                self.screen_sub.configure(text="1 个音正在演奏")
            else:
                self.screen_main.configure(text=f"{len(active)} 音同时")
                self.screen_sub.configure(text="  +  ".join(KEY_NAMES[i] for i in active))
        else:
            self.screen_kicker.configure(text="实时监测")
            self.screen_main.configure(text=f"{len(active)} / 7  TOUCH")
            self.screen_sub.configure(text=f"A0  {self.pitch_percent * 100:5.1f}%     A1  {self.volume_percent * 100:5.1f}%")
        self.touch_count.configure(text=f"{len(active)} / 7")
        self._draw_activity()

    def _draw_activity(self):
        # Audio arrives from A, after the same mix/volume path feeding OLED I2S.
        if not hasattr(self, "_trace"):
            self._trace = None
            self._trace_time = 0.0
        self._render_audio_trace()
        if self._wave_job is None:
            self._wave_job = self.after(100, self._check_trace_age)

    def update_waveform(self, frame):
        self._trace = frame
        self._trace_time = time.monotonic()
        self._draw_activity()

    def _render_audio_trace(self):
        canvas = self.activity
        width, height = canvas.winfo_width(), canvas.winfo_height()
        if width < 20 or height < 10:
            return
        trace = getattr(self, "_trace", None)
        fresh = bool(trace and time.monotonic()-self._trace_time < .6 and trace["online"])
        render_key = (id(trace), fresh, width, height)
        if getattr(self, "_trace_render_key", None) == render_key:
            return
        self._trace_render_key = render_key
        canvas.delete("all")
        mid = height*.5
        for x in range(0, width, max(1, width//8)):
            canvas.create_line(x, 4, x, height-4, fill="#24223a")
        for y in (height*.25, mid, height*.75):
            canvas.create_line(0, y, width, y, fill="#24223a")
        if not fresh:
            canvas.create_line(0, mid, width, mid, fill=MUTED)
            self.screen_kicker.configure(text="实际音频波形 · 等待A板波形数据")
            return
        values = trace["samples"]
        peak = max((abs(v) for v in values), default=0)
        if trace["peak"] < 32 or peak == 0:
            canvas.create_line(0, mid, width, mid, fill=MINT, width=2)
        else:
            # Desktop-only AGC: fill 88% of the plot height without changing audio.
            gain = height*.44/peak
            coords = []
            for i, value in enumerate(values):
                coords.extend((i*(width-1)/(len(values)-1), mid-value*gain))
            canvas.create_line(*coords, fill="#163d53", width=6, joinstyle="round")
            canvas.create_line(*coords, fill=MINT, width=2, joinstyle="round")
        self.screen_kicker.configure(text="实际音频波形 · OLED同源 · 显示自动放大")

    def _check_trace_age(self):
        self._wave_job = None
        if self.winfo_exists():
            self._render_audio_trace()
            if self.winfo_ismapped():
                self._wave_job = self.after(100, self._check_trace_age)

    def _dispose_animation(self, event):
        if event.widget is self and self._wave_job is not None:
            self.after_cancel(self._wave_job)
            self._wave_job = None

    def _draw_decorations(self):
        """Draw quiet, non-interactive audio motifs around the compact keyboard."""
        for canvas, side in ((self.decor_left, "left"), (self.decor_right, "right")):
            canvas.delete("all")
            width = canvas.winfo_width()
            height = canvas.winfo_height()
            if width < 20 or height < 30:
                continue
            center = height * 0.48
            amplitude = min(16, height * 0.16)
            points = []
            for x in range(0, max(2, width), 3):
                phase = (x / max(1, width)) * 4.0 * math.pi
                points.extend((x, center + amplitude * math.sin(phase)))
            canvas.create_line(*points, fill=PURPLE, width=2, smooth=True)
            canvas.create_line(0, center, width, center, fill=LINE, dash=(2, 5))
            if side == "left":
                canvas.create_text(8, 16, text="S O U N D", anchor="w",
                                   fill=MUTED, font=("Consolas", 8, "bold"))
                canvas.create_text(8, height - 14, text="01 — 07", anchor="w",
                                   fill=MUTED, font=("Consolas", 8))
            else:
                canvas.create_text(width - 8, 16, text="P L A Y", anchor="e",
                                   fill=MINT, font=("Consolas", 8, "bold"))
                canvas.create_oval(width - 48, height - 22, width - 38, height - 12,
                                   fill=MINT, outline="")
                canvas.create_text(width - 31, height - 17, text="", anchor="w",
                                   fill=MUTED, font=("Consolas", 8))

    def _draw_keyboard(self):
        self.keyboard.delete("all")
        width = self.keyboard.winfo_width()
        height = self.keyboard.winfo_height()
        if width < 100 or height < 80:
            return
        key_width = width / 7
        for i, name in enumerate(KEY_NAMES):
            x0 = i * key_width + 2
            x1 = (i + 1) * key_width - 2
            active = bool(self.display_touch & (1 << i))
            face = WHITE_ACTIVE if active else WHITE_KEY
            self.keyboard.create_rectangle(x0 + 3, 3, x1 + 3, height - 5,
                                           fill="#050910", outline="")
            self.keyboard.create_rectangle(x0, 0, x1, height - 10,
                                           fill=face, outline=MINT if active else "#acbbd0", width=1)
            self.keyboard.create_rectangle(x0 + 4, 3, x1 - 4, 8,
                                           fill="#158b9e" if active else "#fafcff", outline="")
            self.keyboard.create_text((x0 + x1) / 2, height - 50,
                                      text=name, font=("Microsoft YaHei UI", 15, "bold"),
                                      fill="#e2ffff" if active else "#28384c")
            self.keyboard.create_text((x0 + x1) / 2, height - 30,
                                      text=KEY_PITCHES[i], font=("Consolas", 10),
                                      fill="#a4f5fa" if active else "#607187")
        # Decorative sharps for the C-major seven-key layout. No touch action.
        black_height = min(height * 0.55, height - 78)
        for boundary in (1, 2, 4, 5, 6):
            x = boundary * key_width
            half = key_width * 0.26
            self.keyboard.create_rectangle(x - half + 3, 0, x + half + 3, black_height + 5,
                                           fill="#030711", outline="")
            self.keyboard.create_rectangle(x - half, 0, x + half, black_height,
                                           fill="#101929", outline="#36445c", width=1)
            self.keyboard.create_rectangle(x - half + 6, 8, x + half - 6, max(12, black_height - 10),
                                           fill="#202d43", outline="")

    def update_state(self, data, touch):
        self.display_touch = touch
        self.pitch_percent = min(max(data["pitch"] / 26400, 0.0), 1.0)
        self.volume_percent = min(max(data["volume"] / 26400, 0.0), 1.0)
        self.pitch_value.configure(text=f"{self.pitch_percent * 100:5.1f}%")
        self.volume_value.configure(text=f"{self.volume_percent * 100:5.1f}%")
        self._draw_meter(self.pitch_meter, MINT)
        self._draw_meter(self.volume_meter, AMBER)
        self.timbre = data["timbre"]
        self._paint_timbre(self.timbre)
        self.mpr_label.configure(text=f"●  MPR121  {'在线' if data['mpr'] else '离线'}",
                                 fg=MINT if data["mpr"] else RED)
        self.ads_label.configure(text=f"●  ADS1115  {'在线' if data['ads'] else '离线'}",
                                 fg=MINT if data["ads"] else RED)
        if data.get("extended"):
            links = data["links"]
            self.link_label.configure(text=f"B {'正常' if links & 1 else '断开'}  /  C {'正常' if links & 2 else '断开'}",
                                      fg=MINT if links == 3 else RED)
            if 'audio_frames' in data:
                self.audio_diagnostic_label.configure(text=(
                    f"累计音频帧 {data['audio_frames']}    失败 B {data['audio_bad_b']} / C {data['audio_bad_c']}\n"
                    f"CRC B {data['audio_crc_b']} / C {data['audio_crc_c']}    "
                    f"帧号 B {data['audio_sequence_b']} / C {data['audio_sequence_c']}\n"
                    f"版本 B {data['audio_version_b']} / C {data['audio_version_c']}"))
            for i, var in enumerate(self.feature_vars):
                var.set((data["features"] >> i) & 1)
            gestures = {1: "右", 2: "左", 4: "上", 8: "下", 16: "前", 32: "后",
                        64: "顺时针", 128: "逆时针"}
            enc = data.get("encoder_status", 0)
            enc_state = "转动" if (enc & 0x8000) else "静止"
            enc_dir = "CW" if (enc & 0x4000) else "CCW"
            effect = "开" if data["features"] & 2 else "关"
            self.distance_label.configure(text=f"编码器 {enc_state} 深度{enc & 0x3fff} {enc_dir} 颤音{effect} / "
                f"手势 {gestures.get(data['gesture'], '--')}")
            self.aux_diagnostic_label.configure(text=format_aux_diagnostic(data))
            states = {0: "空闲", 1: "初始化", 2: "擦除中", 3: "录制中", 4: "重演中",
                      5: "保存参数中", 6: "停止收尾中", 15: "不可用"}
            text = states.get(data["store_status"], "忙碌")
            if data["store_status"] == 0 and data["store_flags"] & 4:
                text = "可录制"
            if data["store_flags"] & 8:
                reasons = {1: "芯片识别失败", 2: "写入读回校验失败",
                           3: "录制索引提交失败", 4: "录制缓存溢出",
                           5: "SPI操作超时", 6: "录制区未准备",
                           7: "没有可重演记录", 8: "重演数据校验失败"}
                text = "存储故障：" + reasons.get(data.get("store_fault_code", 0), "旧版无诊断码")
            self.store_label.configure(text=text, fg=RED if data["store_flags"] & 8 else MUTED)
            if hasattr(self, "last_storage"):
                self.last_storage = (data["store_status"], data["store_flags"])
                self._apply_storage_controls()
            values = [str(v) if data["pressure_valid"] & (1 << i) else "--"
                      for i, v in enumerate(data["pressure"])]
            self.pressure_label.configure(text="压力 ADC：" + "    ".join(
                f"{name} {v}" for name, v in zip(("升音片", "降音片", "预留2", "预留3", "预留4", "预留5", "预留6"), values)))
        self._update_screen()
        self._draw_keyboard()

    def reset_touch(self):
        self._trace = None
        self._trace_time = 0.0
        self.display_touch = 0
        self._update_screen()
        self._draw_keyboard()

    def set_commands_enabled(self, enabled):
        self.controls_enabled = enabled
        for control in self.command_controls:
            control.configure(state="normal" if enabled else "disabled")
        self._apply_storage_controls()

    def _apply_storage_controls(self):
        state, flags = self.last_storage
        idle = state == 0
        allowed = {0x10: idle, 0x11: idle and bool(flags & 4),
                   0x12: state != 15, 0x13: idle and not bool(flags & 12),
                   0x14: idle}
        for opcode, control in self.storage_controls.items():
            control.configure(state="normal" if self.controls_enabled and allowed.get(opcode, True)
                              else "disabled")

    def toggle_feature(self, index):
        self.on_command(3, (1 << (8+index)) | (self.feature_vars[index].get() << index))
