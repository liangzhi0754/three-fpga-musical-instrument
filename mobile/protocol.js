/* Shared by the shipped page and Node tests; no dependencies. */
(function (root) {
  'use strict';
  const TIMBRES = ['正弦', '锯齿', '方波', '大提琴32', '空灵竹笛32'];
  const LENGTHS = {0x55:12, 0x56:38, 0x57:74, 0x58:88, 0x59:108};
  const STORES = {0:'空闲', 1:'初始化', 2:'擦除中', 3:'录制中', 4:'重演中', 5:'保存参数中', 6:'停止收尾中', 15:'不可用'};
  const FAULTS = {1:'芯片识别失败', 2:'写入读回校验失败', 3:'录制索引提交失败', 4:'录制缓存溢出', 5:'SPI操作超时', 6:'录制区未准备', 7:'没有可重演记录', 8:'重演数据校验失败'};
  const COUNTERS = ['audio_frames', 'audio_bad_b', 'audio_bad_c', 'audio_crc_b', 'audio_crc_c', 'audio_sequence_b', 'audio_sequence_c', 'audio_version_b', 'audio_version_c'];
  const u16 = (f, i) => f[i] | f[i+1] << 8;
  function decode(f) {
    const d = {frame_type:f[1], sequence:f[2], extended:f.length !== 12};
    if (!d.extended) return Object.assign(d, {touch:f[3]&127, pitch:u16(f,4), volume:u16(f,6), mpr:!!(f[8]&1), ads:!!(f[8]&2), adc_valid:!!(f[8]&4), volume_valid:!!(f[8]&8), timbre:f[9]&3});
    if (f[3] !== 1) return null;
    Object.assign(d, {touch:f[4]&127, timbre:f[5]&7, pitch:u16(f,6), volume:u16(f,8),
      mpr:!!(f[10]&1), ads:!!(f[10]&2), adc_valid:!!(f[10]&4), volume_valid:!!(f[10]&8),
      features:f[11]&7, ads_online:f[12]&7, aux_online:f[13]&3, links:f[14]&3,
      store_status:f[15]&15, store_fault_code:f[15]>>>4, store_flags:f[16], command_sequence:f[17],
      encoder_status:u16(f,18), encoder_active:!!(f[19]&128), encoder_direction:!!(f[19]&64), encoder_depth:u16(f,18)&0x3fff,
      gesture:f[20], pressure_valid:f[21]&127, pressure:Array.from({length:7}, (_,i)=>u16(f,22+i*2))});
    if (f[12]&128) d.encoder_diagnostic = {raw_a:!!(f[10]&32), raw_b:!!(f[10]&16), seen_a:!!(f[10]&128), seen_b:!!(f[10]&64), filtered_a:!!(f[12]&16), filtered_b:!!(f[12]&8), legal_seen:!!(f[12]&32), illegal_seen:!!(f[12]&64), count:f[13]>>>2};
    if (f.length >= 74) COUNTERS.forEach((name,i)=>{ const j=36+i*4; d[name]=(f[j]+f[j+1]*256+f[j+2]*65536+f[j+3]*16777216)>>>0; });
    if (f.length >= 88) {
      const r=f.subarray(72,86);
      d.aux_diagnostic = {pc:r[0]|((r[1]&1)<<8), state:(r[1]>>>1)&7, busy:!!(r[1]&16), scl:!!(r[1]&32), sda:!!(r[1]&64), valid:!!(r[1]&128), error:r[2], fail_pc:r[3]|((r[4]&1)<<8), chip:(r[4]>>>1)&1, fail_reg:r[5], model_id:r[6], fail_read:r[7], range_status:r[8], attempts:r[9], ranges:r[10], transactions:r[11], last_reg:r[12], bus_fault:r[13]&7};
    }
    if (f.length === 108) {
      const r=f.subarray(86,106);
      d.aux_probe={phase:r[0], flags:r[1], rounds:r[2], ack_count:r[3], addresses:[]};
      for (let i=8;i<120;i++) if(r[4+(i>>>3)]&(1<<(i&7))) d.aux_probe.addresses.push(i);
    }
    return d;
  }
  class FrameParser {
    constructor() { this.reset(); }
    reset() { this.buf=new Uint8Array(0); this.bad=0; }
    feed(data) {
      const chunk=data instanceof DataView ? new Uint8Array(data.buffer,data.byteOffset,data.byteLength) : new Uint8Array(data);
      const merged=new Uint8Array(this.buf.length+chunk.length);
      merged.set(this.buf); merged.set(chunk,this.buf.length);
      let offset=0; const result=[];
      while(offset<merged.length) {
        if(merged[offset]!==0xaa) { offset++; continue; }
        if(merged.length-offset<2) break;
        const size=LENGTHS[merged[offset+1]];
        if(!size) { offset++; continue; }
        if(merged.length-offset<size) break;
        const f=merged.subarray(offset,offset+size);
        let sum=0; for(let i=2;i<size-2;i++) sum=(sum+f[i])&255;
        if(f[size-1]!==13 || f[size-2]!==sum) { this.bad++; offset++; continue; }
        offset+=size;
        const decoded=decode(f); if(decoded) result.push(decoded);
      }
      this.buf=merged.slice(offset); // A partial frame is at most 107 bytes.
      return result;
    }
  }
  function commandPacket(sequence, opcode, argument=0) {
    const b=Uint8Array.of(0x43,0x4d,sequence&255,opcode&255,argument&255,(argument>>>8)&255,0,13);
    b[6]=(b[2]+b[3]+b[4]+b[5])&255; return b;
  }
  function storageText(d) {
    if(!d.extended) return '未提供';
    if(d.store_flags&8) return '存储故障：'+(d.store_fault_code ? (FAULTS[d.store_fault_code] || `未知故障码 ${d.store_fault_code}`) : '设备未提供故障码（手机串口）');
    return d.store_status===0 && d.store_flags&4 ? '可录制' : (STORES[d.store_status] || `未知状态 ${d.store_status}`);
  }
  function storageAllowed(d) {
    if(!d || !d.extended) return {};
    const idle=d.store_status===0;
    return {0x10:idle, 0x11:idle&&!!(d.store_flags&4), 0x12:d.store_status!==15, 0x13:idle&&!(d.store_flags&12), 0x14:idle};
  }
  function validateScore(data) {
    if(!data || typeof data!=='object') throw Error('曲谱必须是 JSON 对象');
    const notes=Array.isArray(data.notes) ? data.notes : Array.isArray(data.events) ? data.events.map(e=>e && e.keys) : null;
    if(!notes || !notes.length || notes.length>10000) throw Error('需要 1–10000 拍 notes 或 events');
    if(notes.some(keys=>!Array.isArray(keys)||keys.some(i=>!Number.isInteger(i)||i<0||i>6))) throw Error('每拍必须是键号 0–6 的数组；空数组表示休止');
    return {title:String(data.title || '本地曲谱').slice(0,100), bpm:Math.max(40,Math.min(240,Number(data.bpm)||100)), notes:notes.map(keys=>[...new Set(keys)])};
  }
  const api={TIMBRES,LENGTHS,STORES,FAULTS,COUNTERS,FrameParser,commandPacket,storageText,storageAllowed,validateScore};
  if(typeof module==='object' && module.exports) module.exports=api;
  else root.InstrumentProtocol=api;
})(typeof globalThis!=='undefined' ? globalThis : this);
