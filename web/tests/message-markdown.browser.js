async (page) => {
  const ctx = await page.context().browser().newContext({ viewport: { width: 1200, height: 850 } });
  const p = await ctx.newPage();
  const errors = []; p.on('pageerror', error => errors.push(error.message));
  const source = '- **设计评审**\n  - 保持原生体验\n  - `代码标记`\n- 验证暗黑模式\n\n3. 预览\n4. 保存\n\n> 内容清晰，操作克制。\n\n[产品网站](https://example.com)';
  const stamp = '2026-11-11T08:00:00Z';
  const messages = [source, '普通文本，保留换行。\n\n\n三个换行之后。', '- 长列表\n' + Array.from({length:15}, (_,i) => '  - 第 ' + (i+1) + ' 项').join('\n')].map((textContent, i) => ({id:'m'+i,type:'text',textContent,isCleared:false,isDeleted:false,createdAt:stamp,updatedAt:stamp}));
  let copied = ''; const uploads = [];
  await ctx.addInitScript(() => {
    localStorage.setItem('authToken', 'isolated-markdown');
    localStorage.setItem('userEmail', 'demo@example.com');
    localStorage.setItem('synca.language', 'zh-Hans');
  });
  await ctx.exposeBinding('fixtureCopy', (_, text) => { copied = text; });
  await ctx.addInitScript(() => Object.defineProperty(navigator, 'clipboard', {value:{writeText: text => window.fixtureCopy(text)}}));
  await ctx.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.hostname !== '127.0.0.1') return route.abort();
    if (url.pathname === '/me/access-status') return route.fulfill({json:{accessStatus:{plan:'pro',isUnlimited:true}}});
    if (url.pathname === '/message-categories') return route.fulfill({json:{categories:[]}});
    if (url.pathname === '/messages') return route.fulfill({json:{messages}});
    if (url.pathname === '/messages/file' || url.pathname === '/messages/image') {uploads.push(url.pathname);return route.fulfill({status:201,json:{id:'upload',type:'file',isCleared:false}});}
    return route.continue();
  });
  try {
    await p.goto('http://127.0.0.1:5198/');
    await p.waitForLoadState('networkidle');
    const fixturesResult = await p.evaluate(async () => {
      const { richListMarkdown } = await import('/src/utils/richListMarkdown.ts');
      const fixtures = [
        ['', null], ['<p>ordinary <b>text</b></p>', null],
        ['<ul><li>Run this:</li></ul><pre><code>if ready:\n    start()\n    finish()</code></pre>', null],
        ['<p>计划</p><ol start="3"><li>第一项<ul><li>子项</li></ul></li><li>第二项</li></ol><p>结束</p>', '计划\n3. 第一项\n   - 子项\n4. 第二项\n结束'],
        ['<ul><li onclick="alert(1)">one<br>continued<script>alert(1)</script><img src=x onerror=alert(1)></li><li>two &amp; three</li></ul>', '- one\n  continued\n- two & three'],
        ['<ul><li><p>one</p><p>continued</p><ol start="2"><li>nested</li></ol></li></ul>', '- one\n  continued\n  2. nested'],
      ];
      for (const [html, expected] of fixtures) {
        const actual = richListMarkdown(html);
        if (actual !== expected) throw new Error(JSON.stringify({html, expected, actual}));
      }
      return { clipboardFixtures: fixtures.length };
    });
    await p.locator('.message-bubble').first().waitFor();
    const first = p.locator('.message-bubble').filter({hasText:'设计评审'});
    if (await first.locator('ul').count() !== 2) throw new Error('nested list missing');
    await first.locator('.message-copy').click();
    if (copied !== source) throw new Error('copy changed Markdown source');
    const long = p.locator('.message-bubble').filter({hasText:'长列表'});
    await long.locator('.message-expand').click();
    if (await long.locator('.message-expand').getAttribute('aria-expanded') !== 'true') throw new Error('expand failed');
    await long.locator('.message-expand').click();
    await first.getByRole('button', {name:'编辑文本', exact:true}).click();
    if (await p.locator('.message-editor-input').inputValue() !== source) throw new Error('editor changed source');
    const paste = async (selector, withFile=false) => p.locator(selector).evaluate((el, withFile) => {
      el.focus();el.setSelectionRange(0,el.value.length);
      const data=new DataTransfer();data.setData('text/plain','one\nchild');data.setData('text/html','<ul><li>one<ul><li>child</li></ul></li></ul>');
      if(withFile)data.items.add(new File(['fixture'],'notes.txt',{type:'text/plain'}));
      el.dispatchEvent(new ClipboardEvent('paste',{clipboardData:data,bubbles:true,cancelable:true}));
    }, withFile);
    await paste('.message-editor-input');
    await p.waitForFunction(() => document.querySelector('.message-editor-input').value === '- one\n  - child');
    await p.getByRole('button', {name:'取消', exact:true}).click();
    await p.getByRole('button', {name:/放弃/, exact:false}).last().click();
    await paste('.input-bar textarea');
    await p.waitForFunction(() => document.querySelector('.input-bar textarea').value === '- one\n  - child');
    await paste('.input-bar textarea', true);
    await p.waitForFunction(() => !document.querySelector('.input-bar textarea').disabled);
    if(uploads[0] !== '/messages/file') throw new Error('attachment priority changed');
    await p.locator('.input-bar textarea').fill('');
    await first.locator('.message-expand').click();
    const screenshots=[];
    for(const [name,width,height,scheme] of [['desktop-light',1200,850,'light'],['desktop-dark',1200,850,'dark'],['mobile-light',390,844,'light'],['mobile-dark',390,844,'dark']]) {
      await p.setViewportSize({width,height});await p.emulateMedia({colorScheme:scheme});await p.waitForTimeout(300);
      await p.locator('.message-list').evaluate(el=>el.scrollTop=0);
      const path='/tmp/synca-markdown-'+name+'.png';await p.screenshot({path,fullPage:true});screenshots.push(path);
    }
    if(errors.length) throw new Error(errors.join('\n'));
    return {...fixturesResult,copyPreserved:true,editorPaste:true,inputPaste:true,attachmentPriority:true,folding:true,screenshots};
  } finally { await ctx.close(); }
}
