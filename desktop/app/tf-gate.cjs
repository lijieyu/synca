const { pathToFileURL }=require('node:url')
const path=require('node:path')
const origin='https://synca-preview.haerth.cn'
const expectedHost=new URL(origin).hostname
const cookieName='synca_preview_gate'
const options={bypassCustomProtocolHandlers:true,credentials:'include'}
async function gateVerified(ses, home) {
  if(home!==origin)return false
  try{
    const cookies=await ses.cookies.get({url:home+'/',name:cookieName})
    if(!cookies.some(c=>c.name===cookieName&&c.hostOnly&&c.domain===expectedHost&&c.httpOnly&&c.secure&&c.path==='/'&&c.sameSite==='lax'))return false
    const response=await ses.fetch(home+'/health',{...options,redirect:'error',headers:{Accept:'application/json'},signal:AbortSignal.timeout(5000)})
    if(!response.ok)return false
    const body=await response.json()
    return body?.ok===true && body?.service==='synca'
  }catch{return false}
}
async function submitGate(ses,home,username,password) {
  if(home!==origin||typeof username!=='string'||typeof password!=='string'||
    !username||username.length>128||/[:\x00-\x1f\x7f]/.test(username)||
    !password||password.length>256||/[\x00-\x1f\x7f]/.test(password))return false
  try{
    const authorization='Basic '+Buffer.from(username+':'+password,'utf8').toString('base64')
    // Do not forward the password past the one TLS gate request or follow its redirect.
    const response=await ses.fetch(home+'/__preview/unlock',{...options,redirect:'manual',
      headers:{Authorization:authorization,Accept:'text/html'},signal:AbortSignal.timeout(10000)})
    if(![0,200,204,302,303].includes(response.status))return false
    return await gateVerified(ses,home)
  }catch{return false}
}
async function ensureGate(ses,home,api) {
  if(await gateVerified(ses,home))return true
  if(home!==origin)return false
  const localSession=api.session.fromPartition('synca-electron-tf-credential-form')
  const form=path.join(__dirname,'tf-unlock.html')
  const allowed=new Set([pathToFileURL(form).href,pathToFileURL(path.join(__dirname,'tf-unlock-ui.js')).href])
  localSession.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!allowed.has(details.url)}))
  localSession.setPermissionCheckHandler(()=>false)
  localSession.setPermissionRequestHandler((_contents,_name,done)=>done(false))
  const gateWindow=new api.BrowserWindow({title:'Synca | Preview Access',width:450,height:420,resizable:false,
    minimizable:false,maximizable:false,autoHideMenuBar:true,
    webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false,webviewTag:false,devTools:false,spellcheck:false,
      session:localSession,preload:path.join(__dirname,'tf-unlock-preload.cjs')}})
  const contents=gateWindow.webContents
  contents.on('will-navigate',event=>event.preventDefault())
  contents.on('will-redirect',event=>event.preventDefault())
  contents.setWindowOpenHandler(()=>({action:'deny'}))
  return await new Promise(resolve=>{
    const channel='synca-tf:unlock'
    let busy=false, admitted=false
    gateWindow.once('closed',()=>{api.ipcMain.removeHandler(channel);resolve(admitted)})
    api.ipcMain.handle(channel,async(event,u,p)=>{
      if(busy||contents.isDestroyed()||event.sender!==contents||event.senderFrame!==contents.mainFrame||!allowed.has(event.senderFrame.url))return false
      busy=true
      try{
        admitted=await submitGate(ses,home,u,p)
        if(admitted&&!gateWindow.isDestroyed())setImmediate(()=>{if(!gateWindow.isDestroyed())gateWindow.close()})
        return admitted
      }finally{busy=false}
    })
    gateWindow.loadFile(form).catch(()=>{if(!gateWindow.isDestroyed())gateWindow.close()})
  })
}
module.exports={gateVerified,submitGate,ensureGate}
