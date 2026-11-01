"""Check plot extent, signal shape, stale clearing, and timer cleanup offline."""
from pathlib import Path
import sys
import math
import time
import tkinter as tk

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'host'))
from instrument_panel import InstrumentPanel

root=tk.Tk()
root.geometry('1280x920')
panel=InstrumentPanel(root,lambda:None,lambda:None,lambda:None)
panel.pack(fill='both',expand=True)
errors=[]
root.report_callback_exception=lambda *args: errors.append(str(args))
root.update()
values=[round(100*math.sin(i*math.tau/32)) for i in range(128)]
frame=dict(samples=values,peak=1000,online=True)
panel.update_waveform(frame)
lines=panel.activity.find_all()
coords=panel.activity.coords(lines[-1])
height=panel.activity.winfo_height()
assert abs((max(coords[1::2])-min(coords[1::2]))/height-.88)<.01
assert len(coords)==256
assert abs(coords[1]-height*.5)<.01
panel._trace_time=time.monotonic()-1
panel._check_trace_age()
assert len(panel.activity.coords(panel.activity.find_all()[-1]))==4
panel.update_waveform(dict(samples=[0]*128,peak=0,online=True))
coords=panel.activity.coords(panel.activity.find_all()[-1])
assert coords[1]==coords[3]
panel.reset_touch()
assert panel._trace is None
panel.destroy()
root.update()
assert panel._wave_job is None and not errors
root.destroy()
print('PASS real-trace shape, 88% amplitude, silence, stale data and cleanup')
