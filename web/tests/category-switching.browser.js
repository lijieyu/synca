async (page) => {
 const ctx=await page.context().browser().newContext({viewport:{width:1200,height:850}});
 const p=await ctx.newPage(), errors=[]; p.on('pageerror',e=>errors.push(e.message));
 const stamp='2026-11-10T08:00:00Z'; let listRequests=0,mediaRequests=0;
 const categories=['default','work','life'].map((id,i)=>({id,name:id,isDefault:i===0,color:'sky',sortOrder:i,createdAt:stamp,updatedAt:stamp}));
 const messages=Array.from({length:80},(_,i)=>({id:'text'+i,type:'text',textContent:'演示记录 '+i+' '+('普通文本。'.repeat(i===0?1500:12)),categoryId:i%2?'work':'life',isCleared:false,isDeleted:false,createdAt:stamp,updatedAt:stamp}));
 messages.unshift({id:'image',type:'image',imageUrl:'/api/media/fixture.png',categoryId:'work',isCleared:false,isDeleted:false,createdAt:stamp,updatedAt:stamp});
 await ctx.addInitScript(()=>{localStorage.setItem('authToken','isolated-perf');localStorage.setItem('userEmail','demo@example.com');localStorage.setItem('synca.language','zh-Hans');localStorage.setItem('synca.selectedCategory.demo@example.com','work');});
 await ctx.route('**/*', async route=>{
  const u=new URL(route.request().url()); const reply=x=>route.fulfill({json:x});
  if(u.hostname!=='127.0.0.1')return route.abort();
  if(u.pathname==='/me/access-status')return reply({email:'demo@example.com',accessStatus:{plan:'pro',isUnlimited:true,todayUsed:0}});
  if(u.pathname==='/messages'){listRequests++;return reply({messages});}
  if(u.pathname==='/message-categories')return reply({categories});
  if(u.pathname==='/api/media/fixture.png'){mediaRequests++;return route.fulfill({contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64')});}
  return route.continue();
 });
 try {
  await p.goto('http://127.0.0.1:5197/');
  await p.locator('[data-category-id="work"]').click();
  await p.locator('.message-list').evaluate(el=>el.scrollTop=0);
  await p.locator('.auth-image img').waitFor();
  const first=await p.locator('.auth-image img').getAttribute('src'); const before=listRequests;
  const samples=[];
  for(let i=0;i<6;i++){
   for(const category of ['life','work']) {
    const ms=await p.evaluate(async id=>{
      const start=performance.now();document.querySelector('[data-category-id="'+id+'"]').click();
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      return performance.now()-start;
    },category);samples.push(ms);
   }
  }
  await p.locator('.auth-image img').waitFor();
  const last=await p.locator('.auth-image img').getAttribute('src');
  const result={medianMs:samples.sort((a,b)=>a-b)[Math.floor(samples.length/2)],maxMs:Math.max(...samples),listRequestsDuringSwitch:listRequests-before,mediaRequests,reusedImageURL:first===last,errors};
  console.log(JSON.stringify(result));
  if(!result.reusedImageURL)throw new Error('Warm category switch recreates the image URL: '+JSON.stringify(result));
  if(result.listRequestsDuringSwitch||errors.length)throw new Error(JSON.stringify(result));
  return result;
 } finally {await ctx.close();}
}
