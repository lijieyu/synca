import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import assert from 'node:assert/strict';
import {_electron} from 'playwright-core';
const root=path.dirname(new URL(import.meta.url).pathname);const temp=await fs.mkdtemp(path.join(os.tmpdir(),'synca-capture-smoke-'));
const out=process.env.SYNCA_CAPTURE_DIR||path.join(temp,'screenshots');await fs.mkdir(out,{recursive:true});
const fixture=path.join(temp,'fixture.html');
await fs.writeFile(fixture,`<!doctype html><html><body style="margin:0;background:#dce7f0;font-family:system-ui"><div style="padding:55px 80px"><h1>Synca · 截图演示</h1><p>这是本地测试场景，不含真实用户内容。</p><div style="margin:32px 0;background:white;border-radius:18px;padding:40px;width:700px;height:280px;box-shadow:0 15px 50px #4563"><h2>捕捉想法，留住重点</h2><p>选择一个窗口，也可以拖动框选区域。</p><p>矩形标注 · 撤销 · 复制 · 保存</p><div style="height:70px;background:#e9f3ee;border-radius:9px;margin-top:32px"></div></div></div></body></html>`);
const entry=path.join(temp,'entry.cjs');
await fs.writeFile(entry,`const {app,BrowserWindow}=require('electron');app.setPath('userData',${JSON.stringify(path.join(temp,'profile'))});app.whenReady().then(async()=>{const window=new BrowserWindow({width:1100,height:720,useContentSize:true,webPreferences:{sandbox:true}});await window.loadFile(${JSON.stringify(fixture)});globalThis.result=null;globalThis.saves=0;const shot=await window.webContents.capturePage();globalThis.capture=require(${JSON.stringify(path.join(root,'app/capture/main.cjs'))}).installCapture(window,{home:'null',isolated:true},{displays:()=>[{id:1,bounds:{x:0,y:0,width:1100,height:720},size:{width:1100,height:720},scaleFactor:1}],cursor:()=>({x:300,y:300}),windows:async()=>[{x:80,y:170,width:780,height:360}],sources:async()=>[{display_id:'1',thumbnail:shot}],permission:()=> 'granted',clipboard:{writeImage:image=>{globalThis.result={width:image.getSize().width,height:image.getSize().height};}},dialog:{showSaveDialog:async()=>++globalThis.saves===1?{canceled:true}:{filePath:${JSON.stringify(path.join(out,'capture-result.png'))}}}});});`);
let app;
async function start(){const event=app.waitForEvent('window');event.catch(()=>{});await app.evaluate(()=>globalThis.capture.start());const overlay=await event;await overlay.waitForURL(/capture\/index.html/);await overlay.locator('body[data-ready=true]').waitFor();return overlay;}
async function closeWith(page,action){const closed=page.waitForEvent('close');try{await action();}catch(error){if(!page.isClosed())throw error;}await closed;}
try{
 app=await _electron.launch({args:[entry]});app.process().stderr.on('data',value=>process.stderr.write(value));const main=await app.firstWindow();await main.waitForLoadState('load');await app.evaluate(async()=>{for(let i=0;i<100&&!globalThis.capture;i++)await new Promise(r=>setTimeout(r,50));if(!globalThis.capture)throw Error("Capture fixture did not initialize");});
 await main.evaluate(()=>localStorage.setItem('synca.language','zh-Hans'));let overlay=await start();await overlay.screenshot({path:path.join(out,'capture-hover.png')});await closeWith(overlay,()=>overlay.keyboard.press('Escape'));assert.equal(await app.evaluate(()=>globalThis.result),null);
 overlay=await start();await overlay.mouse.move(120,210);await overlay.mouse.down();await overlay.mouse.move(700,500,{steps:10});await overlay.mouse.up();
 await overlay.locator('#annotate').click();await overlay.mouse.move(180,290);await overlay.mouse.down();await overlay.mouse.move(520,390,{steps:8});await overlay.mouse.up();
 await overlay.screenshot({path:path.join(out,'capture-annotated.png')});
 await overlay.locator('#save').click();await overlay.waitForTimeout(100);assert.equal(overlay.isClosed(),false);
 await closeWith(overlay,()=>overlay.locator('#copy').click());const result=await app.evaluate(()=>globalThis.result);assert.ok(result.width>0&&result.height>0);
 overlay=await start();await overlay.mouse.click(300,300);await closeWith(overlay,()=>overlay.locator('#save').click());assert.ok((await fs.stat(path.join(out,'capture-result.png'))).size>100);
 console.log(JSON.stringify({passed:['hover','region','rectangle','cancel-preserves-clipboard','save-cancel-preserves-editor','copy','PNG-save'],result,artifacts:out}));
}finally{if(app)await app.close();await fs.rm(temp,{recursive:true,force:true});}
