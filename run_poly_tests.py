from pathlib import Path
import subprocess
import json
import numpy as np

r=Path(__file__).resolve().parent
iv=Path('E:/qiansai/tmp/iverilog_portable_v9/bin/iverilog.exe')
out=r/'validation/poly_strings.vvp'
p=subprocess.run([str(iv),'-g2005','-s','tb_poly_strings','-o',str(out),
 'sim/tb_poly_strings.v','src/common/poly_string_bank.v','src/common/synth_waveform.v'],
 cwd=r,capture_output=True,text=True)
log=p.stdout+p.stderr
if p.returncode==0:
 p=subprocess.run([str(iv.with_name('vvp.exe')),str(out)],cwd=r,
                  capture_output=True,text=True,timeout=900)
 log+=p.stdout+p.stderr
(r/'validation/poly_strings.log').write_text(log)
print(log,flush=True)
if p.returncode or 'PASS' not in log:raise SystemExit(1)
results={}
for name,octave in [('cello',0.5),('flute',1.0)]:
 x=np.loadtxt(r/f'validation/{name}_chord.txt')
 # 3072 samples give 17.17Hz bins: disjoint bins for C3/E3/G3 too.
 y=x[-3072:];spectrum=np.abs(np.fft.rfft(y*np.hanning(len(y))))
 fs=27000000/512
 peaks=[]
 for base in (21308210,26846653,31926153):
  frequency=base*octave*fs/(2**32)
  center=int(round(frequency*len(y)/fs))
  local=spectrum[center]
  assert local>spectrum.max()*0.30,(name,frequency,local,spectrum.max())
  peaks.append(dict(hz=frequency,strength=float(local/spectrum.max())))
 assert np.max(np.abs(x))<32767,(name,'clipping')
 results[name]=dict(peaks=peaks,peak_sample=float(np.max(np.abs(x))),rms=float(np.sqrt(np.mean(y*y))))
a=np.loadtxt(r/'validation/cello_chord.txt')[-2048:]
b=np.loadtxt(r/'validation/flute_chord.txt')[-2048:]
assert abs(np.corrcoef(a,b)[0,1])<0.95,'instruments not distinct'
(r/'validation/poly_numeric.json').write_text(json.dumps(results,indent=2))
for octave in (0.5, 1.0):
 frequencies=np.array((21308210,26846653,31926153))*octave*fs/(2**32)
 bins=np.rint(frequencies*3072/fs).astype(int)
 time=np.arange(3072)/fs
 for missing in range(3):
  fixture=sum(np.sin(2*np.pi*hz*time) for i,hz in enumerate(frequencies) if i!=missing)
  fft=np.abs(np.fft.rfft(fixture*np.hanning(3072)))
  assert fft[bins[missing]]<fft.max()*0.30,('missing-note false positive',octave,missing)
print('PASS HDL audio: Do/Mi/Sol disjoint center bins, missing-note negative controls, no clipping, distinct waveforms',flush=True)
