export async function toastPositionChecks({fixture,check,assert,out}) {
 for(const desktop of [false,'macOS'])for(const [width,height] of [[1280,800],[640,500]])await check(`unified toast ${desktop||'Web'} ${width}`,async()=>{
  const f=await fixture(width,height,desktop),p=f.page;
  try{
   if(desktop)await p.evaluate(()=>document.documentElement.setAttribute('data-appearance','dark'));
   const show=async(message,variant='success')=>{await p.evaluate(async({message,variant})=>(await import('/tests/toast-fixture.tsx')).showToast(message,variant),{message,variant});await p.getByText(message,{exact:true}).waitFor();await p.waitForTimeout(350);return p.getByText(message,{exact:true});};
   await p.keyboard.press('Meta+r');const sync=await p.locator('.sync-feedback').boundingBox();
   const toast=await show('Text saved');const box=await toast.boundingBox();
   assert(Math.abs(box.x+box.width/2-sync.x-sync.width/2)<1,'save and sync must share horizontal center');
   assert(Math.abs(box.y+box.height/2-sync.y-sync.height/2)<1,'save and sync must share vertical center');
   assert.equal(await toast.evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(24, 117, 44)');
   if(out)await p.screenshot({path:`${out}/toast-${desktop||'web'}-${width}-success.png`});
   if(width===1280){await p.getByRole('separator').focus();await p.keyboard.press('End');await p.waitForTimeout(100);const moved=await toast.boundingBox(),header=await p.locator('.calm-main>.header').boundingBox();assert(Math.abs(moved.x+moved.width/2-header.x-header.width/2)<1,'toast must follow sidebar resizing');}
   const error=await show('Could not copy. Check clipboard permissions, or open the image and save it.','error');const e=await error.boundingBox(),h=await p.locator('.calm-main>.header').boundingBox();
   assert.equal(await error.getAttribute('role'),'alert');assert.equal(await error.evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(180, 35, 24)');
   assert(Math.abs(e.x+e.width/2-h.x-h.width/2)<1);assert(e.x>=h.x+8&&e.x+e.width<=h.x+h.width-8);assert(e.y+e.height<h.y+h.height-4||e.y>=h.y+h.height+8,'toast must not straddle header divider');
   const actions=await p.locator('.header-actions').boundingBox();assert(e.y>=actions.y+actions.height||e.x+e.width<=actions.x,'error must not cover header controls');
   if(out)await p.screenshot({path:`${out}/toast-${desktop||'web'}-${width}-error.png`});
   await p.locator('.settings-entry').click();await show('Saved');const settings=await p.locator('.settings-title').boundingBox(),notice=await p.getByText('Saved',{exact:true}).boundingBox();assert(Math.abs(notice.x+notice.width/2-settings.x-settings.width/2)<1,'settings toast follows active pane');
   assert.deepEqual(f.errors,[]);
  }finally{await f.ctx.close();}
 });
 for(const desktop of [false,'macOS'])await check(`unified toast actual actions ${desktop||'Web'}`,async()=>{
  const f=await fixture(1280,800,desktop),p=f.page;
  try{
   const row=p.locator('[data-message-id=r2]');await row.hover();await row.getByRole('button',{name:'编辑文本',exact:true}).click();
   await p.locator('.message-editor-input').fill('保存后检查提示位置');await p.locator('.message-editor-input').press('Control+Enter');await p.locator('.message-editor-input').waitFor({state:'detached'});
   const saved=p.locator('.app-toast:visible');await saved.waitFor();assert.equal(await saved.getAttribute('role'),'status');
   let box=await saved.boundingBox(),header=await p.locator('.calm-main>.header').boundingBox();assert(Math.abs(box.y+box.height/2-header.y-header.height/2)<1);
   await saved.waitFor({state:'hidden'});
   await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw new Error('fixture clipboard denied');}}}));
   await row.hover();await row.locator('.message-copy').click();await p.locator('.app-toast[data-variant=error]:visible').waitFor();
   await f.ctx.route('**/messages',route=>route.request().method()==='POST'?route.fulfill({status:503,json:{error:'fixture_unavailable'}}):route.fallback());
   const input=p.locator('.input-bar textarea');await input.fill('发送失败也不丢草稿');await input.press('Enter');
   await p.waitForFunction(()=>document.querySelectorAll('.app-toast[data-variant=error]').length===2);assert.equal(await p.locator('.app-toast:visible').count(),1);assert.equal(await input.inputValue(),'发送失败也不丢草稿');
   if(out)await p.screenshot({path:`${out}/toast-actual-${desktop||'web'}-send-error.png`});
   assert.deepEqual(f.errors,[]);
  }finally{await f.ctx.close();}
 });
 await check('unified toast mobile bounds',async()=>{
  const f=await fixture(390,844),p=f.page;
  try{await p.evaluate(async()=>(await import('/tests/toast-fixture.tsx')).showToast('Could not copy. Check clipboard permissions, or open the image and save it.','error'));const toast=p.locator('.app-toast');await toast.waitFor();const box=await toast.boundingBox(),header=await p.locator('.calm-main>.header').boundingBox();assert(box.x>=8&&box.x+box.width<=382);assert(box.y>=header.y+header.height+8);if(out)await p.screenshot({path:out+'/toast-mobile-error.png'});assert.deepEqual(f.errors,[]);}finally{await f.ctx.close();}
 });

}
