const { _electron: electron } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright-core')
import assert from 'node:assert/strict'
import path from 'node:path'
import fs from 'node:fs/promises'
import os from 'node:os'
import { randomUUID } from 'node:crypto'
import { setTimeout as pause } from 'node:timers/promises'

const webRoot=path.resolve(process.env.SYNCA_WEB || '../web')
const backend = path.resolve(process.env.SYNCA_BACKEND, 'dist/src')
const executablePath = path.resolve(process.argv[2])
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'synca-electron-qa-'))
const capture=path.resolve(process.env.CAPTURE_DIR || temp)
process.chdir(temp)
await fs.cp(path.resolve(backend, '../../certs/apple'), path.join(temp, 'certs/apple'), {recursive:true})
process.env.DB_PATH = path.join(temp, 'qa.sqlite')
const { default: api } = await import(path.join(backend, 'app.js'))
const { runMigrations } = await import(path.join(backend, 'migrate.js'))
const { db } = await import(path.join(backend, 'db.js'))
const { createSession } = await import(path.join(backend, 'store.js'))
await runMigrations()
const id = randomUUID(), token = randomUUID(), now = new Date().toISOString()
await db.insertInto('users').values({ id, apple_user_id:id, email:'qa@example.invalid', nickname:'QA', created_at:now,
  updated_at:now,trial_started_at:now,trial_ends_at:new Date(Date.now()+86400000).toISOString() }).execute()
