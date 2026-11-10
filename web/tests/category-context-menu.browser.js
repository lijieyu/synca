async (page) => {
 const ctx=await page.context().browser().newContext({viewport:{width:1100,height:820}});
 const p=await ctx.newPage(); const errors=[];p.on('pageerror',e=>errors.push(e.message));
 const stamp='2026-11-10T08:00:00.000Z';
 let categories=[['default','默认',true],['work','工作',false],['life','生活',false],['empty','空分类',false]].map(([id,name,isDefault],i)=>({id,name,isDefault,color:'sky',sortOrder:i,createdAt:stamp,updatedAt:stamp,userId:'qa'}));
 let messages=[{id:'done',type:'text',textContent:'已完成的演示项目',categoryId:'work',categoryName:'工作',categoryColor:'sky',categoryIsDefault:false,isCleared:true,isDeleted:false,createdAt:stamp,updatedAt:stamp}];
 const writes=[];let failOrder=false;
 const assert=(ok,why)=>{if(!ok)throw new Error(why)};
 await ctx.addInitScript(()=>{localStorage.setItem('authToken','isolated-qa');localStorage.setItem('userEmail','demo@example.com');localStorage.setItem('synca.language','zh-Hans');});
 await ctx.route('**/*',async route=>{
  const req=route.request(),u=new URL(req.url()),path=u.pathname,method=req.method(); const reply=data=>route.fulfill({json:data});
  if(u.hostname!=='127.0.0.1')return route.abort();
  if(path==='/me/access-status')return reply({email:'demo@example.com',accessStatus:{plan:'pro',isUnlimited:true,todayUsed:0}});
  if(path==='/messages')return reply({messages});
  if(path==='/message-categories')return reply({categories});
  if(path==='/message-categories/order'){
   const ids=req.postDataJSON().categoryIds;writes.push({method,ids});
   if(failOrder)return route.fulfill({status:500,json:{error:'test failure'}});
   categories=[categories[0],...ids.map(id=>categories.find(c=>c.id===id))];return reply({ok:true});
  }
  if(path.startsWith('/message-categories/')){
   const id=path.split('/').pop();writes.push({method,id});
   if(method==='DELETE'){categories=categories.filter(c=>c.id!==id);messages=messages.map(m=>m.categoryId===id?{...m,categoryId:'default',categoryName:'默认',categoryIsDefault:true}:m);return reply({ok:true});}
   if(method==='PATCH'){const patch=req.postDataJSON();categories=categories.map(c=>c.id===id?{...c,...patch}:c);return reply(categories.find(c=>c.id===id));}
  }
  return route.continue();
 });
 try{
  await p.goto('http://127.0.0.1:5197/');
  const row=id=>p.locator('[data-category-id="'+id+'"]');const menu=()=>p.getByRole('menu');
  await row('work').waitFor();await row('work').click({button:'right'});
  assert(await p.locator('main h1').innerText()==='全部','Right click changed selection');
  assert((await menu().getByRole('menuitem').allTextContents()).join(',')==='修改,上移,下移,删除','Order');
  assert(await menu().getByRole('menuitem',{name:'上移',exact:true}).isDisabled(),'First item move up');
  assert(await menu().getByRole('separator').count()===1,'Delete separator');
  await p.screenshot({path:'/tmp/synca-category-context/web-menu-light.png'});
  await menu().getByRole('menuitem',{name:'下移',exact:true}).click();await p.waitForFunction(()=>[...document.querySelectorAll('[data-sort-id]')][0]?.getAttribute('data-sort-id')==='life');
  await row('work').click({button:'right'});await menu().getByRole('menuitem',{name:'修改',exact:true}).click();
  const dlg=p.getByRole('dialog');await dlg.getByRole('textbox').fill('工作修改');await dlg.getByRole('button',{name:'保存',exact:true}).click();await row('work').getByText('工作修改').waitFor();
  await row('default').click({button:'right'});assert(await menu().locator('button:disabled').count()===4,'Default category must be protected');await p.keyboard.press('Escape');assert(await menu().count()===0,'Esc close');
  await row('empty').focus();await p.keyboard.press('Shift+F10');assert(await menu().getByRole('menuitem',{name:'下移',exact:true}).isDisabled(),'Last item move down');await menu().getByRole('menuitem',{name:'删除',exact:true}).click();
  assert(await dlg.locator('.modal-message').count()===0,'Empty delete has unnecessary explanation');const prior=writes.length;await dlg.getByRole('button',{name:'取消',exact:true}).click();assert(writes.length===prior,'Cancel wrote data');
  await row('work').click();await row('work').click({button:'right'});await menu().getByRole('menuitem',{name:'删除',exact:true}).click();
  assert((await dlg.innerText()).includes('移到默认分类'),'Completed record must trigger migration warning');await p.screenshot({path:'/tmp/synca-category-context/web-delete-populated.png'});await dlg.getByRole('button',{name:'删除',exact:true}).click();await row('work').waitFor({state:'detached'});assert(await p.locator('main h1').innerText()==='默认','Deleted active category fallback');assert(messages[0].categoryId==='default'&&messages[0].isCleared,'Message state lost');
  failOrder=true;await row('life').click({button:'right'});await menu().getByRole('menuitem',{name:'下移',exact:true}).click();await dlg.waitFor();assert(await p.locator('[data-sort-id]').first().getAttribute('data-sort-id')==='life','Failed sort not rolled back');await p.keyboard.press('Escape');
  await p.evaluate(()=>document.documentElement.dataset.appearance='dark');await row('life').click({button:'right'});await p.screenshot({path:'/tmp/synca-category-context/web-menu-dark.png'});await p.keyboard.press('ArrowDown');await p.keyboard.press('Escape');assert(await menu().count()===0,'Keyboard close');assert(errors.length===0,errors.join('\n'));
  return {passed:true,checks:['menu order and separator','right-click selection unchanged','first/last disabled','default protected','keyboard and Escape','edit saved','sort persisted','failed sort rollback','empty confirmation','completed-record warning','cancel no write','delete fallback and migration'],writes};
 } finally {await ctx.close();}
}
