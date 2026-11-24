// Run with an Electron executable. Uses a private profile and loopback synthetic API.
const {app,BrowserWindow,ipcMain,session}=require('electron');
const http=require('node:http'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const {installPlatform}=require('./app/platform.cjs');
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'synca-notify-runtime-'));
app.setPath('userData',profile);app.setName('Synca Sync Verification');
let count=2;const streams=new Set(),requests=[];let win,server;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn){for(let i=0;i<80;i++){if(fn())return;await sleep(50);}throw Error('Timed out waiting for badge');}
app.whenReady().then(async()=>{
 try{
  server=http.createServer((req,res)=>{
   requests.push(req.url);
   if(req.url==='/sync/events'){assert.equal(req.headers.authorization,'Bearer synthetic');res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-store'});streams.add(res);res.write('event: change\ndata: {}\n\n');res.on('close',()=>streams.delete(res));return;}
   if(req.url==='/sync/state'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({messages:String(count),categories:'c',access:'a',count}));return;}
   res.writeHead(200,{'Content-Type':'text/html'});res.end('<title>Sync verification</title>');
  });await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const home='http://127.0.0.1:'+server.address().port;
  const ses=session.fromPartition('sync-verification-'+Date.now());
  win=new BrowserWindow({show:false,width:640,height:500,webPreferences:{session:ses,sandbox:true}});
  win.on('close',e=>{e.preventDefault();win.hide()});
  installPlatform(win,ses,()=>win.show(),()=>{},{home,push:false,local:false,bundleId:'test.synca'});
  await win.loadURL(home+'/');
  const event={sender:win.webContents,senderFrame:win.webContents.mainFrame};
  ipcMain.emit('desktop:session',event,'synthetic');await until(()=>app.getBadgeCount()===2);
  win.close();assert.equal(win.isVisible(),false);
  count=7;for(const res of streams)res.write('event: change\ndata: {}\n\n');await until(()=>app.getBadgeCount()===7);
  assert(!requests.some(p=>p.startsWith('/messages')));
  ipcMain.emit('desktop:session',event,null);await until(()=>app.getBadgeCount()===0);await until(()=>streams.size===0);
  console.log(JSON.stringify({passed:true,checks:['real Electron net.fetch stream','closed window stays alive','system Dock badge 2 → 7','no record download while hidden','logout closes stream and clears badge'],requests}));
 }catch(error){console.error(error);process.exitCode=1;}
 finally{for(const res of streams)res.end();server?.closeAllConnections();server?.close();win?.destroy();app.exit(process.exitCode||0);}
});
