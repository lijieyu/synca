// Local-only Electron smoke test. Requires `node build-ui.mjs` first.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
const { _electron } = await import(process.env.PLAYWRIGHT_MODULE || './node_modules/playwright-core/index.mjs');
const run = randomBytes(16).toString('hex');
const stage = await fs.mkdtemp(path.join(os.tmpdir(), 'synca-keyboard-smoke-'));
const out = process.env.SYNCA_CAPTURE_DIR || path.join(stage, 'screenshots');
await fs.mkdir(out, {recursive:true});
await fs.cp(new URL('./app/', import.meta.url), stage, {recursive:true});
await fs.writeFile(path.join(stage, 'preview-build.json'), JSON.stringify({mode:'mas-preflight'}));
await fs.writeFile(path.join(stage, 'smoke-entry.cjs'), "globalThis.smokeRuntime={fs:require('node:fs/promises'),path:require('node:path')};require('./main.cjs');\n");
const metadata=JSON.parse(await fs.readFile(path.join(stage,'package.json'),'utf8'));
await fs.writeFile(path.join(stage,'package.json'),JSON.stringify({...metadata,main:'smoke-entry.cjs'}));
let app, profile;
try {
  app = await _electron.launch({executablePath:process.env.ELECTRON_PATH, args:[stage], env:{...process.env,SYNCA_PREVIEW_SMOKE_RUN:run}});
  const page = await app.firstWindow();
  page.setDefaultTimeout(8000);
  profile = await app.evaluate(({app}) => app.getPath('userData'));
  // Replace the offline transport with an entirely in-memory fixture. No outgoing requests.
  await app.evaluate(async ({session}, renderer) => {
    const {fs,path} = globalThis.smokeRuntime;
    const stamp='2026-11-24T00:00:00Z';
    const categories=[{id:'inbox',name:'默认',isDefault:true,color:'slate',sortOrder:0},{id:'work',name:'工作',color:'sky',sortOrder:1}].map(c=>({...c,createdAt:stamp,updatedAt:stamp}));
    let messages=[{id:'done',categoryId:'work',textContent:'整理本周的灵感记录',isCleared:true},{id:'pending',categoryId:'work',textContent:'把重要的想法留下来',isCleared:false}].map(m=>({...m,type:'text',isDeleted:false,createdAt:stamp,updatedAt:stamp}));
    globalThis.shortcutSmoke={deletes:[]};
    await session.defaultSession.protocol.unhandle('https');
    await session.defaultSession.protocol.handle('https', async req => {
      const url=new URL(req.url), p=url.pathname;
      if(url.origin!=='https://synca-testflight.invalid')return new Response(null,{status:403});
      if(p==='/messages/delete-completed'){
        const body=await req.json();globalThis.shortcutSmoke.deletes.push(body);
        messages=messages.filter(m=>!(m.isCleared&&(!body.categoryId||m.categoryId===body.categoryId)));
        return Response.json({ok:true});
      }
      if(p==='/messages')return Response.json({messages});
      if(p==='/message-categories')return Response.json({categories});
      if(p==='/me/access-status')return Response.json({email:'demo@example.invalid',accessStatus:{plan:'unlimited',isUnlimited:true,isTrial:false,todayUsed:2,todayLimit:null}});
      if(p.startsWith('/me/')||p.startsWith('/api/'))return Response.json({connections:[],operations:[],links:[]});
      if(p==='/'||/^\/assets\/[\w.-]+$/.test(p)||p==='/logo.png'){
        const file=p==='/'?'index.html':p.slice(1);
        const type={'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png'}[path.extname(file)];
        try{return new Response(await fs.readFile(path.join(renderer,file)),{headers:{'Content-Type':type||'application/octet-stream'}});}catch{return new Response(null,{status:404});}
      }
      return new Response(null,{status:404});
    });
  }, path.join(stage,'renderer'));
  await page.evaluate(() => {
    localStorage.setItem('authToken','offline-keyboard-fixture');
    localStorage.setItem('userEmail','demo@example.invalid');
    localStorage.setItem('synca.language','zh-Hans');
    localStorage.setItem('synca.appearance','light');
  });
  await page.reload();
  await page.locator('[data-message-id=pending]').waitFor();
  const native = fn => app.evaluate(fn);
  await page.locator('.settings-entry').click();
  await page.getByRole('button',{name:'通用',exact:true}).click();
  const layout = () => page.locator('.settings-general').evaluate(el=>({height:el.clientHeight,content:el.scrollHeight,width:el.clientWidth,contentWidth:el.scrollWidth}));
  for(const [name,width,height,theme,language] of [
    ['mac-general-light',1040,760,'light','zh-Hans'],
    ['mac-general-dark',1040,760,'dark','zh-Hans'],
    ['mac-general-minimum',640,500,'dark','zh-Hans'],
    ['mac-general-minimum-english',640,500,'light','en'],
  ]){
    await app.evaluate(({BrowserWindow},{width,height})=>BrowserWindow.getAllWindows()[0].setSize(width,height),{width,height});
    await page.evaluate(({theme,language})=>{localStorage.setItem('synca.appearance',theme);localStorage.setItem('synca.language',language);},{theme,language});
    await page.reload();await page.locator('[data-message-id=pending]').waitFor();
    await page.locator('.settings-entry').click();
    await page.getByRole('button',{name:language==='en'?'General':'通用',exact:true}).click();
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const size=await layout();assert(size.content<=size.height+1,`${name} overflow: ${JSON.stringify(size)}`);
    assert(size.contentWidth<=size.width+1);
    await page.screenshot({path:path.join(out,name+'.png')});
    console.log('PASS layout',name,size);
  }
  await page.keyboard.press('Escape');
  await page.locator('[data-category-id=work]').click();
  const composer=page.locator('.input-bar textarea');await composer.fill('不要丢失我的草稿');
  const menuState=()=>native(({Menu})=>{const item=Menu.getApplicationMenu().getMenuItemById('clear-completed');return {enabled:item.enabled,accelerator:item.accelerator};});
  assert.equal((await menuState()).enabled,true);
  for(const extra of [{isComposing:true},{isAutoRepeat:true}]) {
    const prevented=await app.evaluate(({BrowserWindow},extra)=>{
      let prevented=false;
      BrowserWindow.getAllWindows()[0].webContents.emit('before-input-event',{preventDefault(){prevented=true;}},{type:'keyDown',key:'Backspace',meta:true,shift:true,control:false,alt:false,...extra});
      return prevented;
    },extra);
    assert.equal(prevented,true,'native accelerator must be suppressed during IME/repeat');
    assert.equal(await page.getByRole('dialog').count(),0);
  }
  await native(({BrowserWindow})=>{const w=BrowserWindow.getAllWindows()[0];w.show();w.focus();w.webContents.sendInputEvent({type:'keyDown',keyCode:'Backspace',modifiers:['meta','shift']});w.webContents.sendInputEvent({type:'keyUp',keyCode:'Backspace',modifiers:['meta','shift']});});
  await page.locator('.modal-btn-destructive').waitFor();
  assert.equal((await native(()=>globalThis.shortcutSmoke.deletes)).length,0);
  await page.keyboard.press('Escape');assert.equal(await composer.inputValue(),'不要丢失我的草稿');
  await native(({Menu})=>Menu.getApplicationMenu().getMenuItemById('clear-completed').click());
  await page.locator('.modal-btn-destructive').waitFor();
  await page.screenshot({path:path.join(out,'mac-clear-confirmation.png')});
  await page.locator('.modal-btn-destructive').click();
  await page.locator('[data-message-id=done]').waitFor({state:'detached'});
  assert.deepEqual(await native(()=>globalThis.shortcutSmoke.deletes),[{categoryId:'work'}]);
  assert.equal((await menuState()).enabled,false);
  await native(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].webContents.sendInputEvent({type:'keyDown',keyCode:'Backspace',modifiers:['meta','shift']}));
  assert.equal(await page.getByRole('dialog').count(),0);
  console.log('PASS native key and menu open confirmation; scoped clearing updates list and disables menu');
  // Zoomed text must stay reachable without horizontal clipping.
  await page.locator('.settings-entry').click();await page.getByRole('button',{name:'General',exact:true}).click();
  await native(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].webContents.setZoomFactor(1.25));
  await page.getByRole('button',{name:'Done',exact:true}).waitFor();
  await page.locator('.settings-shortcuts dd').last().scrollIntoViewIfNeeded();
  assert(await page.locator('.settings-shortcuts dd').last().isVisible());
  assert(await page.locator('.desk-detail-body:visible').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
  console.log('PASS narrow/zoomed settings remain reachable');
} finally {
  if(app)await app.close();
  if(profile?.endsWith('-smoke-'+run))await fs.rm(profile,{recursive:true,force:true});
  await fs.rm(stage,{recursive:true,force:true});
}
