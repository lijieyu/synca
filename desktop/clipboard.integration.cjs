// Run with node_modules/.bin/electron clipboard.integration.cjs.
// Uses an isolated session and synthetic data; never reads pre-existing clipboard contents.
const {app, BrowserWindow, clipboard, ipcMain, nativeImage, session} = require('electron')
const assert = require('node:assert/strict')
const path = require('node:path')
const os = require('node:os')
const fs = require('node:fs')
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'synca-clipboard-test-'))
app.setPath('userData', profile)
const home = 'https://synca-testflight.invalid'
let window, wrote = false
app.whenReady().then(async () => {
  const ses = session.fromPartition('clipboard-regression')
  ses.setPermissionRequestHandler((_w, _p, cb) => cb(false))
  ses.setPermissionCheckHandler(() => false)
  const image = nativeImage.createFromBitmap(Buffer.from([0,0,255,255]), {width:1,height:1})
  assert.equal(image.isEmpty(), false)
  ses.protocol.handle('https', request => new Response(request.url.endsWith('/api/media/test.png') ? image.toPNG() : '<html><body>Clipboard regression fixture</body></html>', {headers:{'Content-Type':request.url.endsWith('.png')?'image/png':'text/html'}}))
  window = new BrowserWindow({show:true, width:400, height:200, webPreferences:{session:ses, preload:path.join(__dirname,'app/preload.cjs'), contextIsolation:true, sandbox:true, additionalArguments:['--synca-mas-preflight']}})
  let token = 'synthetic-session'
  const handle = (name, fn) => ipcMain.handle('desktop:'+name, (e, ...args) => {
    assert.equal(e.sender, window.webContents)
    assert.equal(e.senderFrame, e.sender.mainFrame)
    assert.equal(e.senderFrame.url, home+'/')
    return fn(...args)
  })
  require('./app/context-menu.cjs').installContextMenus(window, ses, handle, () => token, () => profile, {home, local:true})
  await window.loadURL(home)
  window.focus()
  const denied = await window.webContents.executeJavaScript("navigator.clipboard.writeText('blocked').then(()=>false,e=>e.name)", true)
  assert.equal(denied, 'NotAllowedError')
  console.log('PASS: reproduced browser clipboard permission denial')
  const bridge = await window.webContents.executeJavaScript('typeof window.syncaDesktop.copyRecord')
  assert.equal(bridge, 'function', 'Copy buttons need a native clipboard bridge')
  wrote = true
  await window.webContents.executeJavaScript("window.syncaDesktop.copyRecord({text:'中文复制 🙂\\n**Markdown source**'})")
  assert.equal(await clipboard.readText(), '中文复制 🙂\n**Markdown source**')
  console.log('PASS: native text copy preserves Chinese, emoji, newline and Markdown')
  await window.webContents.executeJavaScript("window.syncaDesktop.copyRecord({attachment:{url:'/api/media/test.png',kind:'image'}})")
  assert.equal(await clipboard.has('image/png'), true)
  console.log('PASS: native image copy produces a PNG')
  for (const attachment of [{url:'https://other.invalid/api/media/test.png',kind:'image'}, {url:'/api/media/test.png',kind:'image',expiresAt:'2000-01-01'}, {url:'/api/media/test.png',kind:'file'}]) {
    assert.equal(await window.webContents.executeJavaScript(`window.syncaDesktop.copyRecord(${JSON.stringify({attachment})}).then(()=>false,()=>true)`), true)
  }
  token = null
  assert.equal(await window.webContents.executeJavaScript("window.syncaDesktop.copyRecord({attachment:{url:'/api/media/test.png',kind:'image'}}).then(()=>false,()=>true)"), true)
  await window.webContents.executeJavaScript("window.syncaDesktop.copyRecord({text:'offline text'})")
  assert.equal(await clipboard.readText(), 'offline text')
  console.log('PASS: external, expired, non-image and signed-out image copies rejected; offline text works')
}).catch(error => {console.error(error); process.exitCode=1}).finally(async () => {
  if (wrote) clipboard.clear()
  window?.destroy()
  fs.rmSync(profile,{recursive:true,force:true})
  app.exit(process.exitCode || 0)
})
app.on('will-quit',()=>fs.rmSync(profile,{recursive:true,force:true}))
