const { app, BrowserWindow, Menu, dialog, session, shell } = require('electron')
const path = require('node:path')
const fs = require('node:fs')
const { variant } = require('./variant.cjs')
const {installLocalUI}=require('./local-ui.cjs')
const {installPlatform}=require('./platform.cjs')
const {requestInstance}=require('./instance.cjs')

const marker = path.join(__dirname, 'preview-build.json')
const hasMarker = fs.existsSync(marker)
const builtMode = hasMarker ? JSON.parse(fs.readFileSync(marker, 'utf8')).mode : 'production'
if (hasMarker && !['preview', 'local-preview', 'mas-preflight', 'mas-testflight', 'mas-production'].includes(builtMode)) throw Error('Invalid preview marker')
const baseCfg = variant(builtMode)
const cfg = baseCfg.local ? Object.freeze({...baseCfg, readAdmission() {
  const secureFile = path.join(app.getPath('userData'), 'launch-admission')
  const fd = fs.openSync(secureFile, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW)
  try {
    const st = fs.fstatSync(fd)
    if (!st.isFile() || (st.mode & 0o777) !== 0o600 || st.uid !== process.getuid() || st.size > 128)
      throw Error('Invalid local launch admission file')
    const key = fs.readFileSync(fd, 'utf8').trim()
    if (!/^[A-Za-z0-9_-]{32,96}$/.test(key)) throw Error('Invalid local launch admission')
    return key
  } finally { fs.closeSync(fd) }
}}) : baseCfg
const home = cfg.home
if (cfg.profile) {
  const smoke = /^[a-f0-9]{32}$/.test(process.env.SYNCA_PREVIEW_SMOKE_RUN || '') ? process.env.SYNCA_PREVIEW_SMOKE_RUN : ''
  const folder = path.join(app.getPath('appData'), cfg.profile + (smoke ? '-smoke-' + smoke : ''))
  fs.mkdirSync(folder, { recursive: true, mode: 0o700 })
  if (!fs.lstatSync(folder).isDirectory() || fs.realpathSync(folder) !== path.join(fs.realpathSync(app.getPath('appData')), path.basename(folder)))
    throw Error('Desktop profile is not an independent real directory')
  app.setPath('userData', folder)
  app.setPath('sessionData', folder)
}
const apple = 'https://appleid.apple.com'
let quitting = false
app.on('before-quit',()=>{quitting=true})
const preferences = { sandbox: true, contextIsolation: true, nodeIntegration: false, webviewTag: false }
let mainWindow, opening
async function openWorkspace(){
  if(mainWindow)return restore()
  if(!opening)opening=(async()=>{
    if(cfg.gate&&!await require('./tf-gate.cjs').ensureGate(session.defaultSession,home,require('electron')))return
    if(!quitting)createWindow()
  })().finally(()=>{opening=undefined})
  return await opening
}

function origin(url) {
  return URL.canParse(url) ? new URL(url).origin : ''
}

function restore(){
  if(mainWindow?.isMinimized())mainWindow.restore()
  mainWindow?.show();mainWindow?.focus()
}
function showSettings(){restore();mainWindow?.webContents.send('desktop:settings')}
function createWindow() {
  const window = new BrowserWindow({ title: cfg.name, width: 1040, height: 760,
    ...(process.platform === 'darwin' && {titleBarStyle:'hiddenInset', trafficLightPosition:{x:16,y:14}}),
    minWidth: process.platform === 'darwin' ? 640 : 480, minHeight: process.platform === 'darwin' ? 500 : 400, autoHideMenuBar: true, webPreferences: {...preferences, preload:path.join(__dirname,"preload.cjs"), additionalArguments: cfg.offline ? ['--synca-mas-preflight'] : cfg.local ? ['--synca-local-preview'] : cfg.isolated ? ['--synca-internal-preview'] : []} })
  mainWindow = window
  const page = window.webContents
  page.on('will-navigate', (event, url) => {
    if (![home+'/',home+'/ai'].includes(url)) event.preventDefault()
  })
  page.on('will-redirect', (event, url) => {
    if (![home+'/',home+'/ai'].includes(url)) event.preventDefault()
  })
  page.setWindowOpenHandler(({url}) => {
    if (cfg.isolated) return { action: 'deny' }
    if (origin(page.getURL()) !== home) return { action: 'deny' }
    if (origin(url) === apple || url === 'about:blank') {
      return { action: 'allow', overrideBrowserWindowOptions: { width: 560, height: 700, titleBarStyle: 'default', webPreferences: preferences } }
    }
    if (/^https:\/\//.test(url)) shell.openExternal(url).catch(console.error)
    return { action: 'deny' }
  })
  page.on('did-create-window', popup => {
    const guard = (event, url) => {
      if (![home, apple, 'https://account.apple.com'].includes(origin(url))) event.preventDefault()
    }
    popup.webContents.on('will-navigate', guard)
    popup.webContents.on('will-redirect', guard)
    popup.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  })
  page.on('will-prevent-unload', event => {
    const discard = dialog.showMessageBoxSync(window, { type: 'question', message: '放弃尚未保存的编辑？',
      buttons: ['继续编辑', '放弃编辑'], defaultId: 0, cancelId: 0 })
    if (discard === 1) event.preventDefault()
    else quitting=false
  })
  window.on('close', event => { if(!quitting){event.preventDefault();window.hide()} })
  installPlatform(window,session.defaultSession,restore,showSettings,cfg)
  window.on('closed', () => { mainWindow = undefined })
  void window.loadURL(home).catch(() => {})
}

if (!requestInstance(process,builtMode,()=>app.requestSingleInstanceLock())) app.quit()
else {
  app.on('second-instance', () => {
    if (app.isReady()) void openWorkspace()
  })
  app.whenReady().then(() => {
    installLocalUI(session.defaultSession,cfg)
    if (cfg.isolated) session.defaultSession.webRequest.onBeforeRequest((details, done) =>
      done({ cancel: !cfg.allows(details.url) && !/^(?:data|blob|devtools):/.test(details.url) }))
    app.setAppUserModelId(cfg.bundleId)
    session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
    session.defaultSession.setPermissionCheckHandler(() => false)
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      {label:process.platform==='darwin'?cfg.name:'File',submenu:[
        ...(process.platform==='darwin'?[{role:'about'},{type:'separator'}]:[]),
        {label:app.getLocale().startsWith('zh')?'设置…':'Settings…',accelerator:'CommandOrControl+,',click:showSettings},
        ...(process.platform==='darwin'?[{type:'separator'},{role:'hide'},{role:'hideOthers'},{role:'unhide'}]:[]),
        ...(process.platform!=='darwin'?[{role:'close'}]:[]),
        {type:'separator'},{role:'quit'}]},
      ...(process.platform==='darwin'?[{label:'File',submenu:[{role:'close'}]}]:[]),
      {role:'editMenu'}, {label:'View', submenu:[{label:app.getLocale().startsWith('zh')?'同步':'Sync',accelerator:'CommandOrControl+R',click:()=>mainWindow?.webContents.send('desktop:sync')},{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'}]}, {role:'windowMenu'}
    ]))
    void openWorkspace()
    app.on('activate', () => { void openWorkspace() })
  })
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
}
