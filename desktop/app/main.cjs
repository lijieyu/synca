const { app, BrowserWindow, Menu, dialog, session, shell } = require('electron')
const path = require('node:path')
const {installLocalUI}=require('./local-ui.cjs')
const {installPlatform}=require('./platform.cjs')

const home = 'https://synca.haerth.cn'
const apple = 'https://appleid.apple.com'
let quitting = false
app.on('before-quit',()=>{quitting=true})
const preferences = { sandbox: true, contextIsolation: true, nodeIntegration: false, webviewTag: false }
let mainWindow

function origin(url) {
  return URL.canParse(url) ? new URL(url).origin : ''
}

function restore(){
  if(mainWindow?.isMinimized())mainWindow.restore()
  mainWindow?.show();mainWindow?.focus()
}
function showSettings(){restore();mainWindow?.webContents.send('desktop:settings')}
function createWindow() {
  const window = new BrowserWindow({ title: 'Synca Electron', width: 1040, height: 760,
    ...(process.platform === 'darwin' && {titleBarStyle:'hiddenInset', trafficLightPosition:{x:16,y:14}}),
    minWidth: process.platform === 'darwin' ? 640 : 480, minHeight: process.platform === 'darwin' ? 500 : 400, autoHideMenuBar: true, webPreferences: {...preferences, preload:path.join(__dirname,"preload.cjs")} })
  mainWindow = window
  const page = window.webContents
  page.on('will-navigate', (event, url) => {
    if (![home+'/',home+'/ai'].includes(url)) event.preventDefault()
  })
  page.on('will-redirect', (event, url) => {
    if (![home+'/',home+'/ai'].includes(url)) event.preventDefault()
  })
  page.setWindowOpenHandler(({url}) => {
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
  installPlatform(window,session.defaultSession,restore,showSettings)
  window.on('closed', () => { mainWindow = undefined })
  void window.loadURL(home).catch(() => {})
}

if (!app.requestSingleInstanceLock()) app.quit()
else {
  app.on('second-instance', () => {
    if (!mainWindow && app.isReady()) createWindow()
    restore()
  })
  app.whenReady().then(() => {
    installLocalUI(session.defaultSession)
    app.setAppUserModelId('cn.haerth.synca.electron')
    session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
    session.defaultSession.setPermissionCheckHandler(() => false)
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      {label:process.platform==='darwin'?'Synca Electron':'File',submenu:[
        ...(process.platform==='darwin'?[{role:'about'},{type:'separator'}]:[]),
        {label:app.getLocale().startsWith('zh')?'设置…':'Settings…',accelerator:'CommandOrControl+,',click:showSettings},
        {type:'separator'},{role:'quit'}]},
      {role:'editMenu'}, {label:'View', submenu:[{role:'reload'},{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'}]}, {role:'windowMenu'}
    ]))
    createWindow()
    app.on('activate', () => { if (!mainWindow) createWindow();else restore() })
  })
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
}
