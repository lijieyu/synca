const {isNewer,validateRelease,installerPath,STORE}=require('./update-policy.cjs');
class UpdateController {
 constructor(options){this.options=options;this.state={phase:'idle'};this.release=null;this.bootstrap=null;
  options.autoUpdater?.on('error',()=>this.set({phase:'error'}));
  options.autoUpdater?.on('update-not-available',()=>this.set({phase:'current'}));
  options.autoUpdater?.on('update-downloaded',()=>{if(this.state.phase==='downloading')this.set({phase:'ready'});});
 }
 set(patch){this.state={...this.state,...patch};this.options.changed?.(this.state);return this.state;}
 async check(){
  if(['checking','downloading','ready','installing'].includes(this.state.phase))return this.state;
  this.set({phase:'checking'});
  try{const catalog=await this.options.catalog();const raw=this.options.platform==='darwin'?catalog.macos:catalog.windows?.[this.options.arch];
   if(!raw||!isNewer(raw.version,this.options.version)){this.release=null;return this.set({phase:'current',version:undefined});}
   this.release=validateRelease(raw,this.options.platform,this.options.arch);
   return this.set({phase:'available',version:raw.version,store:this.options.platform==='darwin',migration:!this.options.installed});
  }catch{return this.set({phase:'error'});}
 }
 async download(){
  if(this.state.phase!=='available'||!this.release)return this.state;
  if(this.options.platform==='darwin'){await this.options.openStore(STORE);return this.state;}
  this.set({phase:'downloading'});
  try{
   if(this.options.installed){this.options.autoUpdater.setFeedURL({url:this.release.feed});this.options.autoUpdater.checkForUpdates();}
   else {this.bootstrap=await this.options.download(this.release);this.set({phase:'ready'});}
  }catch{this.set({phase:'error'});}
  return this.state;
 }
 async install(){
  if(this.state.phase!=='ready')return this.state;
  this.set({phase:'installing'});
  try{
   if(this.options.installed){this.options.prepareRestart();this.options.autoUpdater.quitAndInstall();}
   else {await this.options.runInstaller(this.bootstrap);this.options.prepareRestart();this.options.quit();}
  }catch{this.set({phase:'error'});}
  return this.state;
 }
}
async function downloadInstaller(release,fetcher,directory){
 const fs=require('node:fs/promises'),path=require('node:path'),{createHash}=require('node:crypto');
 const dir=await fs.mkdtemp(path.join(directory,'synca-update-'));
 const target=path.join(dir,'Setup.exe');let handle;
 try{
  const response=await fetcher(release.url,{redirect:'error',signal:AbortSignal.timeout(15*60*1000)});
  if(!response.ok||!response.body)throw Error('Download failed');
  handle=await fs.open(target,'wx',0o600);let bytes=0;const hash=createHash('sha256');
  for await(const chunk of response.body){bytes+=chunk.length;if(bytes>release.bytes)throw Error('Oversized installer');hash.update(chunk);await handle.writeFile(chunk);}
  await handle.sync();await handle.close();handle=null;
  if(bytes!==release.bytes||hash.digest('hex')!==release.sha256)throw Error('Installer checksum mismatch');
  return {path:target,release};
 }catch(error){if(handle)await handle.close();await fs.rm(dir,{recursive:true,force:true});throw error;}
}
function installUpdater(window,cfg,version,prepareRestart){
 const {app,autoUpdater,ipcMain,net,shell}=require('electron'),fs=require('node:fs'),fsp=require('node:fs/promises');
 const {spawn}=require('node:child_process'),{createHash}=require('node:crypto');
 if(cfg.isolated)return;
 const installed=process.platform==='win32'&&fs.existsSync(installerPath(process.execPath));
 const controller=new UpdateController({platform:process.platform,arch:process.arch,version,installed,autoUpdater:process.platform==='win32'?autoUpdater:null,
  changed:()=>{if(!window.isDestroyed())window.webContents.send('desktop:update');},
  catalog:async()=>{const response=await net.fetch('https://synca.haerth.cn/app-updates',{redirect:'error',signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Check failed');const text=await response.text();if(text.length>32768)throw Error('Invalid catalog');return JSON.parse(text);},
  download:release=>downloadInstaller(release,(url,options)=>net.fetch(url,options),app.getPath('temp')),
  openStore:url=>shell.openExternal(url),prepareRestart,quit:()=>app.quit(),
  runInstaller:async bootstrap=>{
   // Recheck the exact trusted file immediately before execution; never accept a renderer path.
   const bytes=await fsp.readFile(bootstrap.path);
   if(bytes.length!==bootstrap.release.bytes||createHash('sha256').update(bytes).digest('hex')!==bootstrap.release.sha256)throw Error('Installer changed');
   await new Promise((resolve,reject)=>{const child=spawn(bootstrap.path,['--silent'],{detached:true,stdio:'ignore'});child.once('error',reject);child.once('spawn',()=>{child.unref();resolve();});});
  }
 });
 const trusted=event=>event.sender===window.webContents&&event.senderFrame===event.sender.mainFrame&&new URL(event.senderFrame.url).origin===cfg.home;
 ipcMain.handle('desktop:update-state',event=>{if(!trusted(event))throw Error('Untrusted update request');return controller.state;});
 ipcMain.handle('desktop:update-action',(event,action)=>{
  if(!trusted(event)||!['check','download','install'].includes(action))throw Error('Invalid update request');return controller[action]();
 });
 const timer=setTimeout(()=>void controller.check(),process.argv.includes('--squirrel-firstrun')?30000:15000);
 const interval=setInterval(()=>void controller.check(),6*60*60*1000);
 window.on('closed',()=>{clearTimeout(timer);clearInterval(interval);ipcMain.removeHandler('desktop:update-state');ipcMain.removeHandler('desktop:update-action');});
 return controller;
}
function squirrelEvent(app){
 if(process.platform!=='win32')return false;
 const event=process.argv.find(value=>/^--squirrel-(install|updated|uninstall|obsolete)$/.test(value));
 if(!event)return false;
 if(event!=='--squirrel-obsolete'){
  const {spawn}=require('node:child_process'),path=require('node:path');
  const child=spawn(installerPath(process.execPath),[event==='--squirrel-uninstall'?'--removeShortcut':'--createShortcut',path.basename(process.execPath)],{detached:true,stdio:'ignore'});
  child.on('error',()=>{});child.unref();
 }
 app.quit();return true;
}
module.exports={UpdateController,downloadInstaller,installUpdater,squirrelEvent};