await createSession(token,id)
const server = api.listen(0,'127.0.0.1')
await new Promise(resolve=>server.once('listening', resolve))
let backendReads = 0
server.on('request', request => { if (request.method === 'GET' && request.url === '/messages') backendReads++ })
const local = 'http://127.0.0.1:' + server.address().port
let app
try {
  app = await electron.launch({executablePath, args:['--user-data-dir='+path.join(temp,'profile')]})
  const page = await app.firstWindow()
  const home = 'https://synca.haerth.cn'
  const context = page.context()
  const calls = []
  page.setDefaultTimeout(12000)
  page.on('pageerror',e=>console.log('renderer error',e.message))
  await app.evaluate(({session},base)=>{
    const ses=session.defaultSession, original=ses.fetch.bind(ses)
    ses.fetch=(input,options)=>{
      const url=new URL(typeof input==='string'?input:input.url)
      if(url.origin==='https://synca.haerth.cn' && /^\/(?:messages|me|message-categories)(?:\/|$)/.test(url.pathname)){
        if(globalThis.qaOffline) throw TypeError('offline')
        const init=typeof input==='string'?options:{method:input.method,headers:input.headers,
          body:['GET','HEAD'].includes(input.method)?undefined:input.body,duplex:'half'}
        return original(base+url.pathname+url.search,init)
      }
      return original(input,options)
    }
  },local)
  await page.goto(home)
  await page.locator('#appleid-signin').waitFor({state:'attached'})
  console.log('Bundled login view loaded', await app.evaluate(({ app })=>[app.getVersion(),app.getPath('userData')]))
  await context.route('**/*', async route=>{
    const request = route.request(), url = new URL(request.url())
    if(url.origin!==home) return route.abort()
    if(/^\/(messages|message-categories|me)(\/|$)/.test(url.pathname)){
      calls.push(request.method()+' '+url.pathname)
      const response = await route.fetch({url:local+url.pathname+url.search,maxRedirects:0})
      return route.fulfill({response})
    }
    if(request.method()==='GET' && !request.headers().authorization && (url.pathname==='/' || /^\/(assets\/|logo\.png|favicon\.png)/.test(url.pathname))) return route.continue()
    return route.abort()
  })
  await page.evaluate(t=>{localStorage.setItem('authToken',t);localStorage.setItem('synca.language','zh-Hans')},token)
  await page.reload()
  const input=page.locator('textarea').first()
  console.log('desktop bundle',await page.evaluate(()=>[typeof window.syncaDesktop,document.querySelector('script[type=module]')?.src]))
  if (process.platform === 'darwin') {
    await app.evaluate(({BrowserWindow}) => {
      const window = BrowserWindow.getAllWindows()[0]
      window.setSize(...window.getMinimumSize())
    })
    await page.waitForFunction(() => innerWidth === 640 && innerHeight === 500)
    const sidebar = await page.locator('.calm-sidebar').boundingBox()
    const header = await page.locator('.calm-main .header').boundingBox()
    assert.equal(sidebar.height, 500)
    assert.equal(header.y, 0)
    assert(header.height >= 80)
  }
  await input.fill('未完成的草稿')
  await page.locator('.settings-entry').click()
  const settings=page.locator('.desk-settings')
  await settings.waitFor()
  assert.equal(await page.locator('.desk-workspace').evaluate(element => element.inert), true)
  await settings.getByRole('button',{name:'通用',exact:true}).click()
  await settings.locator('select').first().selectOption('dark')
  await page.screenshot({path:path.join(capture,'Settings-Dark.png')})
  await settings.locator('select').first().selectOption('light')
  await page.screenshot({path:path.join(capture,'Settings-General.png')})
  await settings.getByRole('button',{name:'桌面',exact:true}).click()
  const badgeSwitch=settings.getByRole('switch').first()
  await badgeSwitch.uncheck()
  await page.waitForFunction(async()=>!(await window.syncaDesktop.preferences()).badge)
  await badgeSwitch.check()
  await page.screenshot({path:path.join(capture,'Settings-Desktop.png')})
  await app.evaluate(({dialog},directory)=>{dialog.showOpenDialog=async()=>({canceled:false,filePaths:[directory]})},temp)
  await settings.getByRole('button',{name:'选择…'}).click()
  await settings.getByText(temp,{exact:true}).waitFor()
  await settings.getByRole('switch').nth(1).uncheck()
  await page.waitForFunction(async()=>!(await window.syncaDesktop.preferences()).ask)
  await page.evaluate(()=>{
    const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['Synca desktop download']));a.download='settings-qa.txt';document.body.append(a);a.click();a.remove()
  })
  for(let i=0;i<30;i++){if(await fs.stat(path.join(temp,'settings-qa.txt')).catch(()=>null))break;await pause(200)}
  assert.equal(await fs.readFile(path.join(temp,'settings-qa.txt'),'utf8'),'Synca desktop download')
  await settings.getByRole('button',{name:/账号与套餐/}).click()
  await settings.getByText('qa@example.invalid',{exact:true}).waitFor()
  await settings.getByRole('button',{name:'关于',exact:true}).click()
  await settings.getByText(/macOS · 1.2.0/).waitFor()
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setSize(640,500))
  await settings.getByRole('button',{name:'通用',exact:true}).click()
  await settings.locator('select').nth(1).selectOption('en')
  await settings.getByRole('button',{name:'Desktop',exact:true}).click()
  assert(await settings.evaluate(el=>el.scrollWidth<=el.clientWidth))
  await page.screenshot({path:path.join(capture,'Settings-Narrow.png')})
  await settings.getByRole('button',{name:'General',exact:true}).click()
  await settings.locator('select').nth(1).selectOption('zh-Hans')
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setSize(1040,760))
  await settings.locator('.settings-title button').click()
  assert.equal(await input.inputValue(),'未完成的草稿')
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].close())
  assert.equal(await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].isVisible()),false)
  await app.evaluate(({app})=>app.emit('activate'))
  assert.equal(await input.inputValue(),'未完成的草稿')
  await page.reload();assert.equal(await input.inputValue(),'未完成的草稿')
  let refreshNavigation = 0
  const countNavigation = () => { refreshNavigation++ }
  page.on('framenavigated', countNavigation)
  const beforeSyncCalls = backendReads
  await app.evaluate(({Menu}) => {
    const sync = Menu.getApplicationMenu().items.flatMap(item=>item.submenu?.items||[]).find(item=>item.accelerator==='CommandOrControl+R')
    if (!sync) throw Error('Missing native sync shortcut')
    sync.click()
  })
  await page.getByText('同步成功',{exact:true}).waitFor()
  assert.equal(refreshNavigation,0)
  assert.equal(await input.inputValue(),'未完成的草稿')
  assert(backendReads>beforeSyncCalls)
  page.removeListener('framenavigated',countNavigation)
  await page.getByText('同步成功',{exact:true}).waitFor({state:'hidden'})
  const beforeBackgroundSync = backendReads
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].webContents.send('desktop:refresh'))
  for(let i=0;i<30 && backendReads===beforeBackgroundSync;i++) await pause(100)
  assert(backendReads>beforeBackgroundSync)
  await pause(300)
  assert.equal(await page.getByText('同步成功',{exact:true}).count(),0)
  assert.equal(await input.inputValue(),'未完成的草稿')
  console.log('Settings dialog, sync shortcut, native preferences, close/hide and relaunch draft passed')
  await input.fill('牛奶采购')
  await input.dispatchEvent('keydown',{key:'Enter',isComposing:true,keyCode:229})
  assert.equal(await input.inputValue(),'牛奶采购')
  assert(!calls.includes('POST /messages'))
  await input.press('Shift+Enter')
  await page.keyboard.insertText('第二行 🥛')
  await input.press('Enter')
  const row=page.locator('[data-message-id]').first()
  await row.waitFor()
  const messageId=await row.getAttribute('data-message-id')
  const headers={authorization:'Bearer '+token,'content-type':'application/json'}
  const list=async()=> (await (await fetch(local+'/messages',{headers})).json()).messages
  assert.equal((await list())[0].textContent,'牛奶采购\n第二行 🥛')
  // Drive the actual contextmenu event and select from the native Menu built by the app.
  // Selecting by item ID keeps this check independent of host language and menu animations.
  async function selectRecordAction(id) {
    await app.evaluate(({Menu}, id) => {
      const original = Menu.prototype.popup
      Menu.prototype.popup = function (options) {
        Menu.prototype.popup = original
        const item = this.getMenuItemById(id)
        if (item?.enabled) item.click(undefined, options.window)
        options.callback?.()
      }
    }, id)
    await row.locator('.message-header').click({button:'right', position:{x:3,y:3}})
  }
  await selectRecordAction('delete')
  await page.getByRole('dialog').getByRole('button',{name:'取消',exact:true}).click()
  assert.equal((await list())[0].id, messageId)
  await selectRecordAction('edit')
  const editor=page.locator('.message-editor-input')
  await editor.fill('牛奶已采购 🥛')
  await editor.press('Control+Enter')
  await editor.waitFor({state:'detached'})
  const [saved]=await list()
  assert.equal(saved.id,messageId)
  assert.equal(saved.textContent,'牛奶已采购 🥛')
  await page.keyboard.press('Tab')
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+f' : 'Control+f')
  const searchBox = page.getByRole('searchbox')
  await searchBox.waitFor()
  assert(await searchBox.evaluate(el => el === document.activeElement && getComputedStyle(el).outlineStyle === 'none'))
  await searchBox.fill('牛奶')
  assert.equal(await page.locator('.message-search-result mark').first().innerText(),'牛奶')
  await page.locator('.message-search-result').first().click()
  await page.locator('[data-message-id].search-target').waitFor()
  const edit=await fetch(local+'/messages/'+messageId+'/text',{method:'PATCH',headers,
    body:JSON.stringify({textContent:'来自第二客户端',expectedUpdatedAt:saved.updatedAt})})
  assert.equal(edit.status,200)
  await row.getByText('来自第二客户端').waitFor({timeout:30000})
  assert.equal(await app.evaluate(({app})=>app.getBadgeCount()),1)
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].close())
  const second=await fetch(local+'/messages',{method:'POST',headers,body:JSON.stringify({textContent:'后台角标'})})
  assert.equal(second.status,201)
  for(let i=0;i<38;i++){
    if(await app.evaluate(({app})=>app.getBadgeCount())===2)break
    await pause(1000)
  }
  assert.equal(await app.evaluate(({app})=>app.getBadgeCount()),2)
  await app.evaluate(({app})=>app.emit('activate'))
  await page.locator('[data-message-id]').getByText('后台角标',{exact:true}).waitFor()
  await app.evaluate(({Menu})=>{
    const item=Menu.getApplicationMenu().items.flatMap(i=>i.submenu?.items||[]).find(i=>i.accelerator==='CommandOrControl+,')
    item.click()
  })
  await settings.getByRole('button',{name:'桌面',exact:true}).click()
  await badgeSwitch.uncheck()
  await page.waitForFunction(async()=>!(await window.syncaDesktop.preferences()).badge)
  assert.equal(await app.evaluate(({app})=>app.getBadgeCount()),0)
  await badgeSwitch.check()
  await settings.locator('.settings-title button').click()
  console.log('Native menu, download folder, hidden window sync and Dock badge toggle passed')
  const {default: verifySharedUI} = await import(path.join(webRoot,'tests/shared-settings-markdown.browser.js'))
  await verifySharedUI(page,{desktop:true,screenshot:path.join(capture,'Electron-Markdown.png')})
  console.log('Packaged shared settings and Markdown edit/persist flow passed')
  await app.evaluate(()=>{globalThis.qaOffline=true})
  await context.route('**/messages',route=>route.abort('internetdisconnected'))
  await context.route('**/message-categories',route=>route.abort('internetdisconnected'))
  await page.reload()
  await page.locator('[data-message-id]').getByText('来自第二客户端',{exact:true}).waitFor()
  console.log('Offline cached records and native Mac badge passed')
  const samples=[]
  for(let i=0;i<6;i++) {
    await pause(2000)
    samples.push(await app.evaluate(({app})=>app.getAppMetrics().map(m=>({type:m.type,cpu:m.cpu.percentCPUUsage,rssKiB:m.memory.workingSetSize}))))
  }
  console.log(JSON.stringify({input:true,edit:true,search:true,bidirectionalSync:true,samples}))
} finally {
  if(app) await app.close()
  await new Promise(resolve=>server.close(resolve))
  await db.destroy()
}
