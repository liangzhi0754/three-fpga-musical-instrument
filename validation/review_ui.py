"""Offline layout verification and capture; never imports or opens a serial port."""
import ast
import ctypes
from ctypes import wintypes
import json
import sys
from pathlib import Path
import tkinter as tk
import time
import math
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'host'))
from instrument_panel import InstrumentPanel, BG

root = tk.Tk()
root.title('霓虹界面预览 · 模拟数据')
root.geometry('1280x920+20+20')
panel = InstrumentPanel(root, lambda: None, lambda: None, lambda: None)
panel.pack(fill='both', expand=True)
tk.Checkbutton(panel.mode_row, text='电脑仅监视（关闭电脑控制）', bg=BG).pack(side='left')
panel.port_combo.set('COM11')
fixture = dict(touch=21, pitch=13200, volume=18000, mpr=True, ads=True,
    adc_valid=True, volume_valid=True, timbre=4, extended=True, links=3,
    features=7, encoder_status=0, gesture=1, store_status=0, store_flags=4,
    pressure=[0]*7, pressure_valid=3, audio_frames=527343, audio_bad_b=0,
    audio_bad_c=0, audio_crc_b=0, audio_crc_c=0, audio_sequence_b=0,
    audio_sequence_c=0, audio_version_b=0, audio_version_c=0,
    encoder_diagnostic=dict(raw_a=1,raw_b=1,seen_a=True,seen_b=True,
        count=12,legal_seen=True,illegal_seen=False))
panel.update_state(fixture, 21)
panel.set_commands_enabled(True)
panel.command_label.configure(text='预览使用模拟数据，未连接硬件')

def capture(name):
    root.update()
    user = ctypes.WinDLL('user32', use_last_error=True)
    gdi = ctypes.WinDLL('gdi32', use_last_error=True)
    user.GetParent.argtypes = [wintypes.HWND]
    user.GetParent.restype = wintypes.HWND
    user.GetDC.argtypes = [wintypes.HWND]
    user.GetDC.restype = wintypes.HDC
    user.ReleaseDC.argtypes = [wintypes.HWND,wintypes.HDC]
    user.PrintWindow.argtypes = [wintypes.HWND,wintypes.HDC,wintypes.UINT]
    gdi.CreateCompatibleDC.argtypes = [wintypes.HDC]
    gdi.CreateCompatibleDC.restype = wintypes.HDC
    gdi.CreateCompatibleBitmap.argtypes = [wintypes.HDC,ctypes.c_int,ctypes.c_int]
    gdi.CreateCompatibleBitmap.restype = wintypes.HBITMAP
    gdi.SelectObject.argtypes = [wintypes.HDC,wintypes.HANDLE]
    gdi.SelectObject.restype = wintypes.HANDLE
    gdi.GetDIBits.argtypes = [wintypes.HDC,wintypes.HBITMAP,wintypes.UINT,wintypes.UINT,
                            ctypes.c_void_p,ctypes.c_void_p,wintypes.UINT]
    gdi.DeleteObject.argtypes = [wintypes.HANDLE]
    gdi.DeleteDC.argtypes = [wintypes.HDC]
    hwnd = user.GetParent(root.winfo_id())
    width,height=root.winfo_width(),root.winfo_height()
    dc=user.GetDC(hwnd);mem=gdi.CreateCompatibleDC(dc)
    bmp=gdi.CreateCompatibleBitmap(dc,width,height);old=gdi.SelectObject(mem,bmp)
    class Header(ctypes.Structure):
        _fields_=[('size',wintypes.DWORD),('width',wintypes.LONG),('height',wintypes.LONG),
          ('planes',wintypes.WORD),('bits',wintypes.WORD),('compression',wintypes.DWORD),
          ('image_size',wintypes.DWORD),('xp',wintypes.LONG),('yp',wintypes.LONG),
          ('used',wintypes.DWORD),('important',wintypes.DWORD)]
    head=Header(40,width,-height,1,32,0,0,0,0,0,0)
    try:
        assert user.PrintWindow(hwnd,mem,3),'PrintWindow failed'
        pixels=ctypes.create_string_buffer(width*height*4)
        assert gdi.GetDIBits(mem,bmp,0,height,pixels,ctypes.byref(head),0)
        Image.frombuffer('RGB',(width,height),pixels.raw,'raw','BGRX',0,1).save(ROOT/'validation'/name)
    finally:
        gdi.SelectObject(mem,old);gdi.DeleteObject(bmp);gdi.DeleteDC(mem);user.ReleaseDC(hwnd,dc)

def check():
    result=[]
    for w,h in ((1280,920),(1080,780),(1600,900)):
        root.geometry(f'{w}x{h}+20+20');root.update()
        for tab in range(2):
            panel.details_notebook.select(tab);root.update()
            widgets=[*panel.command_controls,panel.keyboard,panel.screen_main]
            for widget in widgets:
                if widget.winfo_ismapped():
                    assert widget.winfo_width()>5 and widget.winfo_height()>5,str(widget)
                    assert widget.winfo_rootx()+widget.winfo_width()<=root.winfo_rootx()+w+2,str(widget)
                    assert widget.winfo_rooty()+widget.winfo_height()<=root.winfo_rooty()+h+2,str(widget)
            ratio=panel.keyboard.winfo_width()/w
            assert .74<ratio<.81,ratio
            print('layout', w,h,tab,'root',root.winfo_height(),'keyboard',panel.keyboard.winfo_height(),
                  'notebook',panel.details_notebook.winfo_height(),flush=True)
            assert panel.keyboard.winfo_height()>=100,panel.keyboard.winfo_height()
            for control in panel.command_controls:
                if control.winfo_ismapped():
                    parent = control.master
                    assert control.winfo_y()+control.winfo_height() <= parent.winfo_height()+1, str(control)
            result.append(dict(width=w,height=h,tab=tab,keyboard_width=panel.keyboard.winfo_width(),
                keyboard_height=panel.keyboard.winfo_height(),keyboard_ratio=ratio))
    root.geometry('1280x920+20+20');panel.details_notebook.select(0);root.update()
    end = time.monotonic()+.7
    while time.monotonic()<end:
        panel.update_waveform(dict(online=True, peak=8192,
            samples=[round(100*math.sin(i*math.tau/36)) for i in range(128)]))
        root.update()
        time.sleep(.01)
    capture('performance_preview.png')
    panel.details_notebook.select(1);root.update();capture('diagnostics_preview.png')
    (ROOT/'validation/layout_results.json').write_text(json.dumps(result,indent=2))
    print('PASS six window/tab layouts, piano width and control bounds',flush=True)
    root.destroy()

def run():
    try:check()
    except BaseException:
        import traceback
        (ROOT/'validation/layout_error.txt').write_text(traceback.format_exc(),encoding='utf-8')
        root.destroy();raise
root.after(800,run)
root.mainloop()
