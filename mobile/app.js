/* Based on bluetooth_work_v1/mobile_deploy: same BLE service and CM commands. */
'use strict';
const P=InstrumentProtocol;
const SERVICE='6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const RX_WRITE='6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const TX_NOTIFY='6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const NOTES=['Do','Re','Mi','Fa','Sol','La','Si'];
const GESTURES={1:'右',2:'左',4:'上',8:'下',16:'前',32:'后',64:'顺时针',128:'逆时针'};
const SONGS={twinkle:{title:'小星星',notes:[[0],[0],[4],[4],[5],[5],[4],[3],[3],[2],[2],[1],[1],[0]]},ode:{title:'欢乐颂',notes:[[2],[2],[3],[4],[4],[3],[2],[1],[0],[0],[1],[2],[2],[1],[1]]}};
const $=id=>document.getElementById(id);
const parser=new P.FrameParser();
let device=null,rxChar=null,txChar=null,connecting=false,bleConnected=false,session=0;
let state=null,dataOnline=false,lastFrameAt=0,seq=0,features=0;
let frameCount=0,rateAt=performance.now(),simTimer=null,simState=null;
let remoteMask=0,gateTimer=null,scoreTimer=null,scoreIdx=0,scoreNotes=[],scoreBpm=100,scoreRunning=false;
let pendingCommands=[],pendingGate=null,writing=false;
const pointerNotes=new Map(),keyboardNotes=new Set();
const keyEls=NOTES.map((name,i)=>{
  const el=document.createElement('button'); el.className='key'; el.type='button';
  el.innerHTML=`<strong>${name}</strong><small>${i+1}</small>`;
  el.setAttribute('aria-label',`${name}，第 ${i+1} 键`);
  el.addEventListener('contextmenu',e=>e.preventDefault());
  $('piano').appendChild(el); return el;
});
const scoreEls=NOTES.map(()=>{const el=document.createElement('div');$('scorebar').appendChild(el);return el;});
function log(message){
  const el=$('log');
  el.textContent=(el.textContent+`[${new Date().toLocaleTimeString()}] ${message}\n`).split('\n').slice(-100).join('\n');
  el.scrollTop=el.scrollHeight;
}
function setPills(){
  $('blePill').textContent=simTimer?'模拟模式':bleConnected?'蓝牙已连接':'蓝牙未连接';
  $('blePill').classList.toggle('on',!!simTimer||bleConnected);
  $('dataPill').textContent=dataOnline?(simTimer?'模拟数据':'数据在线'):'数据离线';
  $('dataPill').classList.toggle('on',dataOnline);
  $('btnConnect').textContent=connecting?'连接中…':bleConnected?'断开蓝牙':'连接蓝牙';
  $('btnConnect').disabled=connecting||!!simTimer||!navigator.bluetooth||!window.isSecureContext;
  $('btnSim').disabled=connecting||bleConnected;
  updateControls();
}
function updateControls(){
  const ready=dataOnline&&(bleConnected||!!simTimer);
  document.querySelectorAll('.timbre').forEach(b=>b.disabled=!ready);
  document.querySelectorAll('.feat, [data-command]').forEach(b=>b.disabled=!ready||!state?.extended);
  const allowed=P.storageAllowed(state);
  document.querySelectorAll('[data-store]').forEach(b=>b.disabled=!ready||!allowed[Number(b.dataset.store)]);
  keyEls.forEach(el=>el.disabled=!ready);
}
function resetData(){
  parser.reset(); state=null; dataOnline=false; features=0; frameCount=0; rateAt=performance.now();
  ['stTimbre','stPitch','stVolume','stLinks','stSeq','stRate','stMpr','stAds','stAdsOnline','stAux'].forEach(id=>$(id).textContent='—');
  $('stStore').textContent='等待设备状态'; $('stStore').style.color='';
  $('stTouch').textContent='—'; $('stPoly').textContent='0 / 7 键';
  $('stEncoder').textContent='编码器：—'; $('stGesture').textContent='手势：—'; $('stPressure').textContent='压力 ADC：—';
  $('stAudio').textContent='音频链路：—'; $('stDiagnostic').textContent='辅助诊断：—'; $('stProbe').textContent='I²C 探测：—';
  $('stEncoderDiagnostic').textContent='编码器引脚诊断：未提供'; $('stBad').textContent='校验丢弃：0';
  keyEls.forEach(el=>el.classList.remove('active'));
  document.querySelectorAll('.timbre, .feat').forEach(b=>b.setAttribute('aria-pressed','false'));
}
async function connect(){
  if(connecting||bleConnected||simTimer) return;
  connecting=true;setPills();const epoch=++session;
  try{
    device=await navigator.bluetooth.requestDevice({filters:[{namePrefix:'FPGA-'}],optionalServices:[SERVICE]});
    device.addEventListener('gattserverdisconnected',onDisconnect);
    const server=await device.gatt.connect();
    const service=await server.getPrimaryService(SERVICE);
    const notify=await service.getCharacteristic(TX_NOTIFY);
    const write=await service.getCharacteristic(RX_WRITE);
    if(epoch!==session) return;
    resetData();txChar=notify;rxChar=write;
    txChar.addEventListener('characteristicvaluechanged',onNotify);
    await txChar.startNotifications();
    if(epoch!==session) return;
    bleConnected=true;log('蓝牙已连接，等待 FPGA 有效状态帧');
  }catch(e){
    log('连接失败：'+(e.message||e));
    cleanupConnection();
    if(device?.gatt.connected) device.gatt.disconnect();
  }finally{connecting=false;setPills();}
}
function cleanupConnection(){
  session++;bleConnected=false;connecting=false;
  if(txChar) txChar.removeEventListener('characteristicvaluechanged',onNotify);
  if(device) device.removeEventListener('gattserverdisconnected',onDisconnect);
  rxChar=null;txChar=null;pendingCommands=[];pendingGate=null;
  releaseAllRemote();resetData();setPills();
}
function onDisconnect(){cleanupConnection();log('蓝牙已断开，手机按键已释放');}
async function disconnect(){
  releaseAllRemote(); // Submit zero before disconnect; bridge also releases on disconnect.
  const oldDevice=device;
  cleanupConnection();
  if(oldDevice?.gatt.connected) oldDevice.gatt.disconnect();
  log('蓝牙已断开');
}
function onNotify(ev){
  for(const d of parser.feed(ev.target.value)) renderState(d);
  $('stBad').textContent=`校验丢弃：${parser.bad}`;
}
function renderState(d){
  state=d;features=d.extended?d.features:0;
  const keys=NOTES.filter((_,i)=>d.touch&(1<<i));
  keyEls.forEach((el,i)=>el.classList.toggle('active',!!(d.touch&(1<<i))));
  $('stTouch').textContent=keys.join(' + ')||'—';$('stPoly').textContent=`${keys.length} / 7 键`;
  $('stTimbre').textContent=P.TIMBRES[d.timbre]||`未知音色 ${d.timbre}`;
  $('stPitch').textContent=d.adc_valid?String(d.pitch):'无有效数据';
  $('stVolume').textContent=d.volume_valid?String(d.volume):'无有效数据';
  $('stMpr').textContent=d.mpr?'在线':'离线';$('stAds').textContent=d.ads?'在线':'离线';
  $('stStore').textContent=P.storageText(d);$('stStore').style.color=d.store_flags&8?'var(--bad)':'';
  $('stLinks').textContent=d.extended?`B ${d.links&1?'正常':'断开'} / C ${d.links&2?'正常':'断开'}`:'未提供';
  $('stSeq').textContent=d.extended?String(d.command_sequence):'未提供';
  $('stAdsOnline').textContent=d.extended?[0,1,2].map(i=>d.ads_online&(1<<i)?'在线':'离线').join(' / '):'未提供';
  $('stAux').textContent=d.extended?`旧距离 ${d.aux_online&1?'在线':'离线'} / 手势 ${d.aux_online&2?'在线':'离线'}`:'未提供';
  $('stEncoder').textContent=d.extended?`编码器：${d.encoder_active?'转动':'静止'} · ${d.encoder_direction?'CW':'CCW'} · 深度 ${d.encoder_depth} · 颤音${features&2?'开':'关'}`:'编码器：未提供';
  $('stGesture').textContent='手势：'+(d.extended?(GESTURES[d.gesture]|| (d.gesture?`未知 ${d.gesture}`:'无')):'未提供');
  const pressureNames=['升音片','降音片','预留2','预留3','预留4','预留5','预留6'];
  $('stPressure').textContent='压力 ADC：'+(d.extended?d.pressure.map((v,i)=>`${pressureNames[i]} ${d.pressure_valid&(1<<i)?v:'—'}`).join(' · '):'未提供');
  $('stAudio').textContent=d.audio_frames!==undefined?`累计音频帧 ${d.audio_frames}\n失败 B ${d.audio_bad_b} / C ${d.audio_bad_c} · CRC B ${d.audio_crc_b} / C ${d.audio_crc_c}\n帧号错误 B ${d.audio_sequence_b} / C ${d.audio_sequence_c} · 版本错误 B ${d.audio_version_b} / C ${d.audio_version_c}`:'音频链路：未提供';
  const a=d.aux_diagnostic;
  $('stDiagnostic').textContent=a?`辅助诊断：${a.valid?'有效':'未就绪'} · PC ${a.pc} · 状态 ${a.state}\n错误 ${a.error} · 总线故障 ${a.bus_fault} · 尝试 ${a.attempts} · 事务 ${a.transactions}\nSCL ${Number(a.scl)} / SDA ${Number(a.sda)} · 失败PC ${a.fail_pc} · 寄存器 0x${a.fail_reg.toString(16)}`:'辅助诊断：未提供';
  const p=d.aux_probe;
  $('stProbe').textContent=p?`I²C 探测：阶段 ${p.phase} · 标志 0x${p.flags.toString(16)} · 轮次 ${p.rounds} · ACK ${p.ack_count}\n地址：${p.addresses.map(x=>'0x'+x.toString(16).padStart(2,'0')).join(' ')||'无'}`:'I²C 探测：未提供';
  const e=d.encoder_diagnostic;
  $('stEncoderDiagnostic').textContent=e?`编码器引脚：A ${Number(e.raw_a)} / B ${Number(e.raw_b)} · 计数 ${e.count} · 非法跳变 ${e.illegal_seen?'有':'无'}`:'编码器引脚诊断：未提供（当前手机串口不附带）';
  document.querySelectorAll('.timbre').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.mode)===d.timbre)));
  document.querySelectorAll('.feat').forEach(b=>b.setAttribute('aria-pressed',String(!!(features&(1<<Number(b.dataset.bit))))));
  frameCount++;const now=performance.now();
  if(now-rateAt>=1000){$('stRate').textContent=(frameCount*1000/(now-rateAt)).toFixed(1)+' Hz';frameCount=0;rateAt=now;}
  lastFrameAt=now;
  if(!dataOnline){dataOnline=true;setPills();log(`收到有效 ${simTimer?'模拟 ':''}AA${d.frame_type.toString(16).toUpperCase()} 状态帧`);}
  updateControls();
}
// One in-flight GATT write. Gate updates coalesce, so a release cannot sit behind old heartbeats.
function sendCmd(op,arg=0,label=''){
  if(simTimer){applySimCommand(op,arg);if(op!==0x20) log('[模拟] '+label);return;}
  if(!bleConnected||!rxChar) return;
  const task={op,arg,label,session,time:performance.now()};
  if(op===0x20) pendingGate=task;
  else if(pendingCommands.length<32) pendingCommands.push(task);
  else {log('命令队列已满，请稍后重试');return;}
  void drainWrites();
}
async function drainWrites(){
  if(writing) return;writing=true;
  try{
    while(pendingGate||pendingCommands.length){
      const task=pendingGate||pendingCommands.shift();
      if(task===pendingGate) pendingGate=null;
      if(task.session!==session||!bleConnected||!rxChar) continue;
      const characteristic=rxChar;
      const arg=task.op===0x20&&performance.now()-task.time>400?0:task.arg;
      seq=seq%255+1;const b=P.commandPacket(seq,task.op,arg);
      try{
        if(task.op===0x20&&characteristic.properties?.writeWithoutResponse&&typeof characteristic.writeValueWithoutResponse==='function') await characteristic.writeValueWithoutResponse(b);
        else if(typeof characteristic.writeValueWithResponse==='function') await characteristic.writeValueWithResponse(b);
        else await characteristic.writeValue(b);
        if(task.session===session&&task.op!==0x20) log(`已写入 ${task.label} · 序号 ${b[2]}（以设备状态为准）`);
      }catch(e){if(task.session===session) log('蓝牙写入失败：'+(e.message||e));}
    }
  }finally{writing=false;}
}
function rebuildRemoteMask(){
  remoteMask=0;
  for(const i of pointerNotes.values()) remoteMask|=1<<i;
  for(const i of keyboardNotes) remoteMask|=1<<i;
  keyEls.forEach((el,i)=>el.classList.toggle('remote',!!(remoteMask&(1<<i))));
  sendCmd(0x20,remoteMask);
  if(remoteMask&&!gateTimer) gateTimer=setInterval(()=>{if(remoteMask) sendCmd(0x20,remoteMask);},150);
  if(!remoteMask&&gateTimer){clearInterval(gateTimer);gateTimer=null;}
}
function releaseAllRemote(){pointerNotes.clear();keyboardNotes.clear();rebuildRemoteMask();}
keyEls.forEach((el,i)=>{
  el.addEventListener('pointerdown',e=>{
    e.preventDefault();if(!dataOnline) return;
    el.setPointerCapture?.(e.pointerId);pointerNotes.set(e.pointerId,i);rebuildRemoteMask();
  });
  const up=e=>{if(pointerNotes.delete(e.pointerId)) rebuildRemoteMask();};
  ['pointerup','pointercancel','lostpointercapture'].forEach(name=>el.addEventListener(name,up));
  el.addEventListener('keydown',e=>{if((e.key===' '||e.key==='Enter')&&dataOnline){e.preventDefault();if(!e.repeat){keyboardNotes.add(i);rebuildRemoteMask();}}});
  el.addEventListener('keyup',e=>{if(e.key===' '||e.key==='Enter'){e.preventDefault();keyboardNotes.delete(i);rebuildRemoteMask();}});
  el.addEventListener('blur',()=>{if(keyboardNotes.delete(i)) rebuildRemoteMask();});
});
window.addEventListener('blur',releaseAllRemote);
window.addEventListener('pagehide',releaseAllRemote);
document.addEventListener('visibilitychange',()=>{if(document.hidden){releaseAllRemote();stopScore('已暂停曲谱指引');}});
document.querySelectorAll('.timbre').forEach(b=>b.onclick=()=>sendCmd(1,Number(b.dataset.mode),`音色 ${P.TIMBRES[Number(b.dataset.mode)]}`));
document.querySelectorAll('.feat').forEach(b=>b.onclick=()=>{
  const index=Number(b.dataset.bit),bit=1<<index;
  features^=bit;
  // Masked feature update preserves concurrent PC edits to the other two bits.
  sendCmd(3,(bit<<8)|(features&bit),'演奏表情');
});
document.querySelectorAll('[data-store]').forEach(b=>b.onclick=()=>{
  const op=Number(b.dataset.store);
  if(op===0x10&&!confirm('准备／擦除会删除设备内已有演奏记录，确定继续？')) return;
  sendCmd(op,0,b.textContent);
});
$('btnZero').onclick=()=>sendCmd(0x30,0,'压力零点');
$('btnConnect').onclick=()=>bleConnected?disconnect():connect();
function sealFrame(f){let sum=0;for(let i=2;i<f.length-2;i++) sum=(sum+f[i])&255;f[f.length-2]=sum;f[f.length-1]=13;return f;}
function simTick(){
  const f=new Uint8Array(108);f[0]=0xaa;f[1]=0x59;f[2]=(simState.sequence++&255);f[3]=1;
  f[4]=remoteMask||([0x15,0x2a,1][Math.floor(performance.now()/2000)%3]);f[5]=simState.timbre;
  f[6]=0x68;f[7]=0x19;f[8]=0xd0;f[9]=7;f[10]=15;f[11]=simState.features;f[12]=7;f[13]=2;f[14]=3;
  f[15]=simState.store;f[16]=simState.flags;f[17]=simState.ack;f[18]=0x34;f[19]=0xc2;f[21]=3;f[22]=0x80;f[23]=4;f[24]=0x80;f[25]=2;
  sealFrame(f);
  // Even the demo passes through the production stream parser in 20-byte BLE chunks.
  for(let i=0;i<f.length;i+=20) for(const d of parser.feed(f.subarray(i,i+20))) renderState(d);
}
function applySimCommand(op,arg){
  simState.ack=simState.ack%255+1;
  if(op===1) simState.timbre=arg;
  if(op===3){const mask=(arg>>>8)&7;simState.features=(simState.features&~mask)|(arg&mask);}
  if(op===0x10){simState.store=0;simState.flags=4;}
  if(op===0x11){simState.store=3;simState.flags=1;}
  if(op===0x12){simState.store=simState.store===3?6:0;simState.flags=0;}
  if(op===0x13){simState.store=4;simState.flags=2;}
  simTick();
}
$('btnSim').onclick=()=>{
  if(bleConnected||connecting) return;
  if(simTimer){clearInterval(simTimer);simTimer=null;releaseAllRemote();resetData();$('btnSim').textContent='模拟演示';}
  else{resetData();simState={timbre:4,features:3,store:0,flags:4,sequence:1,ack:0};simTimer=setInterval(()=>{if(simState.store===6){simState.store=0;simState.flags=0;}simTick();},100);$('btnSim').textContent='退出模拟';simTick();}
  setPills();
};
function clearGuide(){keyEls.forEach(el=>el.classList.remove('guide'));scoreEls.forEach(el=>el.classList.remove('on'));}
function stopScore(message){if(scoreTimer) clearTimeout(scoreTimer);scoreTimer=null;scoreRunning=false;clearGuide();$('btnScore').textContent='播放指引';if(message) $('scoreHint').textContent=message;}
function stepScore(){
  if(!scoreRunning) return;
  if(scoreIdx>=scoreNotes.length){stopScore('曲谱指引已结束');return;}
  clearGuide();const keys=scoreNotes[scoreIdx];
  keys.forEach(i=>{keyEls[i].classList.add('guide');scoreEls[i].classList.add('on');});
  $('scoreHint').textContent=`第 ${scoreIdx+1}/${scoreNotes.length} 拍：${keys.map(i=>NOTES[i]).join(' + ')||'休止'}`;
  scoreIdx++;scoreTimer=setTimeout(stepScore,Math.round(60000/scoreBpm));
}
$('btnScore').onclick=()=>{
  if(scoreRunning){stopScore('已停止指引');return;}
  scoreNotes=SONGS[$('songSelect').value].notes;scoreIdx=0;scoreBpm=Math.max(40,Math.min(240,Number($('bpm').value)||100));
  scoreRunning=true;$('btnScore').textContent='停止指引';stepScore();
};
$('songSelect').onchange=()=>stopScore('已切换曲谱');
$('btnLoadScore').onclick=()=>$('scoreFile').click();
$('scoreFile').onchange=async ev=>{
  const file=ev.target.files[0];if(!file) return;
  try{
    if(file.size>1024*1024) throw Error('曲谱文件请小于 1 MB');
    const song=P.validateScore(JSON.parse(await file.text()));SONGS.custom=song;
    let opt=$('customScore');if(!opt){opt=document.createElement('option');opt.id='customScore';opt.value='custom';$('songSelect').appendChild(opt);}
    opt.textContent=song.title;$('songSelect').value='custom';$('bpm').value=song.bpm;stopScore(`已载入 ${song.title} · ${song.notes.length} 拍`);
  }catch(e){stopScore('曲谱载入失败：'+e.message);}
  finally{ev.target.value='';}
};
setInterval(()=>{
  if(dataOnline&&performance.now()-lastFrameAt>2000){
    releaseAllRemote();dataOnline=false;setPills();keyEls.forEach(el=>el.classList.remove('active'));
    $('stTouch').textContent='—';$('stPoly').textContent='0 / 7 键';$('stRate').textContent='0 Hz';
    log('超过 2 秒未收到有效状态帧，数据离线；面板其余数值为最后一次状态');
  }
},500);
if(!window.isSecureContext) $('supportHint').textContent='连接蓝牙需要 HTTPS 页面；请使用支持 Web Bluetooth 的浏览器。';
else if(!navigator.bluetooth) $('supportHint').textContent='此浏览器不支持 Web Bluetooth。iPhone 请使用兼容的 BLE 浏览器，Safari 不支持；仍可查看模拟演示。';
setPills();
if(new URLSearchParams(location.search).has('sim')) $('btnSim').click();
if(new URLSearchParams(location.search).has('score')) $('btnScore').click();
