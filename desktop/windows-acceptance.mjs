// Windows-only evidence. Instrumented copies redirect ALL service traffic to a
// synthetic loopback fixture. Release ZIP/Setup/MSIX bytes are never modified.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import assert from 'node:assert/strict';import {createHash} from 'node:crypto';import {spawn,execFileSync} from 'node:child_process';
import {verifySquirrel} from './windows-squirrel-acceptance.mjs';
import {extractAll,createPackage} from '@electron/asar';import {_electron} from 'playwright-core';
if(process.platform!=='win32'||!['x64','arm64'].includes(process.arch))throw Error('Run on Windows x64 or ARM64');
const arch=process.arch;
const out=path.resolve('dist/evidence');await fs.mkdir(out,{recursive:true});
const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-windows-acceptance-')),appData=path.join(stage,'AppData');await fs.mkdir(appData);
const evidence={os:os.release(),arch:process.arch,commit:process.env.GITHUB_SHA,scope:'Real Windows binaries; instrumented copies only; synthetic account and loopback service. Not Store certification.',checks:[],limitations:['Formal Microsoft Store signed installation and Store-managed upgrade require Partner Center identity and approval']};
let running,backend;
const log=await fs.open(path.join(out,'backend.log'),'w');
const powershell=(script)=>execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{encoding:'utf8',timeout:180000});
const quote=s=>"'"+s.replaceAll("'","''")+"'";
async function instrument(source,name,inPlace=false){
 const target=inPlace?source:path.join(stage,name);if(!inPlace)await fs.cp(source,target,{recursive:true});
 const archive=path.join(target,'resources/app.asar'),unpacked=path.join(stage,name+'-source');extractAll(archive,unpacked);
 const metadata=JSON.parse(await fs.readFile(path.join(unpacked,'package.json'),'utf8'));
 const entry=`const {app,session,net}=require('electron');const fs=require('node:fs/promises'),path=require('node:path');
// Observe the real legacy defaults; no userData/sessionData/appData overrides.
if(app.getVersion()==='1.2.0'){const syncFS=require('node:fs');const profile=app.getPath('userData');if(syncFS.existsSync(profile)&&syncFS.readdirSync(profile).length)throw Error('Legacy profile must be empty on this disposable runner');}
const proxy=async(request,options={})=>{const url=new URL(typeof request==='string'?request:request.url);if(url.origin!=='https://synca.haerth.cn')return new Response(null,{status:403});if(url.pathname==='/app-updates')return Response.json({schema:1,windows:process.env.SYNCA_CI_RELEASE?{[process.arch]:JSON.parse(await fs.readFile(process.env.SYNCA_CI_RELEASE,'utf8'))}:{}});if(url.pathname.endsWith('-Setup.exe')&&process.env.SYNCA_CI_SETUP)return new Response(await fs.readFile(process.env.SYNCA_CI_SETUP));if(url.pathname.endsWith('/Synca-1.2.2-full.nupkg')&&process.env.SYNCA_CI_PACKAGE)return new Response(await fs.readFile(process.env.SYNCA_CI_PACKAGE));const response=await fetch('http://127.0.0.1:54671'+url.pathname+url.search,{method:options.method??request.method??'GET',headers:options.headers??request.headers,body:options.body,redirect:'error'});return response;};
net.fetch=proxy;
require('./local-ui.cjs').installLocalUI=(ses,cfg)=>{
 ses.fetch=proxy;
 ses.webRequest.onBeforeRequest((details,done)=>done({cancel:!details.url.startsWith(cfg.home+'/')&&!/^(data|blob|devtools|file):/.test(details.url)}));
 ses.protocol.handle('https',async req=>{const url=new URL(req.url);if(url.origin!==cfg.home)return new Response(null,{status:403});
  if(req.method==='GET'&&(url.pathname==='/'||/^\\/(assets\\/|logo.png|favicon.png)/.test(url.pathname))){try{const name=url.pathname==='/'?'index.html':url.pathname.slice(1);return new Response(await fs.readFile(path.join(__dirname,'renderer',name)),{headers:{'Content-Type':name.endsWith('.html')?'text/html':name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'image/png'}});}catch{return new Response(null,{status:404})}}
  return proxy(req,{method:req.method,headers:req.headers,body:['GET','HEAD'].includes(req.method)?undefined:await req.arrayBuffer()});
 });
};
app.on('browser-window-created',(_event,window)=>window.webContents.on('did-finish-load',async()=>{if(app.getVersion()==='1.2.2'){const values=await window.webContents.executeJavaScript('({authToken:localStorage.getItem("authToken"),draft:localStorage.getItem("synca.ci.unsent")})');await fs.writeFile(path.join(process.env.SYNCA_CI_APPDATA,'launch-1.2.2.json'),JSON.stringify({...values,version:app.getVersion(),profile:app.getPath('userData')}));}}));
require('./${metadata.main}');`;
 await fs.writeFile(path.join(unpacked,'ci-entry.cjs'),entry);metadata.main='ci-entry.cjs';await fs.writeFile(path.join(unpacked,'package.json'),JSON.stringify(metadata));await fs.rm(archive);await createPackage(unpacked,archive);
 return path.join(target,'Synca Electron.exe');
}
async function launch(executable){
 running=await _electron.launch({executablePath:executable,env:{...process.env,SYNCA_CI_APPDATA:appData},timeout:60000});
 const page=await running.firstWindow();page.setDefaultTimeout(20000);await page.waitForLoadState('domcontentloaded');return page;
}
async function close(){if(running){await running.close();running=null;}}
try{
 backend=spawn(process.execPath,[path.resolve('../backend/node_modules/tsx/dist/cli.mjs'),path.resolve('../backend/tests/acceptance-server.ts')],{stdio:['ignore',log.fd,log.fd]});
 for(let i=0;i<60;i++){try{const r=await fetch('http://127.0.0.1:54671/health');if(r.ok)break;}catch{}if(i===59)throw Error('Fixture failed to start');await new Promise(r=>setTimeout(r,500));}
 const oldZip=path.join(stage,'1.2.0.zip');const response=await fetch(`https://synca.haerth.cn/downloads/windows/1.2.0-20261125-r3/Synca-1.2.0-Windows-${arch}.zip`,{redirect:'error',signal:AbortSignal.timeout(180000)});assert(response.ok);
 const bytes=Buffer.from(await response.arrayBuffer());const digest=createHash('sha256').update(bytes).digest('hex');assert.equal(digest,{x64:'988ad348b73e2690b0f8ce2807bf370c669c42060e44d08ab21aba0db8f2711e',arm64:'3526b7be1429d4e21d0c24c16562b5de0f4202307b57b9e2ab5ed5884a323068'}[arch]);await fs.writeFile(oldZip,bytes);
 powershell(`Expand-Archive -LiteralPath ${quote(oldZip)} -DestinationPath ${quote(path.join(stage,'old'))}`);
 const oldSource=path.join(stage,'old',`Synca Electron-win32-${arch}`);assert.deepEqual(JSON.parse(await fs.readFile(path.join(oldSource,'resources/build-info.json'),'utf8')),{version:'1.2.0',build:'89'});
 const oldExe=await instrument(oldSource,'legacy-runtime');let page=await launch(oldExe);
 const oldProfile=await running.evaluate(({app})=>({name:app.getName(),profile:app.getPath('userData'),session:app.getPath('sessionData')}));assert.equal(oldProfile.name,'Synca Electron');
 await page.evaluate(async()=>{
  localStorage.setItem('authToken','visual-fixture');localStorage.setItem('userId','visual-fixture');localStorage.setItem('userEmail','demo@example.invalid');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.appearance','light');localStorage.setItem('synca.ci.unsent','本地草稿：升级不能丢失');
  await new Promise((resolve,reject)=>{const req=indexedDB.open('synca-ci-preservation',1);req.onupgradeneeded=()=>req.result.createObjectStore('records');req.onerror=()=>reject(req.error);req.onsuccess=()=>{const db=req.result,tx=db.transaction('records','readwrite');tx.objectStore('records').put('未同步的本地内容','draft');tx.oncomplete=()=>{db.close();resolve()};tx.onerror=()=>reject(tx.error)}});
 });
 await running.evaluate(async({session})=>{await session.defaultSession.cookies.set({url:'https://synca.haerth.cn',name:'ci-session',value:'synthetic-session',secure:true,expirationDate:Math.floor(Date.now()/1000)+86400});await session.defaultSession.cookies.flushStore();await session.defaultSession.flushStorageData()});
 await fs.writeFile(path.join(oldProfile.profile,'desktop-preferences.json'),JSON.stringify({badge:false,ask:false,directory:''}));await fs.writeFile(path.join(oldProfile.profile,'local-file.txt'),'本地附件样本');
 await close();evidence.checks.push({name:'official 1.2.0 (89) runtime profile seed',sha256:digest,...oldProfile});
 const currentExe=await instrument(path.resolve(`dist/Synca Electron-win32-${arch}`),'website-runtime');page=await launch(currentExe);
 const currentProfile=await running.evaluate(({app})=>app.getPath('userData'));assert.equal(currentProfile,oldProfile.profile);
 assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),'visual-fixture');assert.equal(await page.evaluate(()=>localStorage.getItem('synca.ci.unsent')),'本地草稿：升级不能丢失');
 assert.equal(await page.evaluate(()=>new Promise((resolve,reject)=>{const req=indexedDB.open('synca-ci-preservation');req.onsuccess=()=>{const db=req.result,r=db.transaction('records').objectStore('records').get('draft');r.onsuccess=()=>{db.close();resolve(r.result)};r.onerror=()=>reject(r.error)}})),'未同步的本地内容');
 assert.equal((await running.evaluate(async({session})=>session.defaultSession.cookies.get({name:'ci-session'})))[0].value,'synthetic-session');
 assert.equal(await fs.readFile(path.join(currentProfile,'local-file.txt'),'utf8'),'本地附件样本');assert.equal(JSON.parse(await fs.readFile(path.join(currentProfile,'desktop-preferences.json'),'utf8')).badge,false);
 await page.locator('[data-message-id]').first().waitFor();evidence.checks.push({name:'1.2.0 → 1.2.1 profile: auth token, cookie, localStorage, IndexedDB, preferences, file',passed:true});
 await running.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setContentSize(1440,900));
 await page.screenshot({path:path.join(out,'windows-tasks-zh-CN.png')});
 await page.getByRole('button',{name:'收藏',exact:true}).click();await page.locator('.collection-filter').waitFor();await page.screenshot({path:path.join(out,'windows-collections-zh-CN.png')});
 await page.getByRole('button',{name:'草稿本',exact:true}).click();const editor=page.locator('.scratchpad textarea');await editor.waitFor();await page.waitForFunction(()=>document.querySelector('.scratchpad textarea')?.value.includes('随时接着写'));
 await editor.fill((await editor.inputValue())+'\n\nWindows：自动保存与同步回归。');await page.getByRole('button',{name:'预览',exact:true}).click();await page.getByText('已同步',{exact:true}).waitFor();await page.screenshot({path:path.join(out,'windows-scratchpad-zh-CN.png')});
 await page.evaluate(()=>localStorage.setItem('synca.appearance','dark'));await page.reload();await page.getByRole('button',{name:'收藏',exact:true}).click();await page.locator('.collection-filter').waitFor();await page.screenshot({path:path.join(out,'windows-collections-dark-zh-CN.png')});
 await page.evaluate(()=>{localStorage.setItem('synca.language','en');localStorage.setItem('synca.appearance','light')});await page.reload();
 await page.getByRole('button',{name:'Collections',exact:true}).click();await page.locator('.collection-filter').waitFor();await page.screenshot({path:path.join(out,'windows-collections-en-US.png')});
 await page.getByRole('button',{name:'Scratchpad',exact:true}).click();await page.locator('.scratchpad textarea').waitFor();await page.getByRole('button',{name:'Preview',exact:true}).click();await page.screenshot({path:path.join(out,'windows-scratchpad-en-US.png')});
 // Native Windows screen enumeration and capture, not a mocked image source.
 async function capture(){const opened=running.waitForEvent('window',p=>p!==page);await page.evaluate(()=>window.syncaDesktop.captureStart());const overlay=await opened;await overlay.locator('body[data-ready=true]').waitFor();return overlay;}
 await running.evaluate(({clipboard})=>clipboard.writeText('Synca CI cancel sentinel'));
 let overlay=await capture();await overlay.screenshot({path:path.join(out,'windows-native-capture.png')});await overlay.keyboard.press('Escape');assert.equal(await running.evaluate(({clipboard})=>clipboard.readText()),'Synca CI cancel sentinel');
 overlay=await capture();await overlay.mouse.move(120,150);await overlay.mouse.down();await overlay.mouse.move(650,450,{steps:10});await overlay.mouse.up();await overlay.locator('#annotate').click();await overlay.mouse.move(170,220);await overlay.mouse.down();await overlay.mouse.move(510,340,{steps:8});await overlay.mouse.up();await overlay.screenshot({path:path.join(out,'windows-native-capture-annotated.png')});
 const closed=overlay.waitForEvent('close');await overlay.locator('#copy').click().catch(error=>{if(!overlay.isClosed())throw error});await closed;
 const copied=await running.evaluate(({clipboard})=>{const image=clipboard.readImage();return {size:image.getSize(),png:image.toPNG().toString('base64')}});assert(copied.size.width>0&&copied.size.height>0);await fs.writeFile(path.join(out,'windows-native-clipboard.png'),Buffer.from(copied.png,'base64'));
 evidence.checks.push({name:'Windows collections, Markdown autosave/preview, light/dark, native capture region/rectangle/clipboard/cancel',passed:true,clipboardSize:copied.size});await close();
 await verifySquirrel({stage,appData,out,instrument,launch,close,evidence,currentExe});
 const storeExe=await instrument(path.resolve(`dist/store-app/Synca Electron-win32-${arch}`),'store-runtime');page=await launch(storeExe);
 assert.equal(await running.evaluate(({app})=>app.getPath('userData')),path.join(path.dirname(oldProfile.profile),'Synca Store'));
 assert.equal(await page.evaluate(()=>typeof window.syncaDesktop.updateAction),'undefined');assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),null);evidence.checks.push({name:'Store marker runtime: isolated profile and no updater bridge',passed:true});await close();
 evidence.result='passed';
} catch(error){evidence.result='failed';evidence.error=error.stack;throw error;}
finally{await close();backend?.kill();await log.close();await fs.writeFile(path.join(out,'windows-acceptance.json'),JSON.stringify(evidence,null,2));await fs.rm(stage,{recursive:true,force:true}).catch(()=>{});}
