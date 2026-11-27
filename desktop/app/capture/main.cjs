const {app,BrowserWindow,desktopCapturer,screen,systemPreferences,globalShortcut,ipcMain,clipboard,nativeImage,dialog,shell}=require('electron');
const fs=require('node:fs/promises'),path=require('node:path'),{promisify}=require('node:util'),{execFile}=require('node:child_process'),{pathToFileURL}=require('node:url');
const execute=promisify(execFile),{validateSelection}=require('./selection.cjs'),{pixels}=require('./geometry.cjs');
const DEFAULT='CommandOrControl+Shift+A';
function language(){const value=app.getLocale().toLowerCase();return /zh-(tw|hk|hant)/.test(value)?'zh-Hant':value.startsWith('zh')?'zh':'en';}
async function windowBounds(){
 let result;
 if(process.platform==='darwin'){
  const helper=path.join(process.resourcesPath,'native','synca-window-bounds');
  const {stdout}=await execute(helper,[],{timeout:5000,maxBuffer:1024*1024});result=JSON.parse(stdout);
 }else{
  const script=await fs.readFile(path.join(__dirname,'windows-bounds.ps1'),'utf8');
  const binary=path.join(process.env.SystemRoot||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');
  // Windows PowerShell 5 cannot load modules inherited from PowerShell 7.
  const env={...process.env};for(const key of Object.keys(env))if(key.toLowerCase()==='psmodulepath')delete env[key];
  const {stdout}=await execute(binary,['-NoProfile','-NonInteractive','-Command',script],{timeout:15000,maxBuffer:1024*1024,windowsHide:true,env});result=JSON.parse(stdout.replace(/^\uFEFF/,''));
 }
 if(!Array.isArray(result))throw Error('Window enumeration unavailable');
 return result.filter(r=>['x','y','width','height'].every(key=>Number.isFinite(r[key]))&&r.width>0&&r.height>0).map(r=>process.platform==='win32'?screen.screenToDipRect(null,{x:r.x,y:r.y,width:r.width,height:r.height}):r);
}
function installCapture(mainWindow,cfg,services={}){
 const preferences=path.join(app.getPath('userData'),'capture-preferences.json');let shortcut=DEFAULT,shortcutError=false,active=null,starting=false,activeLanguage=language();
 const trustedMain=e=>e.sender===mainWindow.webContents&&e.senderFrame===e.sender.mainFrame&&new URL(e.senderFrame.url).origin===cfg.home;
 const overlayURL=pathToFileURL(path.join(__dirname,'index.html')).href;
 const overlay=e=>{const entry=active?.entries.find(item=>item.window.webContents===e.sender);if(!entry||e.senderFrame!==e.sender.mainFrame||e.senderFrame.url!==overlayURL)throw Error('Untrusted capture request');return entry;};
 function cancel(){const state=active;active=null;if(state)for(const entry of state.entries){if(!entry.window.isDestroyed())entry.window.destroy();}}
 async function report(error){
  const zh=activeLanguage!=='en';
  const denied=process.platform==='darwin'&&systemPreferences.getMediaAccessStatus('screen')!=='granted';
  const result=await dialog.showMessageBox(mainWindow,{type:'info',message:denied?(zh?'请允许 Synca 录制屏幕以使用截图':'Allow Synca to record the screen to take screenshots'):(zh?'截图未能启动，请重试':'Could not start capture. Please try again.'),detail:denied?(zh?'在系统设置的“隐私与安全性 → 屏幕与系统音频录制”中允许 Synca，然后重新打开应用。':'Allow Synca in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app.'):(zh?'屏幕或窗口信息暂时不可用。':'Screen or window information is unavailable.'),buttons:denied?[zh?'打开系统设置':'Open System Settings',zh?'取消':'Cancel']:[zh?'好':'OK'],cancelId:denied?1:0});
  if(denied&&result.response===0)await shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture');
  console.warn('[capture] unavailable',error?.code??error?.message??'unknown');
 }
 async function start(){
  if(starting||active)return;starting=true;
  try{
   const preference=await mainWindow.webContents.executeJavaScript('localStorage.getItem("synca.language")').catch(()=>null);
   activeLanguage=preference==='zh-Hans'?'zh':['zh-Hant','en'].includes(preference)?preference:language();
   const displays=(services.displays??(()=>screen.getAllDisplays()))();const cursor=(services.cursor??(()=>screen.getCursorScreenPoint()))();
   const windows=await (services.windows??windowBounds)();
   const sources=await Promise.race([(services.sources??(options=>desktopCapturer.getSources(options)))({types:['screen'],thumbnailSize:{width:Math.min(16384,Math.max(...displays.map(d=>Math.ceil(d.size.width*d.scaleFactor)))),height:Math.min(16384,Math.max(...displays.map(d=>Math.ceil(d.size.height*d.scaleFactor))))},fetchWindowIcons:false}),new Promise((_,reject)=>setTimeout(()=>reject(Error('capture timeout')),12000))]);
   if(process.platform==='darwin'&&(services.permission??(()=>systemPreferences.getMediaAccessStatus('screen')))()!=='granted')throw Error('Screen permission required');
   active={entries:[],finishing:false};
   for(const display of displays){
    const source=sources.find(item=>String(item.display_id)===String(display.id));if(!source||source.thumbnail.isEmpty())throw Error('Missing screen');
    const frozen=source.thumbnail.toPNG();const size=nativeImage.createFromBuffer(frozen).getSize();
    const window=new BrowserWindow({...display.bounds,frame:false,transparent:false,backgroundColor:'#000000',show:false,resizable:false,movable:false,skipTaskbar:true,alwaysOnTop:true,fullscreenable:false,hasShadow:false,enableLargerThanScreen:true,
     webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false,preload:path.join(__dirname,'preload.cjs'),partition:`capture-${Date.now()}-${display.id}`,backgroundThrottling:false}});
    if(process.platform==='darwin')window.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});
    window.setAlwaysOnTop(true,'screen-saver');window.setMenu(null);
    const entry={window,display:display.bounds,size,payload:{png:'data:image/png;base64,'+frozen.toString('base64'),display:display.bounds,windows,cursor,language:activeLanguage}};active.entries.push(entry);
    window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',event=>event.preventDefault());
    window.on('closed',()=>{if(active?.entries.includes(entry))cancel();});
    await window.loadFile(path.join(__dirname,'index.html'));
   }
   const entries=active.entries;
   for(const entry of entries)entry.window.showInactive();
   const target=entries.find(entry=>cursor.x>=entry.display.x&&cursor.x<entry.display.x+entry.display.width&&cursor.y>=entry.display.y&&cursor.y<entry.display.y+entry.display.height)||entries[0];target.window.focus();
  }catch(error){cancel();await report(error);}finally{starting=false;}
 }
 function register(value){
  let okay=false;try{okay=globalShortcut.register(value,()=>void start());}catch{}
  if(!okay)return false;if(value!==shortcut)globalShortcut.unregister(shortcut);shortcut=value;shortcutError=false;return true;
 }
 void fs.readFile(preferences,'utf8').then(text=>{const value=JSON.parse(text).shortcut;if(typeof value==='string'&&value.length<80)shortcut=value;}).catch(()=>{}).finally(()=>{if(!mainWindow.isDestroyed())shortcutError=!register(shortcut);});
 ipcMain.handle('desktop:capture-settings',e=>{if(!trustedMain(e))throw Error('Untrusted');return{shortcut,error:shortcutError};});
 ipcMain.handle('desktop:capture-shortcut',async(e,value)=>{
  if(!trustedMain(e)||typeof value!=='string'||!/^(?:(?:CommandOrControl|Command|Control|Alt|Shift|Super)\+){1,4}[A-Z0-9]$/.test(value))throw Error('Invalid shortcut');
  if(value===shortcut&&!shortcutError)return{shortcut,error:false};const old=shortcut;
  if(!register(value))throw Error('Shortcut unavailable');
  try{await fs.writeFile(preferences,JSON.stringify({shortcut}),{mode:0o600});}catch(error){globalShortcut.unregister(shortcut);shortcut=old;shortcutError=!register(old);throw error;}
  return{shortcut,error:false};
 });
 ipcMain.handle('desktop:capture-start',e=>{if(!trustedMain(e))throw Error('Untrusted');void start();return{ok:true};});
 ipcMain.handle('capture:load',e=>overlay(e).payload);
 const onCancel=e=>{try{overlay(e);cancel();}catch{}};
 ipcMain.on('capture:cancel',onCancel);
 ipcMain.handle('capture:finish',async(e,value)=>{
  const entry=overlay(e),state=active;if(state.finishing)return{error:true};state.finishing=true;
  try{
   if(!['copy','save'].includes(value?.action))throw Error('Invalid action');validateSelection(value,entry.display);
   if(typeof value.png!=='string'||!value.png.startsWith('data:image/png;base64,')||value.png.length>160*1024*1024)throw Error('Invalid image');
   const bytes=Buffer.from(value.png.slice(22),'base64');
   const expected=pixels(value.rect,entry.size,entry.display);
   if(bytes.length<33||!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))||bytes.readUInt32BE(8)!==13||bytes.toString('ascii',12,16)!=='IHDR'||bytes.readUInt32BE(16)!==expected.width||bytes.readUInt32BE(20)!==expected.height||expected.width*expected.height>40000000)throw Error('Invalid PNG');
   const image=nativeImage.createFromBuffer(bytes);const size=image.getSize();
   if(image.isEmpty()||size.width!==expected.width||size.height!==expected.height)throw Error('Invalid crop size');
   if(value.action==='copy'){(services.clipboard??clipboard).writeImage(image);cancel();return{ok:true};}
   for(const item of state.entries)item.window.setAlwaysOnTop(false);
   const result=await (services.dialog??dialog).showSaveDialog(entry.window,{defaultPath:path.join(app.getPath('pictures'),`Synca-${new Date().toISOString().replace(/[:.]/g,'-')}.png`),filters:[{name:'PNG',extensions:['png']}]});
   if(active!==state||result.canceled||!result.filePath)return{cancelled:true};
   await fs.writeFile(result.filePath,image.toPNG());if(active===state)cancel();return{ok:true};
  }catch{return{error:true};}finally{state.finishing=false;if(active===state)for(const item of state.entries)if(!item.window.isDestroyed())item.window.setAlwaysOnTop(true,'screen-saver');}
 });
 mainWindow.on('closed',()=>{cancel();globalShortcut.unregister(shortcut);ipcMain.removeListener('capture:cancel',onCancel);for(const channel of ['desktop:capture-settings','desktop:capture-shortcut','desktop:capture-start','capture:load','capture:finish'])ipcMain.removeHandler(channel);});
 app.once('will-quit',()=>{cancel();globalShortcut.unregister(shortcut);});
 return{start};
}
module.exports={installCapture,windowBounds};
