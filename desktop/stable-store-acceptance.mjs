// Disposable Windows runner only. Test copies use a synthetic account + loopback backend.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {once} from 'node:events';import {pathToFileURL} from 'node:url';
import {extractAll,createPackage} from '@electron/asar';import {_electron} from 'playwright-core';
if(process.platform!=='win32')throw Error('Windows runtime required');
const arch=process.arch,out=path.resolve('dist/stable-evidence',arch);await fs.mkdir(out,{recursive:true});
const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-stable-acceptance-')),source=path.resolve('dist/stable',arch,'verified-msix','app'),copy=path.join(stage,'app');
const result={version:'1.2.0',build:'89',arch,commit:process.env.GITHUB_SHA,checks:[],scope:'Instrumented copy extracted from verified MSIX of published 1.2.0 with Store startup adapter; synthetic local backend; not Microsoft-signed installation'};
let electron,backend;const log=await fs.open(path.join(out,'backend.log'),'w');
try{
 let occupied=false;try{await fetch('http://127.0.0.1:54671/health',{signal:AbortSignal.timeout(1000)});occupied=true;}catch{}assert.equal(occupied,false,'Fixture port must not belong to another process');
 backend=spawn(process.execPath,['--import',pathToFileURL(path.resolve('../backend/node_modules/tsx/dist/loader.mjs')).href,path.resolve('../backend/tests/acceptance-server.ts')],{stdio:['ignore',log.fd,log.fd]});
 for(let i=0;i<60;i++){if(backend.exitCode!==null)throw Error('Fixture exited before readiness');try{if((await fetch('http://127.0.0.1:54671/health')).ok)break;}catch{}if(i===59)throw Error('Fixture unavailable');await new Promise(r=>setTimeout(r,500));}
 const appData=path.join(stage,'AppData'),website=path.join(appData,'Synca Electron');await fs.mkdir(website,{recursive:true});assert.deepEqual(await fs.readdir(website),[],'Disposable runner website profile must be empty');await fs.writeFile(path.join(website,'preserve.txt'),'website data must not change');
 await fs.cp(source,copy,{recursive:true});const unpacked=path.join(stage,'unpacked'),archive=path.join(copy,'resources/app.asar');extractAll(archive,unpacked);
 const metadata=JSON.parse(await fs.readFile(path.join(unpacked,'package.json'),'utf8'));assert.equal(metadata.main,'store-entry.cjs');
 const entry=`const {app,session,net}=require('electron'),fs=require('node:fs/promises'),path=require('node:path');
app.setPath('appData',${JSON.stringify(appData)});
const proxy=async(request,options={})=>{const url=new URL(typeof request==='string'?request:request.url);if(url.origin!=='https://synca.haerth.cn')return new Response(null,{status:403});return fetch('http://127.0.0.1:54671'+url.pathname+url.search,{method:options.method??request.method??'GET',headers:options.headers??request.headers,body:options.body,redirect:'error'});};net.fetch=proxy;
require('./local-ui.cjs').installLocalUI=(ses,cfg)=>{ses.fetch=proxy;ses.webRequest.onBeforeRequest((details,done)=>done({cancel:!details.url.startsWith(cfg.home+'/')&&!/^(data|blob|devtools|file):/.test(details.url)}));ses.protocol.handle('https',async req=>{const url=new URL(req.url);if(url.origin!==cfg.home)return new Response(null,{status:403});if(req.method==='GET'&&(url.pathname==='/'||/^\\/(assets\\/|logo.png|favicon.png)/.test(url.pathname))){try{const name=url.pathname==='/'?'index.html':url.pathname.slice(1);return new Response(await fs.readFile(path.join(__dirname,'renderer',name)),{headers:{'Content-Type':name.endsWith('.html')?'text/html':name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'application/octet-stream'}});}catch{return new Response(null,{status:404})}}return proxy(req,{method:req.method,headers:req.headers,body:['GET','HEAD'].includes(req.method)?undefined:await req.arrayBuffer()});});};
require('./store-entry.cjs');`;
 await fs.writeFile(path.join(unpacked,'ci-entry.cjs'),entry);await fs.writeFile(path.join(unpacked,'package.json'),JSON.stringify({...metadata,main:'ci-entry.cjs'}));await fs.rm(archive);await createPackage(unpacked,archive);
 electron=await _electron.launch({executablePath:path.join(copy,'Synca Electron.exe'),timeout:60000});
 electron.process().stderr?.on('data',data=>{void fs.appendFile(path.join(out,'runtime.log'),data)});
 let page=await electron.firstWindow();page.setDefaultTimeout(20000);await page.waitForLoadState('domcontentloaded');
 const profile=await electron.evaluate(({app})=>({version:app.getVersion(),userData:app.getPath('userData'),sessionData:app.getPath('sessionData')}));assert.equal(profile.version,'1.2.0');assert.equal(profile.userData,path.join(appData,'Synca Store'));assert.equal(profile.sessionData,profile.userData);result.profile=profile;
 assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),null);
 await page.evaluate(()=>{localStorage.setItem('authToken','visual-fixture');localStorage.setItem('userId','visual-fixture');localStorage.setItem('userEmail','demo@example.invalid');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.appearance','light');});await page.reload();await page.locator('[data-message-id]').first().waitFor();
 assert.deepEqual(await page.evaluate(()=>({version:window.syncaDesktop.version,build:window.syncaDesktop.build,update:typeof window.syncaDesktop.updateAction,capture:typeof window.syncaDesktop.captureStart})),{version:'1.2.0',build:'89',update:'undefined',capture:'undefined'});
 assert.equal(await page.getByRole('button',{name:'收藏',exact:true}).count(),0);assert.equal(await page.getByRole('button',{name:'草稿本',exact:true}).count(),0);
 await electron.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].setContentSize(1440,900));
 assert.equal(await page.getByText('记录灵感，跨设备接着使用。',{exact:true}).count(),0,'Fresh backend must not contain a prior acceptance record');
 await page.locator('.input-bar textarea').fill('记录灵感，跨设备接着使用。');await page.locator('.input-bar .send-btn').click();await page.locator('[data-message-id]').filter({hasText:'记录灵感，跨设备接着使用。'}).waitFor();
 await page.reload();await page.locator('[data-message-id]').filter({hasText:'记录灵感，跨设备接着使用。'}).waitFor();assert.equal(await page.locator('.input-bar textarea').inputValue(),'');
 await page.screenshot({path:path.join(out,'stable-tasks-zh-CN.png')});
 await page.evaluate(()=>localStorage.setItem('synca.appearance','dark'));await page.reload();await page.locator('[data-message-id]').first().waitFor();await page.screenshot({path:path.join(out,'stable-tasks-dark-zh-CN.png')});
 await page.evaluate(()=>{localStorage.setItem('synca.language','en');localStorage.setItem('synca.appearance','light');});await page.reload();await page.locator('[data-message-id]').first().waitFor();await page.screenshot({path:path.join(out,'stable-tasks-en-US.png')});
 assert.deepEqual(await fs.readdir(website),['preserve.txt']);assert.equal(await fs.readFile(path.join(website,'preserve.txt'),'utf8'),'website data must not change');
 result.checks=['released version 1.2.0 / build 89','Store profile and session isolation; website sentinel unchanged','no 1.2.1 Collections/Scratchpad/Capture/updater UI','record create/read against isolated backend','actual Windows Chinese/English and light/dark screenshots'];result.result='passed';
}catch(error){result.result='failed';result.error=error.stack;throw error;}
finally{await fs.writeFile(path.join(out,'acceptance.json'),JSON.stringify(result,null,2));if(electron)await electron.close().catch(()=>{});if(backend&&backend.exitCode===null){const stopped=once(backend,'exit');backend.kill();await stopped;}await log.close();await fs.rm(stage,{recursive:true,force:true,maxRetries:5,retryDelay:200}).catch(()=>{});}
