async (page) => {
 const ctx=await page.context().browser().newContext({viewport:{width:1200,height:850}}), p=await ctx.newPage(), errors=[];
 p.on('pageerror',e=>errors.push(e.message));
 const stamp='2026-11-10T08:00:00Z';
 const categories=['default','work','life'].map((id,i)=>({id,name:id==='work'?'工作':'生活',isDefault:i===0,color:'sky',sortOrder:i,createdAt:stamp,updatedAt:stamp}));
 let messages=Array.from({length:75},(_,i)=>({id:'text'+i,type:'text',textContent:i===12?('长记录用于验证尾部上下文与三行显示。'.repeat(60)+'最终核验标记'):i===15?'牛奶采购清单 · glyph typography gy pq 中文':i===74?'最后一条记录':i===10?'超长记录\n'+('测试长段落。\n'.repeat(250)+'隐藏命中段落'):'演示记录 '+i+' '+('普通文本。'.repeat(12)),categoryId:i%2?'work':'life',isCleared:i===15,isDeleted:false,createdAt:new Date(Date.parse(stamp)+i*1000).toISOString(),updatedAt:stamp}));
 messages.push({id:'late-image',type:'image',imageUrl:'/api/media/late.svg',fileName:'延迟图片.svg',categoryId:'life',isCleared:false,isDeleted:false,createdAt:new Date(Date.parse(stamp)+73500).toISOString(),updatedAt:stamp});
 await ctx.addInitScript(()=>{localStorage.setItem('authToken','isolated-search');localStorage.setItem('userEmail','demo@example.com');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.selectedCategory.demo@example.com','life');});
 await ctx.route('**/*',async route=>{const u=new URL(route.request().url());if(u.hostname!=='127.0.0.1')return route.abort();const reply=json=>route.fulfill({json});if(u.pathname==='/me/access-status')return reply({email:'demo@example.com',accessStatus:{plan:'pro',isUnlimited:true,todayUsed:0}});if(u.pathname==='/messages')return reply({messages});if(u.pathname==='/message-categories')return reply({categories});if(u.pathname==='/api/media/late.svg'){await new Promise(resolve=>setTimeout(resolve,500));return route.fulfill({contentType:'image/svg+xml',body:'<svg xmlns="http://www.w3.org/2000/svg" width="600" height="900"><rect width="600" height="900" fill="#b9d7ed"/></svg>'});}return route.continue();});
 const assert=(v,m)=>{if(!v)throw Error(m);};
 const visible=async id=>p.locator('[data-message-id="'+id+'"]').evaluate(el=>{const box=el.getBoundingClientRect(),list=el.closest('.message-list').getBoundingClientRect();return box.top>=list.top-1&&box.top<list.bottom&& (box.height>list.height-24||box.bottom<=list.bottom+1);});
 const search=async q=>{await p.getByRole('button',{name:'搜索记录',exact:true}).click();await p.getByRole('searchbox').fill(q);await p.locator('.message-search-result').first().waitFor();};
 try {
 await p.goto('http://127.0.0.1:5199/');await p.locator('[data-message-id="text74"]').waitFor();
 const composer=p.locator('.input-bar textarea');
 await composer.focus();
 if(await composer.evaluate(el=>getComputedStyle(el).outlineStyle!=='none'))throw Error('composer initial focus has inner ring');
 await composer.press('Tab');await p.keyboard.press('Shift+Tab');
 if(await composer.evaluate(el=>getComputedStyle(el).outlineStyle!=='none'))throw Error('composer keyboard focus has inner ring');
 const failures=[];
 const check=(ok,label)=>{if(!ok)failures.push(label);};
 const shots=async name=>{for(const theme of ['light','dark']){await p.emulateMedia({colorScheme:theme});await p.screenshot({animations:'disabled',path:'/tmp/synca-round3-'+name+'-'+theme+'.png'});}await p.emulateMedia({colorScheme:'light'});};
 const edit=p.locator('[data-message-id="text74"] button[aria-label="编辑文本"]');
 await edit.click();await p.locator('.message-editor-input').waitFor();
 check(await p.locator('.message-editor-input').evaluate(el=>getComputedStyle(el).outlineStyle==='none'),'editor autofocus ring');await shots('editor');
 await p.keyboard.press('Escape');
 check(await edit.evaluate(el=>document.activeElement===el&&getComputedStyle(el).outlineStyle==='none'),'edit Escape ring');await shots('edit-escape');
 for(const [label,button] of [['delete',p.locator('[data-message-id="text74"] button[title="删除"]')],['brush',p.getByRole('button',{name:'清除已完成',exact:true})]]) {
  if(label==='brush')await p.locator('.category-all').click();
  await button.click();await p.getByRole('dialog').waitFor();await p.keyboard.press('Escape');
  check(await button.evaluate(el=>document.activeElement===el&&getComputedStyle(el).outlineStyle==='none'),label+' Escape ring');await shots(label+'-escape');
  await p.keyboard.press('Tab');await p.keyboard.press('Shift+Tab');
  check(await button.evaluate(el=>document.activeElement===el&&getComputedStyle(el).outlineStyle!=='none'),'keyboard focus missing '+label);
 }
 await p.keyboard.press('Tab');await p.keyboard.press('Shift+Tab');
 const keyboardTrigger=p.getByRole('button',{name:'清除已完成',exact:true});
 await keyboardTrigger.press('Enter');await p.getByRole('dialog').waitFor();await p.keyboard.press('Escape');
 check(await keyboardTrigger.evaluate(el=>document.activeElement===el&&getComputedStyle(el).outlineStyle!=='none'&&parseFloat(getComputedStyle(el).outlineWidth)<=1.5),'keyboard modal restore indicator');await shots('keyboard-escape');
 await search('演示');
 await p.waitForFunction(()=>Math.abs(document.querySelector('[role=dialog]').getBoundingClientRect().width-640)<.001);
 const input=p.getByRole('searchbox'), icon=p.locator('.message-search-field > svg');
 const typedWidth=await icon.evaluate(el=>el.getBoundingClientRect().width);
 await input.fill('');const emptyWidth=await icon.evaluate(el=>el.getBoundingClientRect().width);
 await input.dispatchEvent('compositionstart');await input.fill('ni');const imeWidth=await icon.evaluate(el=>el.getBoundingClientRect().width);await shots('ime');
 check(Math.abs(emptyWidth-18)<.1&&Math.abs(typedWidth-emptyWidth)<.01&&Math.abs(imeWidth-emptyWidth)<.01,'search icon shrinks '+[emptyWidth,typedWidth,imeWidth]);
 await input.fill('演示');await input.dispatchEvent('compositionend',{data:'演示'});await p.locator('.message-search-result').first().waitFor();await p.locator('.message-search-result').first().hover();
 check(await p.locator('.message-search-result').first().evaluate(el=>{const s=getComputedStyle(el,'::before');return s.top===s.bottom&&parseFloat(s.bottom)>=3;}),'hover asymmetric');await shots('hover');
 await input.fill('最后一条');await p.waitForFunction(()=>document.querySelector('.message-search-result')?.textContent.includes('最后一条'));
 await p.emulateMedia({reducedMotion:'reduce'});await p.locator('.message-search-result').click();await p.locator('.search-target').waitFor();
 check(await p.locator('.search-target').evaluate(el=>{const s=getComputedStyle(el,'::before');return parseFloat(s.left)<=-8&&parseFloat(s.right)<=-8&&parseFloat(s.top)>=6&&parseFloat(s.bottom)>=6;}),'locate horizontal inset');await shots('locate');
 for(const [width,label] of [[1200,'desktop'],[390,'mobile']]) {
  await p.setViewportSize({width,height:850});await search('最终核验标记');
  const preview=p.locator('.message-search-preview');
  check(await preview.evaluate(el=>{const mark=el.querySelector('mark'),box=el.getBoundingClientRect(),hit=mark.getBoundingClientRect();return hit.bottom<=box.bottom+1&&hit.top>=box.top&&getComputedStyle(el).webkitLineClamp==='3'&&box.height>parseFloat(getComputedStyle(el).lineHeight)*2;}),'tail hit visible in 3 lines '+label);
  await shots('tail-'+label);await p.keyboard.press('Escape');
 }
 assert(errors.length===0,errors.join('\n'));assert(failures.length===0,failures.join('\n'));return {passed:true,checks:['editor pointer autofocus','edit/delete/brush Escape restore without ring','keyboard Tab and keyboard-opened Escape indicators','IME icon fixed width','balanced hover inset','locate horizontal breathing room']};
 }finally{await ctx.close();}
}
