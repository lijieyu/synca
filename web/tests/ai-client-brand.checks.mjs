export async function aiClientBrandChecks({ fixture, check, assert, out }) {
  for (const width of [390, 1100]) await check(`AI client icons and compact connection actions (${width})`, async () => {
    const f = await fixture(width, 844), p = f.page;
    try {
      const names = ['ChatGPT', 'Claude Code', '豆包', 'My Assistant', 'Qwen Work', '千问', 'WorkBuddy', 'Doubao Work', '百度搭子', 'Kimi', 'DeepSeek', 'Z.ai', 'Gemini', 'Cursor', 'Windsurf', 'Cline', 'Cherry Studio', 'Visual Studio Code', 'Codex'];
      await f.ctx.route('**/api/ai/connections', route => route.fulfill({json:{connections:names.map((name,i)=>({id:String(i),name,expires_at:'2099-12-31T00:00:00Z',revoked_at:null,last_used_at:'2026-11-24T12:00:00Z'}))}}));
      await p.goto(new URL('/ai', p.url()).href);
      const rows = p.locator('.ai-connection'); await rows.first().waitFor();
      assert.equal(await rows.count(), names.length);
      assert.equal(await p.locator('[data-ai-brand=unknown]').count(), 1);
      const assets = await p.locator('.ai-app-mark').evaluateAll(async marks => {
        return Promise.all(marks.map(async mark => {
          const image = mark.querySelector('img');
          if (image) { await image.decode(); return image.naturalWidth > 0; }
          const mask = mark.querySelector('.ai-client-mask');
          if (!mask) return !!mark.querySelector('svg');
          const url = getComputedStyle(mask).maskImage.slice(5,-2);
          const probe = new Image(); probe.src = url; await probe.decode(); return probe.naturalWidth > 0;
        }));
      });
      assert(assets.every(Boolean), 'all eighteen bundled client assets load');
      const heading = await rows.first().locator('h3').boundingBox();
      const revoke = await rows.first().locator('button').boundingBox();
      const icon = await rows.first().locator('.ai-app-mark').boundingBox();
      assert(Math.abs(icon.y + icon.height/2 - heading.y - heading.height/2) < 2, 'icon and title are vertically centered');
      assert(Math.abs(heading.y + heading.height/2 - revoke.y - revoke.height/2) < 2, 'revoke stays on the title row');
      assert(await p.locator('.ai-content').evaluate(el=>el.scrollWidth <= el.clientWidth+1));
      if(out) await p.screenshot({path:out+`/ai-connected-${width}-light.png`});
      await p.evaluate(()=>document.documentElement.dataset.appearance='dark');
      if(out) await p.screenshot({path:out+`/ai-connected-${width}-dark.png`});
      await rows.first().locator('button').click();
      const confirm = p.getByRole('dialog'); await confirm.waitFor();
      assert.match(await confirm.innerText(), /ChatGPT/);
      await confirm.getByRole('button',{name:'取消',exact:true}).click();
      assert.equal(await rows.count(), names.length, 'cancel retains the connection');
      assert.deepEqual(f.errors, []);
    } finally { await f.ctx.close(); }
  });
  for (const native of [false, true]) await check(`AI free upgrade routes to ${native ? 'native purchase' : 'Web plan'}`, async () => {
    const f = await fixture(390, 844), p = f.page;
    try {
      await f.ctx.route('**/me/access-status', r => r.fulfill({json:{accessStatus:{plan:'free',isUnlimited:false,isTrial:false,todayUsed:7,todayLimit:20}}}));
      if (native) await f.ctx.addInitScript(() => { window.webkit = {messageHandlers:{syncaAIUpgrade:{postMessage: action => { window.upgradeRequest = action; }}}}; });
      await p.goto(new URL('/ai', p.url()).href);
      const action = p.getByRole('button', {name:'升级 Synca Pro',exact:true}); await action.waitFor();
      const layout = await action.boundingBox(), group = await p.locator('.ai-upgrade-actions').boundingBox();
      assert(Math.abs(layout.width-group.width)<2, 'upgrade is the full-width primary action');
      if(out) await p.screenshot({path:out+`/ai-free-${native ? 'native' : 'web'}.png`});
      await action.click();
      if(native) { assert.equal(await p.evaluate(()=>window.upgradeRequest),'upgrade'); assert.equal(await p.getByRole('dialog').count(),0); }
      else { const modal=p.getByRole('dialog'); await modal.waitFor(); assert.equal(await modal.locator('a[href*="apps.apple.com"]').count(),1); }
      assert.deepEqual(f.errors,[]);
    } finally { await f.ctx.close(); }
  });
}
