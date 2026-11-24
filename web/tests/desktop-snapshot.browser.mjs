import { preview } from 'vite';
import assert from 'node:assert/strict';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'../../desktop/node_modules/playwright-core/index.mjs');
const server=await preview({build:{outDir:'../desktop/app/renderer'},preview:{host:'127.0.0.1',port:0}}),base=server.resolvedUrls.local[0];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const ctx=await browser.newContext();let rows=[{id:'a',type:'text',textContent:'原有记录',isDeleted:false,isCleared:false,createdAt:'2026-11-24T00:00:00.000Z',updatedAt:'2026-11-24T00:00:00.000Z',categoryId:'work'}],offline=false,failCategory=false,categoryName='默认';
await ctx.addInitScript(()=>{localStorage.setItem('authToken','snapshot-fixture');localStorage.setItem('userEmail','cache@example.invalid');window.syncaDesktop={platform:'macOS',version:'1.2.0',session(){},count(){},preferences:async()=>({badge:true}),subscribe:(event,fn)=>{window.addEventListener('fixture-'+event,fn);return()=>window.removeEventListener('fixture-'+event,fn)}}});
await ctx.route('**/*',route=>{const u=new URL(route.request().url()),p=u.pathname;if(u.origin!==new URL(base).origin)return route.abort();
 if(p==='/messages'){if(offline)return route.abort();const since=u.searchParams.get('since');return route.fulfill({json:{messages:since?rows.filter(r=>r.updatedAt>since):rows.filter(r=>!r.isDeleted)}});}
 if(p==='/sync/state')return offline?route.abort():route.fulfill({json:{messages:JSON.stringify(rows),categories:categoryName,access:'a',latestMessage:rows.at(-1).updatedAt,count:rows.filter(r=>!r.isDeleted).length}});
 if(p==='/message-categories'){if(failCategory){failCategory=false;return route.abort();}return route.fulfill({json:{categories:[{id:'default',name:'默认',color:'slate',isDefault:true,sortOrder:0},{id:'work',name:categoryName,color:'sky',isDefault:false,sortOrder:1}]}});}
 if(p==='/me/access-status')return route.fulfill({json:{email:'cache@example.invalid',accessStatus:{plan:'unlimited',isUnlimited:true,todayUsed:0}}});
 if(p.startsWith('/me/'))return route.fulfill({json:{}});return route.continue();
});
const p=await ctx.newPage();p.setDefaultTimeout(8000);
try{
 await p.goto(base);await p.locator('[data-message-id=a]').waitFor();await p.waitForTimeout(1300);
 categoryName='远端分类名称';failCategory=true;await p.evaluate(()=>window.dispatchEvent(new Event('fixture-refresh')));await p.locator('[data-category-id=work]').getByText('远端分类名称',{exact:true}).waitFor();
 rows.push({...rows[0],id:'b',textContent:'增量新增',updatedAt:'2026-11-24T00:01:00.000Z'});
 await p.evaluate(()=>window.dispatchEvent(new Event('fixture-refresh')));await p.locator('[data-message-id=b]').waitFor();await p.waitForTimeout(100);
 offline=true;await p.reload();await p.locator('[data-message-id=a]').waitFor();await p.locator('[data-message-id=b]').waitFor();
 offline=false;rows[0]={...rows[0],isDeleted:true,updatedAt:'2026-11-24T00:02:00.000Z'};await p.evaluate(()=>window.dispatchEvent(new Event('fixture-refresh')));await p.locator('[data-message-id=a]').waitFor({state:'detached'});await p.waitForTimeout(100);
 offline=true;await p.reload();await p.locator('[data-message-id=b]').waitFor();assert.equal(await p.locator('[data-message-id=a]').count(),0);
 console.log('PASS desktop incremental merged snapshot survives offline reload; tombstones do not resurrect');
}finally{await browser.close();server.httpServer.closeAllConnections();await new Promise(r=>server.httpServer.close(r));}
