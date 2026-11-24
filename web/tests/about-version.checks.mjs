export async function aboutVersionChecks({fixture,check,assert,out}) {
 for(const desktop of [false,'macOS','Windows'])await check('about version '+(desktop||'Web'),async()=>{
  const f=await fixture(640,500,desktop),p=f.page;
  try{
   await p.locator('.settings-entry').click();await p.locator('.desk-settings nav').getByRole('button',{name:'关于',exact:true}).click();
   const line=p.locator('.about-identity p');await line.waitFor();
   if(desktop)assert.equal(await line.innerText(),`${desktop} · 1.2.0 (87)`);
   else assert.match(await line.innerText(),/(?:Web|网页版) · \d{4}\.\d{2}\.\d{2} · [a-f0-9]{7,}/);
   assert(await line.evaluate(el=>el.scrollWidth<=el.clientWidth+1));
   if(out)await p.screenshot({path:`${out}/about-version-${desktop||'web'}.png`});assert.deepEqual(f.errors,[]);
  }finally{await f.ctx.close();}
 });
}
