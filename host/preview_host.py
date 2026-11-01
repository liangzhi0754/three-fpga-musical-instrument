"""Open an isolated UI preview without connecting to serial hardware."""
from pathlib import Path
import tkinter as tk
import ctypes
from ctypes import wintypes
from PIL import Image
from instrument_panel import InstrumentPanel

root = tk.Tk()
root.title("UI preview (simulation)")
root.geometry("1280x850+20+20")
panel = InstrumentPanel(root, lambda: None, lambda: None, lambda: None)
panel.pack(fill="both", expand=True)
data = dict(touch=21, pitch=13200, volume=20000, mpr=True, ads=True,
    adc_valid=True, volume_valid=True, timbre=0, extended=True, links=3,
    features=7, aux_online=3, distance=260, gesture=1, store_status=0,
    store_flags=2, pressure=[14000,0,18000,0,22000,0,0], pressure_valid=127,
    audio_frames=527343, audio_bad_b=0, audio_bad_c=25,
    audio_crc_b=0, audio_crc_c=24, audio_sequence_b=0, audio_sequence_c=1,
    audio_version_b=0, audio_version_c=0)
def capture():
    panel.update_state(data, 21)
    root.update_idletasks()
    folder = Path(__file__).resolve().parent.parent / "validation"
    folder.mkdir(exist_ok=True)
    # Capture only this application's client area, even when it is obscured.
    user = ctypes.WinDLL("user32", use_last_error=True)
    gdi = ctypes.WinDLL("gdi32", use_last_error=True)
    user.GetDC.restype = wintypes.HDC
    gdi.CreateCompatibleDC.restype = wintypes.HDC
    gdi.CreateCompatibleBitmap.restype = wintypes.HBITMAP
    gdi.SelectObject.restype = wintypes.HANDLE
    user.GetDC.argtypes = [wintypes.HWND]
    user.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
    user.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
    gdi.CreateCompatibleDC.argtypes = [wintypes.HDC]
    gdi.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
    gdi.SelectObject.argtypes = [wintypes.HDC, wintypes.HANDLE]
    gdi.DeleteObject.argtypes = [wintypes.HANDLE]
    gdi.DeleteDC.argtypes = [wintypes.HDC]
    gdi.GetDIBits.argtypes = [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT,
                            wintypes.UINT, ctypes.c_void_p, ctypes.c_void_p, wintypes.UINT]
    hwnd = root.winfo_id()
    width, height = root.winfo_width(), root.winfo_height()
    dc = user.GetDC(hwnd)
    memory = gdi.CreateCompatibleDC(dc)
    bitmap = gdi.CreateCompatibleBitmap(dc, width, height)
    old = gdi.SelectObject(memory, bitmap)
    class Header(ctypes.Structure):
        _fields_ = [("size", wintypes.DWORD), ("width", wintypes.LONG),
                    ("height", wintypes.LONG), ("planes", wintypes.WORD),
                    ("bits", wintypes.WORD), ("compression", wintypes.DWORD),
                    ("image_size", wintypes.DWORD), ("xp", wintypes.LONG),
                    ("yp", wintypes.LONG), ("used", wintypes.DWORD),
                    ("important", wintypes.DWORD)]
    header = Header(40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
    try:
        if not user.PrintWindow(hwnd, memory, 1):
            raise RuntimeError("PrintWindow failed; no desktop fallback")
        pixels = ctypes.create_string_buffer(width * height * 4)
        if not gdi.GetDIBits(memory, bitmap, 0, height, pixels,
                            ctypes.byref(header), 0):
            raise RuntimeError("GetDIBits failed")
        Image.frombuffer("RGB", (width, height), pixels.raw,
                         "raw", "BGRX", 0, 1).save(folder / "host_preview.png")
    finally:
        gdi.SelectObject(memory, old)
        gdi.DeleteObject(bitmap)
        gdi.DeleteDC(memory)
        user.ReleaseDC(hwnd, dc)
    print("Preview saved; keyboard size:", panel.keyboard.winfo_width(), panel.keyboard.winfo_height())
    root.destroy()
root.after(800, capture)
root.mainloop()
