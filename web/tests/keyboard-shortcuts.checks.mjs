// Runs against the real UI with the existing isolated API fixture. Never touches live records.
export async function keyboardShortcutChecks({ fixture, check, assert, out }) {
  for (const desktop of [false, true, 'Windows']) await check(`fixed shortcut help (${desktop === 'Windows' ? 'Windows' : desktop ? 'Mac' : 'Web'})`, async () => {
    const f = await fixture(1100, 760, desktop), p = f.page;
    try {
      await p.locator('.settings-entry').click();
      await p.getByRole('button', { name: '通用', exact: true }).click();
      const section = p.locator('.settings-shortcuts');
      await section.waitFor();
      assert.match(await section.innerText(), /不支持修改/);
      assert.equal(await section.locator('button,input,select,[tabindex]').count(), 0);
      assert.equal(await section.locator('dt').count(), desktop === 'Windows' ? 5 : desktop ? 6 : 2);
      const body = p.locator('.desk-detail-body:visible');
      assert(await body.evaluate(el => el.scrollHeight <= el.clientHeight + 1), 'normal desktop has no settings scroll');
      if (out) await p.screenshot({ path: out + `/shortcuts-${desktop === 'Windows' ? 'windows' : desktop ? 'mac' : 'web'}-light.png` });
      await p.getByRole('combobox', {name:'外观'}).click();
      await p.getByRole('option', {name:'深色',exact:true}).click();
      if (out) await p.screenshot({ path: out + `/shortcuts-${desktop === 'Windows' ? 'windows' : desktop ? 'mac' : 'web'}-dark.png` });
      await p.setViewportSize({ width:640, height:500 });
      await p.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      assert.equal(await p.locator('.desk-settings').count(), 1);
      const bounds = await section.boundingBox();
      assert(bounds.x >= 0 && bounds.x + bounds.width <= 640, 'minimum window has no horizontal overflow');
      if (out) await p.screenshot({ path: out + `/shortcuts-${desktop === 'Windows' ? 'windows' : desktop ? 'mac' : 'web'}-minimum.png` });
      await p.getByRole('combobox', {name:'语言'}).click();
      await p.getByRole('option', {name:'English',exact:true}).click();
      assert.match(await section.innerText(), /cannot be changed/);
      await p.setViewportSize({width:512,height:400});
      await section.locator('dd').last().scrollIntoViewIfNeeded();
      assert(await section.locator('dd').last().isVisible(), 'help remains available when the layout narrows');
      assert.deepEqual(f.errors, []);
    } finally { await f.ctx.close(); }
  });

  for (const platform of ['macOS', 'Windows']) await check(`${platform} clear shortcut: confirmation, scope, drafts, repeat and IME`, async () => {
    const windows = platform === 'Windows', modifier = windows ? 'Control' : 'Meta';
    const combo = modifier + '+Shift+' + (windows ? 'Delete' : 'Backspace');
    const f = await fixture(1100, 760, windows ? 'Windows' : true), p = f.page, clears = [];
    try {
      await f.ctx.route('**/messages/delete-completed', async route => {
        clears.push(route.request().postDataJSON());
        await route.fulfill({json:{ok:true}});
      });
      const composer = p.locator('.input-bar textarea');
      await composer.fill('尚未发送的草稿');
      await p.keyboard.press(combo);
      const dialog = p.getByRole('dialog');
      await dialog.waitFor();
      assert.match(await dialog.innerText(), /1/);
      assert.equal(clears.length, 0);
      await p.keyboard.press(combo);
      assert.equal(await dialog.count(), 1);
      assert.equal(clears.length, 0);
      await p.keyboard.press('Escape');
      assert.equal(await composer.inputValue(), '尚未发送的草稿');
      for (const extra of [{repeat:true}, {isComposing:true}, {keyCode:229}, {altKey:true}]) {
        await p.evaluate(({extra, windows}) => window.dispatchEvent(new KeyboardEvent('keydown', {key:windows?'Delete':'Backspace',metaKey:!windows,ctrlKey:windows,shiftKey:true,bubbles:true,cancelable:true,...extra})), {extra,windows});
        assert.equal(await dialog.count(), 0);
      }
      await p.locator('[data-category-id=inbox]').click();
      await p.keyboard.press(combo);
      await dialog.waitFor();
      assert.match(await dialog.innerText(), /默认/);
      await dialog.locator('.modal-btn-destructive').click();
      await dialog.waitFor({state:'detached'});
      assert.deepEqual(clears, [{categoryId:'inbox'}]);
      await p.locator('.category-all').click();
      await p.evaluate(() => window.dispatchEvent(new Event('fixture-clear-completed')));
      await dialog.waitFor();
      await dialog.locator('.modal-btn-destructive').click();
      await dialog.waitFor({state:'detached'});
      assert.deepEqual(clears, [{categoryId:'inbox'}, {categoryId:null}]);
      await p.locator('[data-category-id=empty]').click();
      await p.keyboard.press(combo);
      assert.equal(await dialog.count(), 0);
      await p.locator('.category-all').click();
      await p.locator('.settings-entry').click();
      await p.keyboard.press(combo);
      assert.equal(await p.locator('.modal-content').count(), 0);
      await p.keyboard.press('Escape');
      await p.keyboard.press(modifier + '+f');
      await p.locator('.message-search-field input').waitFor();
      await p.keyboard.press(combo);
      assert.equal(await p.getByRole('dialog').count(), 1);
      assert.equal(await p.locator('.message-search-field input').count(), 1);
      assert.deepEqual(f.errors, []);
    } finally { await f.ctx.close(); }
  });

  await check('Web does not claim the browser clear-data shortcut', async () => {
    const f = await fixture(), p = f.page;
    try {
      const unhandled = await p.evaluate(() => window.dispatchEvent(new KeyboardEvent('keydown', {key:'Backspace',metaKey:true,shiftKey:true,bubbles:true,cancelable:true})));
      assert.equal(unhandled, true);
      assert.equal(await p.evaluate(() => window.dispatchEvent(new KeyboardEvent('keydown', {key:'Delete',ctrlKey:true,shiftKey:true,bubbles:true,cancelable:true}))), true);
      assert.equal(await p.getByRole('dialog').count(), 0);
      assert(!/⌘|⇧/.test(await p.getByRole('button', {name:'清除已完成',exact:true}).getAttribute('title')));
    } finally { await f.ctx.close(); }
  });
}
