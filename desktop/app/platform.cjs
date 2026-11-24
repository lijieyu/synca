const { createChangeNotifications } = require('./change-notifications.cjs')
const { app, dialog, ipcMain, Menu, nativeImage, powerMonitor, pushNotifications, Tray } = require('electron')
const fs=require('node:fs')
const path=require('node:path')
const { safeFileName } = require('./file-names.cjs')
function installPlatform(window, ses, restore, settings, cfg) {
  const HOME=cfg.home, topic=cfg.bundleId
  const file=path.join(app.getPath('userData'),'desktop-preferences.json')
  let prefs={badge:true,ask:true,directory:''}
  try{
    const stored=JSON.parse(fs.readFileSync(file,'utf8'))
    for(const k of Object.keys(prefs)) if(typeof stored[k]===typeof prefs[k]) prefs[k]=stored[k]
  }catch(error){if(error.code!=='ENOENT') console.warn('Desktop preferences reset')}
  let count=0, token=null, generation=0, apnsToken=null, registration=null, changes=null, hasServerCount=false
  const asset=(name)=>nativeImage.createFromPath(path.join(__dirname,'icons',name+'.png'))
  const label=app.getLocale().startsWith('zh')?['打开 Synca','设置','退出','待处理']:['Open Synca','Settings','Quit','pending']
  const tray=process.platform==='win32'?new Tray(asset('tray')):null
  if(tray){
    tray.setContextMenu(Menu.buildFromTemplate([{label:label[0],click:restore},{label:label[1],click:settings},{type:'separator'},{label:label[2],click:()=>app.quit()}]))
    tray.on('click',restore)
  }
  function badge(n){
    count=n
    const visible=prefs.badge?n:0
    if(process.platform==='darwin') app.setBadgeCount(visible)
    if(tray){
      const icon=visible?asset(String(Math.min(visible,100))):null
      window.setOverlayIcon(icon,visible?visible+' '+label[3]:'')
      tray.setImage(icon||asset('tray'));tray.setToolTip(visible?'Synca · '+visible+' '+label[3]:'Synca')
    }
  }
  function save(next){
    fs.writeFileSync(file+'.tmp',JSON.stringify(next),{mode:0o600})
    fs.renameSync(file+'.tmp',file);prefs=next;badge(count)
    return prefs
  }
  const trusted=e=>e.sender===window.webContents && e.senderFrame===e.sender.mainFrame && e.senderFrame.url===HOME+'/'
  function handle(name,fn){ipcMain.handle('desktop:'+name,(e,...args)=>{
    if(!trusted(e)) throw Error('Invalid desktop view')
    return fn(...args)
  })}
  require('./context-menu.cjs').installContextMenus(window, ses, handle, () => token,
    () => prefs.directory && fs.existsSync(prefs.directory) ? prefs.directory : app.getPath('downloads'), cfg)
  handle('preferences',()=>prefs)
  handle('change',(key,value)=>{
    if(!['ask','badge'].includes(key)||typeof value!=='boolean') throw Error('Invalid preference')
    return save({...prefs,[key]:value})
  })
  handle('directory',async()=>{
    const result=await dialog.showOpenDialog(window,{properties:['openDirectory','createDirectory']})
    return result.canceled?prefs:save({...prefs,directory:result.filePaths[0]})
  })
  ipcMain.on('desktop:count',(e,n)=>{
    if(!trusted(e)||!token||!Number.isSafeInteger(n)||n<0)return
    if(!hasServerCount&&window.isVisible())badge(n)
    changes?.hint()
  })
  const clearAvailability=(event,available)=>{
    if(!trusted(event)||typeof available!=='boolean')return
    const item=Menu.getApplicationMenu()?.getMenuItemById('clear-completed')
    if(item)item.enabled=available
  }
  ipcMain.on('desktop:clear-available',clearAvailability)
  window.on('closed',()=>ipcMain.removeListener('desktop:clear-available',clearAvailability))
  function refreshView(){if(window.isVisible()&&!window.isDestroyed())window.webContents.send('desktop:refresh')}
  async function refresh(epoch){
    if(!token||window.isDestroyed()||epoch!==generation)return true
    const response=await ses.fetch(HOME+'/sync/state',{headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(12000),bypassCustomProtocolHandlers:!cfg.local})
    if(epoch!==generation)return true
    if(response.status===401){setSession(null);return true}
    if(!response.ok)return false
    const state=await response.json()
    if(epoch!==generation)return true
    if(!Number.isSafeInteger(state.count)||state.count<0)return false
    hasServerCount=true
    badge(state.count)
    refreshView()
    return true
  }
  async function bindPush(epoch){
    if(!cfg.push||process.platform!=='darwin'||!token)return
    try{
      registration ||= pushNotifications.registerForAPNSNotifications()
      apnsToken=await registration
      if(epoch!==generation||!token)return
      const response=await ses.fetch(HOME+'/me/push-token',{method:'POST',redirect:'error',bypassCustomProtocolHandlers:true,
        headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
        body:JSON.stringify({token:apnsToken,platform:'macos',apnsEnvironment:'production',topic}),signal:AbortSignal.timeout(12000)})
      if(!response.ok)console.warn('Push registration unavailable',response.status)
    }catch{registration=null;console.warn('APNs unavailable for this installation')}
  }
  function setSession(next){
    if(next===token)return
    changes?.stop();changes=null
    generation++;token=next;hasServerCount=false;badge(0)
    const epoch=generation
    if(next)changes=createChangeNotifications({token:next,base:HOME,
      fetcher:(url,options)=>ses.fetch(url,{...options,bypassCustomProtocolHandlers:!cfg.local}),
      onChange:()=>refresh(epoch),onUnauthorized:()=>{if(epoch===generation)setSession(null)}
    })
    if(next)void bindPush(generation)
    else if(apnsToken){pushNotifications.unregisterForAPNSNotifications();apnsToken=null;registration=null}
  }
  ipcMain.on('desktop:session',(e,next)=>{if(trusted(e)&&(next===null||(typeof next==='string'&&next.length<=8192)))setSession(next)})
  if(cfg.push&&process.platform==='darwin')pushNotifications.on('received-apns-notification',()=>{changes?.hint()})
  powerMonitor.on('resume',()=>{changes?.hint()})
  window.on('show',()=>{refreshView();changes?.hint()})
  const pendingDownloads=new Set()
  ses.on('will-download',(_event,item,contents)=>{
    if(contents!==window.webContents)return
    const dir=prefs.directory&&fs.existsSync(prefs.directory)?prefs.directory:app.getPath('downloads')
    const filename=safeFileName(item.getFilename())
    const target=path.join(dir,filename)
    if(prefs.ask||fs.existsSync(target)||pendingDownloads.has(target))item.setSaveDialogOptions({defaultPath:target})
    else {pendingDownloads.add(target);item.once("done",()=>pendingDownloads.delete(target));item.setSavePath(target)}
  })
  app.once('will-quit',()=>{changes?.stop();tray?.destroy()})
}
module.exports={installPlatform}
