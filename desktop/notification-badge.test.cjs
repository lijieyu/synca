const test=require('node:test'), assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const {EventEmitter}=require('node:events');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
test('hidden Mac updates badge from notification without fetching records, then fences logout',async()=>{
 const badges=[],sent=[],requests=[];let stream,count=2;
 const ipcMain=new EventEmitter();ipcMain.handle=()=>{};
 const app=Object.assign(new EventEmitter(),{getPath:()=>'/private/tmp/synca-notification-test',getLocale:()=> 'en',setBadgeCount:n=>badges.push(n)});
 const window=Object.assign(new EventEmitter(),{isVisible:()=>false,isMinimized:()=>false,isDestroyed:()=>false,webContents:{send:(...args)=>sent.push(args)}});
 const frame={url:'https://synca.haerth.cn/'};window.webContents.mainFrame=frame;
 const session=Object.assign(new EventEmitter(),{fetch:async(url,options)=>{
  requests.push(url); if(url.endsWith('/sync/events'))return new Response(new ReadableStream({start(c){stream=c;c.enqueue(new TextEncoder().encode('event: change\ndata: {}\n\n'));options.signal.addEventListener('abort',()=>{try{c.close()}catch{}})}}),{headers:{'content-type':'text/event-stream'}});
  return Response.json({messages:'r'+count,categories:'c',access:'a',count});
 }});
 const powerMonitor=new EventEmitter();
 const electron={app,ipcMain,powerMonitor,pushNotifications:{},Menu:{getApplicationMenu:()=>null},nativeImage:{},dialog:{}};
 const box={module:{exports:{}},__dirname:path.resolve('app'),process:{platform:'darwin'},console,AbortSignal,setInterval,clearInterval,setTimeout,clearTimeout,require:id=>id==='electron'?electron:id==='./context-menu.cjs'?{installContextMenus(){}}:id.startsWith('./')?require(path.resolve('app',id)):require(id)};
 vm.runInNewContext(fs.readFileSync('app/platform.cjs','utf8'),box);
 box.module.exports.installPlatform(window,session,()=>{},()=>{},{home:'https://synca.haerth.cn',push:false});
 const event={sender:window.webContents,senderFrame:frame};
 try {
  ipcMain.emit('desktop:session',event,'test-token');await delay(80);assert.equal(badges.at(-1),2);
  count=7;stream.enqueue(new TextEncoder().encode('event: change\ndata: {}\n\n'));await delay(80);assert.equal(badges.at(-1),7);
  ipcMain.emit('desktop:count',event,2);assert.equal(badges.at(-1),7,'stale renderer cannot replace newer server count');
  assert.equal(sent.length,0,'hidden renderer does not refresh');assert(!requests.some(x=>x.includes('/messages')),'no list download for background badge');
  ipcMain.emit('desktop:session',event,null);const n=requests.length;await delay(50);assert.equal(badges.at(-1),0);assert.equal(requests.length,n);
 }finally{app.emit('will-quit');}
});
