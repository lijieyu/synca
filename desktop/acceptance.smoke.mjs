// Requires the loopback acceptance-server.ts fixture and build:ui. Never contacts production.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import assert from 'node:assert/strict';import {randomBytes} from 'node:crypto';
import {_electron} from 'playwright-core';
const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-acceptance-ui-'));const out=process.env.SYNCA_CAPTURE_DIR||path.join(stage,'shots');await fs.mkdir(out,{recursive:true});
await fs.cp(new URL('./app/',import.meta.url),stage,{recursive:true});await fs.writeFile(path.join(stage,'preview-build.json'),JSON.stringify({mode:'mas-preflight'}));
await fs.writeFile(path.join(stage,'acceptance-entry.cjs'),"globalThis.acceptanceRuntime={fs:require('node:fs/promises'),path:require('node:path'),localUI:require('./local-ui.cjs')};require('./main.cjs');");
const metadata=JSON.parse(await fs.readFile(path.join(stage,'package.json'),'utf8'));await fs.writeFile(path.join(stage,'package.json'),JSON.stringify({...metadata,main:'acceptance-entry.cjs'}));
await fs.writeFile(path.join(stage,'preload.cjs'),(await fs.readFile(path.join(stage,'preload.cjs'),'utf8')).replace("...(!preview && !process.windowsStore && !process.argv.includes('--synca-store') ? {updateState:", '...(true ? {updateState:'));
let app,profile;
try{
 app=await _electron.launch({args:[stage],env:{...process.env,SYNCA_PREVIEW_SMOKE_RUN:randomBytes(16).toString('hex')}});const page=await app.firstWindow();await app.evaluate(({ipcMain})=>{globalThis.acceptanceUpdate={phase:'idle'};ipcMain.handle('desktop:update-state',()=>globalThis.acceptanceUpdate);ipcMain.handle('desktop:update-action',()=>globalThis.acceptanceAction??({phase:'ready',version:'1.2.2'}));});page.setDefaultTimeout(10000);profile=await app.evaluate(({app})=>app.getPath('userData'));
 await app.evaluate(async({session},renderer)=>{
  const {fs,path,localUI}=globalThis.acceptanceRuntime;await session.defaultSession.protocol.unhandle('https');
  await session.defaultSession.protocol.handle('https',async req=>{
   const url=new URL(req.url);if(url.origin!=='https://synca-testflight.invalid')return new Response(null,{status:403});
   if(url.pathname==='/'||url.pathname.startsWith('/assets/')||url.pathname==='/logo.png'){
    try{return new Response(await fs.readFile(path.join(renderer,url.pathname==='/'?'index.html':url.pathname.slice(1))),{headers:{'Content-Type':url.pathname==='/'?'text/html':url.pathname.endsWith('.js')?'text/javascript':url.pathname.endsWith('.css')?'text/css':'image/png'}});}catch{return new Response(null,{status:404});}
   }
   const headers=new Headers(req.headers);
   const response=await fetch('http://127.0.0.1:54671'+url.pathname+url.search,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:await req.arrayBuffer(),redirect:'error'});
   return localUI.localMediaResponse(response,{upstream:'http://127.0.0.1:54671',home:url.origin});
  });
 },path.join(stage,'renderer'));
 await page.evaluate(()=>{localStorage.setItem('authToken','visual-fixture');localStorage.setItem('userId','visual-fixture');localStorage.setItem('userEmail','demo@example.invalid');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.appearance','light');});
 await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setSize(1120,800));await page.reload();await page.locator('[data-message-id]').first().waitFor();
 await app.evaluate(({BrowserWindow})=>{globalThis.acceptanceUpdate={phase:'available',version:'1.2.2'};globalThis.acceptanceAction={phase:'error'};BrowserWindow.getAllWindows()[0].webContents.send('desktop:update')});
 await page.getByRole('button',{name:'下载更新',exact:true}).click();await page.locator('.update-notice').getByRole('button',{name:'检查更新',exact:true}).waitFor();await page.screenshot({path:path.join(out,'desktop-update-failure-retry.png')});
 await app.evaluate(({BrowserWindow})=>{globalThis.acceptanceUpdate={phase:'idle'};globalThis.acceptanceAction=null;BrowserWindow.getAllWindows()[0].webContents.send('desktop:update')});
 await page.getByRole('button',{name:'收藏',exact:true}).click();await page.locator('.collection-filter').waitFor();await page.screenshot({path:path.join(out,'desktop-collections-light.png')});
 await page.locator('.search-trigger').click();await page.locator('input[type=search]').fill('项目资料');await page.locator('.message-search-result').first().waitFor();assert.equal(await page.locator('.message-search-result').first().getByText('收藏',{exact:true}).count(),1);await page.screenshot({path:path.join(out,'desktop-collection-search.png')});await page.locator('.message-search-result').first().click();await page.locator('.collection-filter').waitFor();
 assert.equal(await page.locator('.input-bar textarea').count(),1);await page.locator('.input-bar textarea').fill('验收：收藏独立新增');await page.locator('.input-bar textarea').press('Enter');await page.getByText('验收：收藏独立新增',{exact:true}).first().waitFor();
 await page.getByRole('button',{name:'草稿本',exact:true}).click();const editor=page.locator('.scratchpad textarea');await editor.waitFor();await page.waitForFunction(()=>document.querySelector('.scratchpad textarea')?.value.includes('随时接着写'));
 assert.equal(await page.locator('.input-bar textarea').count(),0);await page.screenshot({path:path.join(out,'desktop-scratch-edit.png')});
 const content=(await editor.inputValue()).split('\n\n桌面端验收')[0]+'\n\n桌面端验收：自动保存成功。';await editor.fill(content);await page.waitForFunction(async expected=>{const r=await fetch('/scratchpad',{headers:{Authorization:'Bearer visual-fixture'}});return (await r.json()).content===expected;},content);
 await page.getByRole('button',{name:'预览',exact:true}).click();await page.getByText('已同步',{exact:true}).waitFor();await page.screenshot({path:path.join(out,'desktop-scratch-preview.png')});
 await page.getByRole('button',{name:'编辑',exact:true}).click();await page.locator('.scratchpad input[type=file]').setInputFiles({name:'验收图片.png',mimeType:'image/png',buffer:await fs.readFile(new URL('./app/renderer/logo.png',import.meta.url))});
 await page.waitForFunction(()=>document.querySelector('.scratchpad textarea')?.value.includes('synca-image:'));await page.getByRole('button',{name:'预览',exact:true}).click();await page.waitForFunction(()=>[...document.querySelectorAll('.scratch-preview img')].some(image=>image.naturalWidth>0)).catch(async error=>{console.log(JSON.stringify(await page.evaluate(async()=>({images:await (await fetch('/scratchpad/images',{headers:{Authorization:'Bearer visual-fixture'}})).json(),html:document.querySelector('.scratch-preview')?.innerHTML}))));throw error;});await page.getByText('已同步',{exact:true}).waitFor();
 const menu=await app.evaluate(({Menu})=>Menu.getApplicationMenu().getMenuItemById('clear-completed').enabled);assert.equal(menu,false);
 await page.evaluate(()=>localStorage.setItem('synca.appearance','dark'));await page.reload();await page.getByRole('button',{name:'收藏',exact:true}).click();await page.locator('.collection-filter').waitFor();await page.screenshot({path:path.join(out,'desktop-collections-dark.png')});
 await page.locator('.account-entry').click();await page.locator('.account-menu-panel').waitFor();assert.equal(await page.locator('.account-menu-panel .identity-avatar').count(),0);await page.screenshot({path:path.join(out,'desktop-account-menu.png')});await page.keyboard.press('Escape');
 await page.locator('.settings-entry').click();await page.getByRole('button',{name:'通用',exact:true}).click();await page.screenshot({path:path.join(out,'desktop-capture-settings.png')});
 await page.keyboard.press('Escape');await app.evaluate(({BrowserWindow})=>{globalThis.acceptanceUpdate={phase:'available',version:'1.2.2',store:true};BrowserWindow.getAllWindows()[0].webContents.send('desktop:update');});await page.locator('.update-notice').first().waitFor();await page.screenshot({path:path.join(out,'desktop-store-update-fixture.png')});
 await app.evaluate(({BrowserWindow})=>{globalThis.acceptanceUpdate={phase:'ready',version:'1.2.2',store:false};BrowserWindow.getAllWindows()[0].webContents.send('desktop:update');});await page.getByRole('button',{name:'重启并安装',exact:true}).waitFor();const colors=await page.getByRole('button',{name:'重启并安装',exact:true}).evaluate(el=>({text:getComputedStyle(el).color,background:getComputedStyle(el).backgroundColor}));assert.notEqual(colors.text,colors.background);assert.notEqual(colors.background,'rgba(0, 0, 0, 0)');await page.screenshot({path:path.join(out,'desktop-windows-ready-ui-fixture.png')});
 console.log('PASS real backend: collections create/filter, scratch load/autosave/preview, hidden clear menu; light/dark screenshots');
}finally{if(app)await app.close();if(profile&&profile.includes('smoke'))await fs.rm(profile,{recursive:true,force:true});await fs.rm(stage,{recursive:true,force:true});}
