import fs from 'node:fs/promises';
export async function recordPolishChecks({fixture,check,assert,out}) {
  await check('record actions follow hover or keyboard focus, not a retained mouse focus', async()=>{
    const f=await fixture(),p=f.page;try{
      const row=p.locator('[data-message-id=r1]'), actions=row.locator('.actions');
      await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{}}}));
      await row.hover(); await row.locator('.message-copy').click();
      await p.mouse.move(1000,50);
      await p.waitForFunction(()=>getComputedStyle(document.querySelector('[data-message-id=r1] .actions')).opacity==='0');
      await row.hover();
      await p.waitForFunction(()=>getComputedStyle(document.querySelector('[data-message-id=r1] .actions')).opacity==='1');
      await p.keyboard.press('Tab'); await row.locator('.action-btn').first().focus();
      await p.mouse.move(1000,50);
      assert(await row.locator('.action-btn').first().evaluate(el=>el.matches(':focus-visible')));
      assert.equal(await actions.evaluate(el=>getComputedStyle(el).opacity),'1');
      assert.deepEqual(f.errors,[]);
    }finally{await f.ctx.close();}
  });
  for(const behavior of ['expiry footer','stable image hover']) await check('record attachment '+behavior,async()=>{
    const f=await fixture(),p=f.page;try{
      const image=await fs.readFile(new URL('../public/logo.png',import.meta.url));
      await f.ctx.route('**/api/media/record-polish.png',r=>r.fulfill({contentType:'image/png',body:image}));
      const record={id:'photo',type:'image',categoryId:'work',categoryName:'工作',categoryColor:'sky',imageUrl:'/api/media/record-polish.png',attachmentExpiresAt:'2099-12-24T12:57:12Z',isCleared:false,isDeleted:false,createdAt:'2026-11-24T12:57:12Z',updatedAt:'2026-11-24T12:57:12Z'};
      await f.ctx.route('**/messages?*',r=>r.fulfill({json:{messages:[record]}}));
      await f.ctx.route('**/messages',r=>r.fulfill({json:{messages:[record]}}));
      await p.reload();const row=p.locator('[data-message-id=photo]'),photo=row.locator('.message-image');await photo.waitFor();
      if(behavior==='expiry footer'){
        const expiry=row.locator('.message-metadata .attachment-expiry');await expiry.waitFor();
        const b=await expiry.boundingBox(),meta=await row.locator('.category-assignment').boundingBox();
        assert(Math.abs(b.y+b.height/2-meta.y-meta.height/2)<2,'expiry stays on the metadata line');
        assert.equal(await row.locator(':scope > .attachment-expiry').count(),0);
        if(out)await p.screenshot({path:out+'/attachment-footer-light.png'});
        await p.evaluate(()=>{document.documentElement.dataset.appearance='dark';localStorage.setItem('synca.appearance','dark')});
        if(out)await p.screenshot({path:out+'/attachment-footer-dark.png'});
        await p.setViewportSize({width:640,height:500});
        assert(await row.evaluate(el=>el.scrollWidth<=el.clientWidth+1),'minimum window wraps without overflow');
      }else{
        const before=await photo.boundingBox();await photo.hover();
        assert.equal(await photo.evaluate(el=>getComputedStyle(el).transform),'none','hover has no translate or scale');
        const after=await photo.boundingBox();assert.deepEqual(after,before);
      }
      assert.deepEqual(f.errors,[]);
    }finally{await f.ctx.close();}
  });
}
