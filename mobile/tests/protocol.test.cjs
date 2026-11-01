'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const path=require('node:path');
const P=require('../protocol.js');
function seal(f){let sum=0;for(let i=2;i<f.length-2;i++) sum=(sum+f[i])&255;f[f.length-2]=sum;f[f.length-1]=13;return f;}
function frame(type=0x59){
  const f=new Uint8Array(P.LENGTHS[type]);f[0]=0xaa;f[1]=type;f[2]=231;f[3]=1;
  if(type===0x55){f[3]=0x45;f[4]=0x34;f[5]=0x12;f[6]=0x78;f[7]=0x56;f[8]=15;f[9]=3;return seal(f);}
  f[4]=0x7f;f[5]=0xfc;f[6]=0x34;f[7]=0x12;f[8]=0x78;f[9]=0x56;
  f[10]=15;f[11]=7;f[12]=7;f[13]=2;f[14]=3;f[15]=6;f[16]=1;f[17]=254;
  f[18]=0x45;f[19]=0xe3;f[20]=128;f[21]=0x43;
  for(let i=0;i<7;i++){f[22+i*2]=i+1;f[23+i*2]=i+2;}
  if(f.length>=74) for(let i=0;i<9;i++) f.set([i+1,0x22,0x33,0xf4],36+i*4);
  if(f.length>=88) f.set([0x23,0xff,5,0x45,3,0x70,0xee,8,9,10,11,12,0x33,6],72);
  if(f.length===108){f.set([3,5,7,2],86);f[90+(0x29>>>3)]|=1<<(0x29&7);f[90+(0x39>>>3)]|=1<<(0x39&7);}
  return seal(f);
}
test('AA59 flute low three bits, all seven gates and little endian fields',()=>{
  const d=new P.FrameParser().feed(frame())[0];
  assert.equal(d.timbre,4);assert.equal(P.TIMBRES[d.timbre],'空灵竹笛32');assert.equal(d.touch,127);
  assert.equal(d.pitch,0x1234);assert.equal(d.volume,0x5678);assert.equal(d.command_sequence,254);
  assert.deepEqual(d.pressure,[513,770,1027,1284,1541,1798,2055]);assert.equal(d.pressure_valid,67);
});
test('AA59 every split boundary including header and checksum',()=>{
  const f=frame();for(let n=1;n<f.length;n++){const p=new P.FrameParser();assert.equal(p.feed(f.slice(0,n)).length,0);assert.equal(p.feed(f.slice(n))[0].timbre,4);assert.equal(p.buf.length,0);}
});
test('one-byte and BLE MTU 20/97/180 chunks, concatenated frames',()=>{
  const f=Buffer.concat([frame(),frame(),frame()]);
  for(const size of [1,20,97,180]){const p=new P.FrameParser();let out=[];for(let i=0;i<f.length;i+=size)out.push(...p.feed(f.subarray(i,i+size)));assert.equal(out.length,3);}
});
test('noise, false headers, invalid checksum and invalid CR resynchronize',()=>{
  const crc=frame();crc[6]^=1;const cr=frame();cr[107]=0;
  const p=new P.FrameParser();const result=p.feed(Buffer.concat([Buffer.from([4,13,0xaa,0x12]),crc,cr,frame()]));
  assert.equal(result.length,1);assert.ok(p.bad>=2);
});
test('DataView honors offset and length, no unrelated buffer bytes',()=>{
  const f=frame();const backing=new Uint8Array(130);backing.fill(255);backing.set(f,7);
  assert.equal(new P.FrameParser().feed(new DataView(backing.buffer,7,108))[0].timbre,4);
});
test('all AA55/56/57/58/59 lengths with version gating',()=>{
  for(const type of [0x55,0x56,0x57,0x58,0x59]){const p=new P.FrameParser();const f=frame(type);assert.equal(p.feed(f)[0].extended,type!==0x55);if(type!==0x55){f[3]=2;assert.equal(p.feed(seal(f)).length,0);}}
  const d=new P.FrameParser().feed(frame(0x55))[0];assert.equal(d.touch,0x45);assert.equal(d.pitch,0x1234);assert.equal(d.timbre,3);assert.equal(d.features,undefined);
});
test('reset discards partial data across connections and buffer stays bounded',()=>{
  const p=new P.FrameParser();p.feed(frame().slice(0,40));p.reset();assert.equal(p.feed(frame()).length,1);
  p.feed(new Uint8Array(500000).fill(0xaa));assert.ok(p.buf.length<=107);
});
test('encoder motion/direction/depth and sensor bits match host',()=>{
  const d=new P.FrameParser().feed(frame())[0];assert.equal(d.encoder_active,true);assert.equal(d.encoder_direction,true);assert.equal(d.encoder_depth,0x2345);assert.equal(d.ads_online,7);assert.equal(d.aux_online,2);assert.equal(d.adc_valid,true);assert.equal(d.volume_valid,true);assert.equal(d.gesture,128);
});
test('optional PC encoder diagnostics mask high bits correctly',()=>{
  const f=frame();f[10]=0xff;f[12]=0xff;f[13]=0xff;
  const d=new P.FrameParser().feed(seal(f))[0];assert.equal(d.ads_online,7);assert.equal(d.aux_online,3);assert.equal(d.encoder_diagnostic.count,63);assert.equal(d.encoder_diagnostic.illegal_seen,true);
});
test('unsigned 32-bit audio counters, auxiliary and I2C address probes',()=>{
  const d=new P.FrameParser().feed(frame())[0];assert.equal(d.audio_frames,0xf4332201);assert.equal(d.audio_version_c,0xf4332209);assert.equal(d.aux_diagnostic.pc,0x123);assert.equal(d.aux_diagnostic.fail_pc,0x145);assert.equal(d.aux_diagnostic.bus_fault,6);assert.deepEqual(d.aux_probe.addresses,[0x29,0x39]);
});
test('ID4 command exact wire bytes and wrapping checksum',()=>{
  assert.deepEqual([...P.commandPacket(1,1,4)],[0x43,0x4d,1,1,4,0,6,13]);
  assert.deepEqual([...P.commandPacket(255,3,0x407)],[0x43,0x4d,255,3,7,4,13,13]);
});
test('status6 finishing blocks start/play/save; stop remains available',()=>{
  const d=new P.FrameParser().feed(frame())[0];assert.equal(P.storageText(d),'停止收尾中');assert.deepEqual(P.storageAllowed(d),{16:false,17:false,18:true,19:false,20:false});
});
test('idle prepared/record/replay control rules and unavailable state',()=>{
  const d={extended:true,store_status:0,store_flags:4};assert.equal(P.storageText(d),'可录制');assert.equal(P.storageAllowed(d)[17],true);assert.equal(P.storageAllowed(d)[19],false);d.store_flags=0;assert.equal(P.storageAllowed(d)[19],true);d.store_status=15;assert.equal(P.storageAllowed(d)[18],false);
});
test('all eight fault codes plus missing phone code and unknown code',()=>{
  for(let code=0;code<=9;code++){const f=frame();f[15]=(code<<4)|6;f[16]=8;const d=new P.FrameParser().feed(seal(f))[0];assert.equal(d.store_status,6);assert.equal(d.store_fault_code,code);assert.match(P.storageText(d),code===0?/未提供故障码/:code===9?/未知故障码 9/:new RegExp(P.FAULTS[code]));}
});
test('local scores accept notes/events, rests, chords and validate keys',()=>{
  assert.deepEqual(P.validateScore({notes:[[0,0,4],[]]}).notes,[[0,4],[]]);assert.deepEqual(P.validateScore({events:[{keys:[6]}],bpm:999}).notes,[[6]]);
  for(const data of [{},null,{notes:[[7]]},{notes:[[-1]]},{notes:[[1.5]]},{notes:['bad']},{events:[null]}])assert.throws(()=>P.validateScore(data));
});
test('same AA59 fixture matches latest Python host decoding and command',()=>{
  const source="import sys,json\nsys.path.insert(0,sys.argv[1])\nfrom three_board_protocol import FrameParser,command_packet\np=FrameParser()\nprint(json.dumps({'frame':p.feed(bytes.fromhex(sys.argv[2]))[0], 'command':list(command_packet(1,1,4))}))";
  const result=spawnSync('python',['-B','-c',source,path.resolve(__dirname,'../../host'),Buffer.from(frame()).toString('hex')],{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);const host=JSON.parse(result.stdout);const js=new P.FrameParser().feed(frame())[0];
  for(const [key,value] of Object.entries(host.frame)) if(key!=='distance')assert.deepEqual(js[key],value,key);
  assert.deepEqual([...P.commandPacket(1,1,4)],host.command);
});
module.exports={frame,seal};
