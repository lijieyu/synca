import { preview } from 'vite';
import assert from 'node:assert/strict';
const {default:express}=await import(process.env.EXPRESS_MODULE||'../../backend/node_modules/express/index.js');
import fs from 'node:fs/promises';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'../../desktop/node_modules/playwright-core/index.mjs');
const out=process.env.SYNCA_CAPTURE_DIR||'/private/tmp/synca-incremental-evidence';await fs.mkdir(out,{recursive:true});
const app=express();
const server=await preview({preview:{host:'127.0.0.1',port:0},plugins:[{name:'sync-fixture',configurePreviewServer(server){server.middlewares.use(app);}}]});const base=server.resolvedUrls.local[0];
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
let records=Array.from({length:180},(_,i)=>({id:'r'+i,type:'text',textContent:'历史记录 '+i+' '+('已有内容。'.repeat(80)),categoryId:'work',categoryName:'工作',categoryColor:'sky',categoryIsDefault:false,sourceDevice:'iOS',isCleared:false,isDeleted:false,createdAt:new Date(Date.UTC(2026,10,20,0,i)).toISOString(),updatedAt:new Date(Date.UTC(2026,10,20,0,i)).toISOString()}));
let categories=[{id:'default',name:'默认',color:'slate',isDefault:true,sortOrder:0},{id:'work',name:'工作',color:'sky',isDefault:false,sortOrder:1}];
let failCategory=false,failMessages=false;const requests=[],errors=[];
// Real Express conditional responses exercise the same automatic ETag behavior as production.
app.get('/messages',(req,res)=>{
 const since=req.query.since??null;
 if(failMessages){failMessages=false;requests.push({since,status:503,bytes:0});return res.status(503).json({error:'fixture_unavailable'});}
 const data=since?records.filter(row=>row.updatedAt>since):records.filter(row=>!row.isDeleted);
 const body=JSON.stringify({messages:data});
 res.on('finish',()=>requests.push({since,status:res.statusCode,bytes:res.statusCode===304?0:Buffer.byteLength(body),ids:data.map(r=>r.id)}));
 res.json({messages:data});
});
async function context(){
 const ctx=await browser.newContext({viewport:{width:1100,height:760}});
 await ctx.addInitScript(()=>{localStorage.setItem('authToken','synthetic-session');localStorage.setItem('userEmail','synthetic@example.invalid');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.defaultSendCategory.synthetic@example.invalid','work');});
 await ctx.route('**/*',async route=>{
  const request=route.request(),url=new URL(request.url());if(url.origin!==new URL(base).origin)return route.abort();
  const path=url.pathname;
  if(path==='/messages'&&request.method()==='GET')return route.continue();
  if(path==='/message-categories'){if(failCategory){failCategory=false;return route.fulfill({status:503,json:{error:'fixture_unavailable'}});}return route.fulfill({json:{categories}});}
  if(path==='/me/access-status')return route.fulfill({json:{email:'synthetic@example.invalid',accessStatus:{plan:'unlimited',isUnlimited:true,isTrial:false,todayUsed:0,todayLimit:null}}});
  if(path.startsWith('/me/')||path.startsWith('/api/ai/'))return route.fulfill({json:{connections:[],operations:[],links:[]}});
  return route.continue();
 });
 const p=await ctx.newPage();p.setDefaultTimeout(7000);p.on('pageerror',e=>errors.push(e.message));await p.clock.install();await p.goto(base);return{ctx,p};
}
async function cycle(p){const count=requests.length;await p.clock.fastForward(10000);await p.waitForFunction(()=>true);for(let n=0;n<100&&requests.length===count;n++)await new Promise(r=>setTimeout(r,20));assert(requests.length>count,'timer must still check for remote changes');await p.waitForTimeout(150);}
try{
 const {ctx,p}=await context();await p.locator('[data-message-id=r0]').waitFor();await p.waitForTimeout(150);
 const initialBytes=requests[0].bytes;assert.equal(requests.length,1);assert.equal(requests[0].since,null);
 const composer=p.locator('.input-bar textarea');await composer.fill('输入中的草稿');
 for(let i=0;i<3;i++)await cycle(p);
 assert(requests.slice(1).every(r=>r.since));assert(requests.some(r=>r.status===304));
 assert.equal(await p.locator('[data-message-id]').count(),180);
 const idleBytes=requests.slice(1).reduce((sum,r)=>sum+r.bytes,0);
 assert(idleBytes<initialBytes/20,'idle response body must drop by more than 95% for this fixture');
 // A second device commits a different row with exactly the latest timestamp.
 records.push({...records.at(-1),id:'same-ms',textContent:'同毫秒新增'});await cycle(p);await p.locator('[data-message-id=same-ms]').waitFor();
 assert.equal(await composer.inputValue(),'输入中的草稿');
 const revision='2026-11-24T03:00:00.000Z';
 records[0]={...records[0],textContent:'远端已编辑',updatedAt:revision};
 records[1]={...records[1],isDeleted:true,updatedAt:revision};
 records[2]={...records[2],isCleared:true,updatedAt:revision};
 await cycle(p);await p.locator('[data-message-id=r0]').getByText('远端已编辑',{exact:true}).waitFor();assert.equal(await p.locator('[data-message-id=r1]').count(),0);
 await p.getByRole('button',{name:'清除已完成',exact:true}).waitFor();assert(await p.getByRole('button',{name:'清除已完成',exact:true}).isEnabled());
 // Real category writes also revise affected messages; preserve the authoritative list.
 categories=[categories[0],{...categories[1],name:'重命名分类',color:'mint'}];
 records=records.map(row=>({...row,categoryName:'重命名分类',categoryColor:'mint',updatedAt:'2026-11-24T03:00:01.000Z'}));
 await cycle(p);await p.locator('[data-category-id=work]').getByText('重命名分类',{exact:true}).waitFor();
 // Deleting the active category remotely must repair its target without losing either draft.
 await p.locator('[data-category-id=default]').click();await composer.fill('默认分类原有草稿');
 await p.locator('[data-category-id=work]').click();await composer.fill('被删除分类中的草稿');
 await composer.press('Home');await composer.press('ArrowRight');await composer.press('ArrowRight');await composer.press('Shift+ArrowRight');await composer.press('Shift+ArrowRight');
 assert.deepEqual(await composer.evaluate(el=>[el.selectionStart,el.selectionEnd]),[2,4]);
 categories=[categories[0]];records=records.map(row=>({...row,categoryId:'default',categoryName:'默认',categoryIsDefault:true,updatedAt:'2026-11-24T03:00:02.000Z'}));
 await cycle(p);assert.equal(await p.locator('[data-category-id=default]').getAttribute('aria-pressed'),'true');
 assert.equal(await composer.inputValue(),'被删除分类中的草稿\n\n默认分类原有草稿');
 assert.deepEqual(await composer.evaluate(el=>[el.selectionStart,el.selectionEnd]),[2,4]);
 assert.equal(await p.evaluate(()=>localStorage.getItem('synca.defaultSendCategory.synthetic@example.invalid')),'default');
 await p.locator('[data-category-id=__all__]').click();assert.equal(await composer.inputValue(),'输入中的草稿');
 // Failed category fetch must not advance the accepted record checkpoint or consume cached deltas.
 records.push({...records[0],id:'retry',textContent:'失败后补齐',updatedAt:'2026-11-24T03:00:05.000Z'});failCategory=true;
 await cycle(p);assert.equal(await p.locator('[data-message-id=retry]').count(),0);const failedSince=requests.at(-1).since;
 await cycle(p);assert.equal(requests.at(-1).since,failedSince);await p.locator('[data-message-id=retry]').waitFor();
 failMessages=true;await cycle(p);const retrySince=requests.at(-1).since;await cycle(p);assert.equal(requests.at(-1).since,retrySince);
 const prior=requests.length;await p.keyboard.press('Control+r');await p.getByText('同步成功',{exact:true}).waitFor();assert(requests.length>prior);assert(requests.at(-1).since);assert.equal(await composer.inputValue(),'输入中的草稿');
 assert.equal(requests.filter(r=>r.since===null).length,1,'full list is only loaded once');assert.deepEqual(errors,[]);
 await p.screenshot({path:out+'/incremental-home.png'});await ctx.close();
 // An initially empty account must still discover its first record incrementally.
 const seed={...records[0],id:'first',textContent:'第一条记录'};records=[];const start=requests.length;const empty=await context();await empty.p.locator('.input-bar textarea').waitFor();await empty.p.waitForTimeout(150);records=[seed];await cycle(empty.p);await empty.p.locator('[data-message-id=first]').waitFor();assert.equal(requests[start].since,null);assert.equal(requests[start+1].since,'1970-01-01T00:00:00.000Z');await empty.ctx.close();
 const report={initialBytes,idleBytes,baselineThreePollBytes:3*initialBytes,reductionPercent:100*(1-idleBytes/(3*initialBytes)),checks:['idle delta/304','same timestamp','edit/delete/complete','category rename/delete and both drafts','failed category retry','failed message retry','Ctrl+R preserves draft','empty initial account'],requests};
 await fs.writeFile(out+'/network-verification.json',JSON.stringify(report,null,2));console.log(JSON.stringify({...report,requests:requests.length},null,2));
}finally{await browser.close();await new Promise(resolve=>server.httpServer.close(resolve));}
