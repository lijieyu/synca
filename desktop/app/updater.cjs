const {isNewer,validateRelease,installerPath,isSquirrelInstalled,STORE}=require('./update-policy.cjs');
class UpdateController {
 constructor(options){this.options=options;this.state={phase:'idle'};this.release=null;this.bootstrap=null;this.abort=new AbortController();
  this.listeners={error:()=>{void this.cleanup();this.set({phase:'error'});},'update-not-available':()=>{void this.cleanup();this.set({phase:'current'});},'update-downloaded':()=>{if(this.state.phase==='downloading'){void this.cleanup();this.set({phase:'ready'});}}};
  for(const [event,listener] of Object.entries(this.listeners))options.autoUpdater?.on(event,listener);
 }
 async cleanup(){clearTimeout(this.timeout);const feed=this.feed;this.feed=null;await feed?.close().catch(()=>{});}
 async discardBootstrap(){const staged=this.bootstrap;this.bootstrap=null;await staged?.dispose?.().catch(()=>{});}
 dispose(){return this.disposal??=(async()=>{this.disposed=true;this.abort.abort();await this.pendingDownload?.catch(()=>{});await this.pendingInstall?.catch(()=>{});await this.discardBootstrap();await this.cleanup();for(const [event,listener] of Object.entries(this.listeners))this.options.autoUpdater?.removeListener(event,listener);})();}
 set(patch){if(this.disposed)return this.state;this.state={...this.state,...patch};this.options.changed?.(this.state);return this.state;}
 async check(){
  if(this.disposed)return this.state;
  if(['checking','downloading','ready','installing'].includes(this.state.phase))return this.state;
  this.set({phase:'checking'});
  try{const catalog=await this.options.catalog();const raw=this.options.platform==='darwin'?catalog.macos:catalog.windows?.[this.options.arch];
   if(!raw||!isNewer(raw.version,this.options.version)){this.release=null;return this.set({phase:'current',version:undefined});}
   this.release=validateRelease(raw,this.options.platform,this.options.arch);
   return this.set({phase:'available',version:raw.version,store:this.options.platform==='darwin',migration:!this.options.installed});
  }catch{return this.set({phase:'error'});}
 }
 async download(){
  if(this.disposed||this.state.phase!=='available'||!this.release)return this.state;
  if(this.options.platform==='darwin'){await this.options.openStore(STORE);return this.state;}
  this.set({phase:'downloading'});
  try{
   if(this.options.installed){
    await this.cleanup();this.pendingDownload=this.options.prepareFeed(this.release,this.abort.signal);this.feed=await this.pendingDownload;
    if(this.disposed){await this.cleanup();return this.state;}
    this.options.autoUpdater.setFeedURL({url:this.feed.url});
    this.timeout=setTimeout(()=>{void this.cleanup();this.set({phase:'error'});},15*60*1000);this.timeout.unref?.();this.options.autoUpdater.checkForUpdates();
   }
   else {this.pendingDownload=(async()=>{await this.discardBootstrap();if(this.disposed)return null;return this.options.download(this.release,this.abort.signal);})();this.bootstrap=await this.pendingDownload;if(this.disposed)await this.discardBootstrap();else this.set({phase:'ready'});}
  }catch{await this.cleanup();this.set({phase:'error'});}
  return this.state;
 }
 async install(){
  if(this.disposed||this.state.phase!=='ready')return this.state;
  this.set({phase:'installing'});
  try{
   if(this.options.installed){this.options.prepareRestart();this.options.autoUpdater.quitAndInstall();}
   else {this.pendingInstall=this.options.runInstaller(this.bootstrap);await this.pendingInstall;await this.discardBootstrap();if(!this.disposed){this.options.prepareRestart();this.options.quit();}}
  }catch{await this.discardBootstrap();this.set({phase:'error'});}
  return this.state;
 }
}
async function downloadInstaller(release,fetcher,directory,filename='Setup.exe',signal){
 const fs=require('node:fs/promises'),path=require('node:path'),{createHash}=require('node:crypto');
 if(!/^(?:Setup\.exe|Synca-\d+\.\d+\.\d+-full\.nupkg)$/.test(filename))throw Error('Invalid download name');
 const dir=await fs.mkdtemp(path.join(directory,'synca-update-'));
 const target=path.join(dir,filename);let handle;
 try{
  const response=await fetcher(release.url,{redirect:'error',signal:signal?AbortSignal.any([signal,AbortSignal.timeout(15*60*1000)]):AbortSignal.timeout(15*60*1000)});
  if(!response.ok||!response.body)throw Error('Download failed');
  handle=await fs.open(target,'wx',0o600);let bytes=0;const hash=createHash('sha256');
  for await(const chunk of response.body){bytes+=chunk.length;if(bytes>release.bytes)throw Error('Oversized installer');hash.update(chunk);await handle.writeFile(chunk);}
  await handle.sync();await handle.close();handle=null;
  if(bytes!==release.bytes||hash.digest('hex')!==release.sha256)throw Error('Installer checksum mismatch');
  return {path:target,release,dispose:()=>fs.rm(dir,{recursive:true,force:true,maxRetries:5,retryDelay:100})};
 }catch(error){if(handle)await handle.close();await fs.rm(dir,{recursive:true,force:true});throw error;}
}
function installUpdater(window,cfg,version,prepareRestart){
 const {app,autoUpdater,ipcMain,net,shell}=require('electron'),fs=require('node:fs'),fsp=require('node:fs/promises');
 const {spawn}=require('node:child_process'),{createHash}=require('node:crypto');
 if(cfg.isolated||cfg.store||process.windowsStore)return;
 const installed=process.platform==='win32'&&isSquirrelInstalled(process.execPath,process.env.LOCALAPPDATA);
 const controller=new UpdateController({platform:process.platform,arch:process.arch,version,installed,autoUpdater:process.platform==='win32'?autoUpdater:null,
  changed:()=>{if(!window.isDestroyed())window.webContents.send('desktop:update');},
  catalog:async()=>{const response=await net.fetch('https://synca.haerth.cn/app-updates',{redirect:'error',signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('Check failed');const text=await response.text();if(text.length>32768)throw Error('Invalid catalog');return JSON.parse(text);},
  prepareFeed:(release,signal)=>require('./verified-feed.cjs').verifiedFeed(release,(url,options)=>net.fetch(url,options),app.getPath('temp'),signal),
  download:(release,signal)=>downloadInstaller(release,(url,options)=>net.fetch(url,options),app.getPath('temp'),'Setup.exe',signal),
  openStore:url=>shell.openExternal(url),prepareRestart,quit:()=>app.quit(),
  runInstaller:async bootstrap=>{
   // Recheck the exact trusted file immediately before execution; never accept a renderer path.
   const bytes=await fsp.readFile(bootstrap.path);
   if(bytes.length!==bootstrap.release.bytes||createHash('sha256').update(bytes).digest('hex')!==bootstrap.release.sha256)throw Error('Installer changed');
   // Keep this app alive until Setup reports success so installer failures remain
   // visible and retryable. Squirrel's processStartAndWait waits for our exit.
   await new Promise((resolve,reject)=>{const child=spawn(bootstrap.path,['--silent'],{stdio:'ignore'});const timer=setTimeout(()=>{child.kill();reject(Error('Installer timed out'));},20*60*1000);child.once('error',error=>{clearTimeout(timer);reject(error)});child.once('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error('Installer failed'))});});
   const update=require('node:path').join(app.getPath('appData'),'..','Local','Synca','Update.exe');
   const installedUpdate=process.env.LOCALAPPDATA?require('node:path').join(process.env.LOCALAPPDATA,'Synca','Update.exe'):update;
   await fsp.access(installedUpdate);
   await new Promise((resolve,reject)=>{const child=spawn(installedUpdate,['--processStartAndWait','Synca Electron.exe'],{detached:true,stdio:'ignore'});child.once('error',reject);child.once('spawn',()=>{child.unref();resolve();});});
  }
 });
 const trusted=event=>event.sender===window.webContents&&event.senderFrame===event.sender.mainFrame&&new URL(event.senderFrame.url).origin===cfg.home;
 ipcMain.handle('desktop:update-state',event=>{if(!trusted(event))throw Error('Untrusted update request');return controller.state;});
 ipcMain.handle('desktop:update-action',(event,action)=>{
  if(!trusted(event)||!['check','download','install'].includes(action))throw Error('Invalid update request');return controller[action]();
 });
 const timer=setTimeout(()=>void controller.check(),process.argv.includes('--squirrel-firstrun')?30000:15000);
 const interval=setInterval(()=>void controller.check(),6*60*60*1000);
 const willQuit=event=>{event.preventDefault();void controller.dispose().finally(()=>app.quit());};
 app.once('will-quit',willQuit);
 window.on('closed',()=>{void controller.dispose().finally(()=>app.removeListener('will-quit',willQuit));clearTimeout(timer);clearInterval(interval);ipcMain.removeHandler('desktop:update-state');ipcMain.removeHandler('desktop:update-action');});
 return controller;
}
function squirrelEvent(app,cfg={}){
 if(process.platform!=='win32'||cfg.store||process.windowsStore)return false;
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
