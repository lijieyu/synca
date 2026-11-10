async (page) => {
  const context = await page.context().browser().newContext();
  const p = await context.newPage();
  const uploaded = [], errors = [];
  p.on('pageerror', e => errors.push(e.message));
  await context.addInitScript(() => {
    localStorage.setItem('authToken', 'isolated-upload-test');
    localStorage.setItem('userEmail', 'demo@example.com');
    localStorage.setItem('synca.language', 'zh-Hans');
  });
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.hostname !== '127.0.0.1') return route.abort();
    if (url.pathname === '/me/access-status') return route.fulfill({json:{accessStatus:{plan:'pro',isUnlimited:true,storage:{canUploadFiles:true,limitBytes:1073741824,usedBytes:0}}}});
    if (url.pathname === '/message-categories') return route.fulfill({json:{categories:[]}});
    if (url.pathname === '/messages') return route.fulfill({json:{messages:[]}});
    if (url.pathname === '/messages/file' || url.pathname === '/messages/image') {
      uploaded.push({path:url.pathname,body:route.request().postDataBuffer().toString('utf8')});
      return route.fulfill({status:201,json:{id:String(uploaded.length),type:'file',fileName:'fixture',isCleared:false}});
    }
    return route.continue();
  });
  try {
    await p.goto('http://127.0.0.1:5197/');
    const picker = p.locator('.file-upload input');
    await picker.waitFor({state:'attached'});
    if (await picker.getAttribute('accept')) throw new Error('File picker still filters formats');
    for (const [name, mimeType] of [['firmware.bin','application/octet-stream'],['settings.json','application/json'],['README',''],['custom.unknown',''],['drawing.svg','image/svg+xml']]) {
      const previous = uploaded.length;
      await picker.setInputFiles({name,mimeType,buffer:Buffer.from('isolated binary fixture')});
      await p.waitForFunction(() => !document.querySelector('.file-upload input').disabled);
      if (uploaded.length !== previous+1 || uploaded.at(-1).path !== '/messages/file' || !uploaded.at(-1).body.includes(name)) {
        throw new Error('File did not reach the generic upload endpoint: '+name);
      }
    }
    if (errors.length) throw new Error(errors.join('\n'));
    return {uploaded:uploaded.length,endpoint:'/messages/file',unrestrictedPicker:true,errors};
  } finally {await context.close();}
}
