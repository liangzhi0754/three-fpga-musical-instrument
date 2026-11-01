/* Real Edge DOM + production scripts, with an in-page BLE device double. No npm deps. */
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const edge=process.env.EDGE_PATH||'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const profile=fs.mkdtempSync(path.join(__dirname,'.edge-profile-'));
let browser,ws,server;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function main(){
  assert.ok(fs.existsSync(edge),'Edge not found; set EDGE_PATH to the browser executable');
  server=http.createServer((req,res)=>{
    const relative=new URL(req.url,'http://localhost').pathname;
    const target=path.resolve(root,'.'+(relative==='/'?'/index.html':relative));
    if(!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
    fs.readFile(target,(err,data)=>{if(err){res.writeHead(404);res.end();return;}res.setHeader('Content-Type',target.endsWith('.js')?'application/javascript':target.endsWith('.css')?'text/css':'text/html; charset=utf-8');res.end(data);});
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const url=`http://127.0.0.1:${server.address().port}/`;
  browser=spawn(edge,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--remote-debugging-port=0',`--user-data-dir=${profile}`,'about:blank'],{windowsHide:true,stdio:'ignore'});
  const portFile=path.join(profile,'DevToolsActivePort');
  for(let i=0;i<150&&!fs.existsSync(portFile);i++) await delay(100);
  assert.ok(fs.existsSync(portFile),'browser debug endpoint did not start');
  const port=fs.readFileSync(portFile,'utf8').split('\n')[0];
  const pages=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
  await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;});
  let id=0;const calls=new Map(),errors=[];
  ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id){const c=calls.get(m.id);calls.delete(m.id);if(m.error)c.reject(Error(JSON.stringify(m.error)));else c.resolve(m.result);}if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails);};
  function cdp(method,params={}){return new Promise((resolve,reject)=>{const n=++id;calls.set(n,{resolve,reject});ws.send(JSON.stringify({id:n,method,params}));});}
  await cdp('Runtime.enable');await cdp('Page.enable');
  await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
  await cdp('Page.addScriptToEvaluateOnNewDocument',{source:`
    window.__writes=[];window.__inflight=0;window.__peak=0;
    window.__rx={properties:{writeWithoutResponse:true},async writeValueWithResponse(bytes){window.__inflight++;window.__peak=Math.max(window.__peak,window.__inflight);await new Promise(r=>setTimeout(r,8));window.__writes.push([...bytes]);window.__inflight--;},async writeValueWithoutResponse(bytes){return this.writeValueWithResponse(bytes);}};
    window.__tx=new EventTarget();window.__tx.startNotifications=async()=>{};
    window.__device=new EventTarget();window.__device.gatt={connected:false,async connect(){this.connected=true;return {getPrimaryService:async()=>({getCharacteristic:async uuid=>uuid.includes('0003')?window.__tx:window.__rx})};},disconnect(){this.connected=false;window.__device.dispatchEvent(new Event('gattserverdisconnected'));}};
    Object.defineProperty(navigator,'bluetooth',{configurable:true,value:{requestDevice:async()=>window.__device}});
    window.confirm=()=>true;
  `});
  await cdp('Page.navigate',{url});
  for(let i=0;i<100;i++){
    const r=await cdp('Runtime.evaluate',{expression:'typeof InstrumentProtocol!=="undefined" && !!document.getElementById("btnConnect") && typeof renderState==="function"',returnByValue:true});
    if(r.result.value) break;await delay(50);
  }
  async function evaluate(expression){const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
  const result=await evaluate(`(async()=>{
    const passed=[];const check=(ok,name)=>{if(!ok) throw Error(name);passed.push(name);};
    const wait=ms=>new Promise(r=>setTimeout(r,ms));
    const notify=f=>{for(let i=0;i<f.length;i+=20){const bytes=f.slice(i,i+20);window.__tx.value=new DataView(bytes.buffer);window.__tx.dispatchEvent(new Event('characteristicvaluechanged'));}};
    const fixture=()=>{const f=new Uint8Array(108);f[0]=170;f[1]=89;f[3]=1;f[4]=127;f[5]=4;f[10]=15;f[11]=3;f[12]=7;f[14]=3;f[15]=0;f[16]=4;f[18]=69;f[19]=227;f[21]=3;f[22]=12;return sealFrame(f);};
    check(document.querySelectorAll('.timbre').length===5,'five timbre buttons');
    check(getComputedStyle(document.body).backgroundColor==='rgb(245, 247, 246)','light theme');
    check(document.documentElement.scrollWidth<=innerWidth,'390px no horizontal overflow');
    document.getElementById('btnSim').click();
    check(document.getElementById('stTimbre').textContent==='空灵竹笛32','offline demo uses ID4 production parser');
    document.getElementById('btnSim').click();
    await connect();notify(fixture());
    check(document.getElementById('stPoly').textContent==='7 / 7 键','seven-key polyphony render');
    check(document.getElementById('stEncoder').textContent.includes('深度 9029'),'encoder depth render');
    document.querySelector('[data-mode="4"]').click();await wait(40);
    check(__writes.some(b=>b[3]===1&&b[4]===4&&b[6]===((b[2]+5)&255)),'ID4 BLE write and checksum');
    const keys=[...document.querySelectorAll('.key')];
    // Synthetic DOM pointers have no native capture token; test the production handlers.
    keys.forEach(key=>key.setPointerCapture=()=>{});
    const down=(i,p)=>keys[i].dispatchEvent(new PointerEvent('pointerdown',{pointerId:p,bubbles:true,cancelable:true}));
    const up=(i,p,type='pointerup')=>keys[i].dispatchEvent(new PointerEvent(type,{pointerId:p,bubbles:true}));
    down(0,11);down(4,12);await wait(50);
    check(__writes.filter(b=>b[3]===32).at(-1)[4]===17,'multitouch chord mask');
    up(0,11);await wait(40);check(__writes.filter(b=>b[3]===32).at(-1)[4]===16,'one finger release keeps other key');
    up(4,12,'pointercancel');await wait(40);check(__writes.filter(b=>b[3]===32).at(-1)[4]===0,'pointer cancellation releases notes');
    down(0,21);down(0,22);up(0,21);await wait(40);check(__writes.filter(b=>b[3]===32).at(-1)[4]===1,'two pointers on same key');up(0,22);
    down(2,31);window.dispatchEvent(new Event('blur'));await wait(50);check(__writes.filter(b=>b[3]===32).at(-1)[4]===0,'blur releases held notes');
    document.querySelector('[data-bit="1"]').click();await wait(40);check(__writes.some(b=>b[3]===3&&b[5]===2),'masked feature command');
    let f=fixture();f[15]=6;f[16]=1;notify(sealFrame(f));
    check(document.getElementById('stStore').textContent==='停止收尾中'&&document.getElementById('btnRec').disabled&&!document.getElementById('btnStop').disabled,'status6 storage controls');
    f[15]=0;f[16]=8;notify(sealFrame(f));check(document.getElementById('stStore').textContent.includes('未提供故障码'),'phone fault without diagnostic code');
    f[15]=0x50;notify(sealFrame(f));check(document.getElementById('stStore').textContent.includes('SPI操作超时'),'specific store fault code');
    const old=document.getElementById('stTimbre').textContent;f[5]=0;f[106]^=1;notify(f);check(document.getElementById('stTimbre').textContent===old,'bad checksum rejected in notification handler');
    const before=__writes.length;document.getElementById('btnScore').click();await wait(30);document.getElementById('btnScore').click();check(__writes.length===before,'local score does not send BLE commands');
    const file=new File([JSON.stringify({title:'本地和弦',events:[{keys:[0,2,4]},{keys:[]}],bpm:120})],'score.json',{type:'application/json'});const transfer=new DataTransfer();transfer.items.add(file);const input=document.getElementById('scoreFile');input.files=transfer.files;input.dispatchEvent(new Event('change'));await wait(60);check(document.getElementById('songSelect').value==='custom'&&document.getElementById('scoreHint').textContent.includes('本地和弦'),'local JSON score import');
    check(__peak===1,'GATT writes serialized');
    down(1,40);await wait(30);await disconnect();check(document.getElementById('dataPill').textContent==='数据离线'&&!keys.some(k=>k.classList.contains('remote')),'disconnect clears remote and status');
    await connect();notify(fixture());check(document.getElementById('stTimbre').textContent==='空灵竹笛32','clean reconnect parses frames');
    await wait(2600);check(document.getElementById('dataPill').textContent==='数据离线'&&keys[0].disabled,'missing telemetry disables phone controls');
    await disconnect();return passed;
  })()`);
  assert.equal(errors.length,0,JSON.stringify(errors));
  for(const name of result) console.log('PASS '+name);
  console.log(`Browser DOM smoke: ${result.length} passed; no uncaught browser exceptions.`);
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{
  if(ws)ws.close();if(browser){browser.kill();await delay(1200);}
  if(server)await new Promise(r=>server.close(r));
  // This test creates only this profile beneath mobile/tests; verify containment before removal.
  const resolved=path.resolve(profile),parent=path.resolve(__dirname)+path.sep;
  if(resolved.startsWith(parent)&&path.basename(resolved).startsWith('.edge-profile-')){
    try{fs.rmSync(resolved,{recursive:true,force:true,maxRetries:10,retryDelay:200});}catch(e){console.error('Profile cleanup:',e.message);}
  }
});
