// These checks use the existing isolated in-memory API harness.
export async function desktopPolishChecks({fixture,check,assert,out}) {
  for (const state of ['free','pro','restricted','failed','connected']) await check('AI state: '+state,async()=>{
    const f=await fixture(); const p=f.page;
    try {
      if(state==='free') {await f.ctx.route('**/me/access-status',r=>r.fulfill({json:{email:'demo@example.invalid',accessStatus:{plan:'free',isUnlimited:false,isTrial:false,todayUsed:3,todayLimit:20}}}));await p.reload();await p.locator('.daily-quota').waitFor();}
      if(['restricted','failed'].includes(state)) await f.ctx.route('**/api/ai/*',r=>r.fulfill({status:403,json:{error:state==='restricted'?'preview_operation_disabled':'unexpected_internal_error'}}));
      if(state==='connected') await f.ctx.route('**/api/ai/connections',r=>r.fulfill({json:{connections:[{id:'test',name:'Test AI',scopes:['read'],expires_at:'2099-01-01',revoked_at:null,last_used_at:null}]}}));
      await p.locator('.settings-entry').click();await p.getByRole('button',{name:'连接 AI',exact:true}).click();
      if(state==='connected'){await p.locator('.ai-connection').waitFor();await p.locator('[data-guide-link]').click();await p.locator('.ai-guide-back').click();await p.locator('.ai-connection').waitFor();}
      else {
        await p.locator('.ai-tutorial').waitFor();await p.locator('.ai-initial-loading').waitFor({state:'detached'});
        if(out && ['free','pro'].includes(state))await p.screenshot({path:out+'/correction-ai-'+state+'.png'});
        assert.equal(await p.locator('.ai-steps li').count(),3);assert.equal(await p.locator('.ai-upgrade').count(),state==='free'?1:0);
        assert.equal(await p.locator('.ai-copy').count(),state==='free'?0:1);
        if(state==='pro'){const button=await p.locator('.ai-copy').boundingBox(),area=await p.locator('.ai-guide-action').boundingBox();assert(Math.abs(button.width-area.width)<1,'copy action stays full width');}
        if(state!=='free')assert.equal(await p.locator('.ai-copy').isEnabled(),state==='pro');
        assert(!/preview_operation_disabled|unexpected_internal_error/.test(await p.locator('.ai-page').innerText()));
        if(state==='failed'){await f.ctx.unroute('**/api/ai/*');await p.locator('.ai-error button').click();await p.waitForFunction(()=>!document.querySelector('.ai-copy')?.disabled);assert.equal(await p.locator('.ai-error').count(),0);}
      }
      assert.deepEqual(f.errors,[]);
    }finally{await f.ctx.close();}
  });
  await check('custom selectors: keyboard, focus, persistence and bounds',async()=>{
    const f=await fixture(640,500);const p=f.page;try{
      await p.locator('.settings-entry').click();await p.getByRole('button',{name:'通用',exact:true}).click();const a=p.getByRole('combobox',{name:'外观'});
      await a.press('ArrowDown');await p.keyboard.press('End');await p.keyboard.press('Enter');assert.equal(await p.evaluate(()=>localStorage.getItem('synca.appearance')),'dark');
      await a.click();await p.keyboard.press('Escape');assert.equal(await p.getByRole('listbox').count(),0);assert.equal(await p.locator('.desk-settings').count(),1);assert(await a.evaluate(el=>el===document.activeElement));
      await p.getByRole('combobox',{name:'语言'}).click();const b=await p.getByRole('listbox').boundingBox();assert(b.x>=0&&b.y>=0&&b.x+b.width<=640&&b.y+b.height<=500);
      await p.keyboard.press('End');await p.keyboard.press('Enter');assert.equal(await p.evaluate(()=>localStorage.getItem('synca.language')),'en');
      await p.getByRole('combobox',{name:'Language'}).click();await p.keyboard.press('Tab');assert.equal(await p.getByRole('listbox').count(),0);assert(await p.locator('.desk-settings').evaluate(el=>el.contains(document.activeElement)),'Tab stays within settings');
      await p.getByRole('combobox',{name:'Appearance'}).click();await p.locator('.settings-title h2').click();assert.equal(await p.getByRole('listbox').count(),0);assert.deepEqual(f.errors,[]);
    }finally{await f.ctx.close();}
  });
  await check('feedback footer aligns and remains fixed while form scrolls',async()=>{
    const f=await fixture(640,500);const p=f.page;try{
      await p.locator('.settings-entry').click();await p.getByRole('button',{name:'提交反馈',exact:true}).click();if(out)await p.screenshot({path:out+'/correction-feedback-minimum.png'});const button=p.locator('.settings-actions button');const before=await button.boundingBox(),input=await p.locator('#feedback-form input[type=email]').boundingBox();assert(Math.abs(input.x+input.width-before.x-before.width)<1);
      await p.locator('#feedback-form').evaluate(el=>el.scrollTop=el.scrollHeight);assert.deepEqual(await button.boundingBox(),before);const panel=await p.locator('.desk-detail').boundingBox();assert(Math.abs((input.x-panel.x)-(panel.x+panel.width-input.x-input.width))<2,'feedback insets must be symmetric');assert(Math.abs(panel.y+panel.height-before.y-before.height-24)<2);if(out){await p.setViewportSize({width:1100,height:760});await p.locator('#feedback-form').evaluate(el=>el.scrollTop=0);await p.screenshot({path:out+'/correction-feedback.png'});}assert.deepEqual(f.errors,[]);
    }finally{await f.ctx.close();}
  });
  await check('menu matches account button width and anchor',async()=>{
    const f=await fixture();const p=f.page;try{if(out){await p.locator('.account-entry').click();await p.screenshot({path:out+'/correction-account-menu.png'});await p.keyboard.press('Escape');}for(const key of ['Home','End']){await p.locator('.sidebar-resizer').press(key);await p.locator('.account-entry').click();const m=await p.locator('.account-menu-panel').boundingBox(),r=await p.locator('.desktop-account-row').boundingBox(),c=await p.locator('.account-entry').boundingBox();assert.equal(m.x,c.x);assert.equal(m.width,c.width);assert.equal(r.y-m.y-m.height,8);await p.keyboard.press('Escape');}assert.deepEqual(f.errors,[]);}finally{await f.ctx.close();}
  });
  await check('sync stays centered without shifting header actions',async()=>{
    const f=await fixture();const p=f.page;try{for(const width of [1280,640]){await p.setViewportSize({width,height:700});const actions=await p.locator('.header-actions').boundingBox();if(width===640)await p.locator('.stream-heading h1').evaluate(el=>el.textContent='这是一个比较长的分类名称');await p.keyboard.press('Meta+r');await p.locator('.sync-feedback[data-visible=true]').waitFor();if(out)await p.screenshot({path:out+'/correction-sync-'+width+'.png'});assert.equal(await p.locator('.sync-feedback').evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(24, 117, 44)');const n=await p.locator('.sync-feedback').boundingBox(),h=await p.locator('.calm-main>.header').boundingBox();assert(Math.abs(n.x+n.width/2-h.x-h.width/2)<1);assert(Math.abs(n.y+n.height/2-h.y-h.height/2)<1);assert.deepEqual(await p.locator('.header-actions').boundingBox(),actions);if(width===640){const title=await p.locator('.stream-heading h1').boundingBox();assert(title.x+title.width+8<=n.x,'long title must not overlap sync icon');}await p.locator('.sync-feedback[data-visible=false]').waitFor();}assert.deepEqual(f.errors,[]);}finally{await f.ctx.close();}
  });
}
