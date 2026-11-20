// Run against an authenticated fixture account. The shared renderer behaves the same on Web and Electron.
export default async (page, { desktop, screenshot }) => {
  const check = (value, message) => { if (!value) throw Error(message); };
  const source = [
    '# 发布记录', '', '## 验收', '', '- [x] 输入', '- [ ] 同步', '',
    '#### 四级', '##### 五级', '###### 六级', '', '<u>标注</u>', '', '~~草案~~', '', '---', '', '| 平台 | 状态 |', '| :--- | ---: |', '| Web | **完成** |',
    '', '```js', 'const value = "<tag>";', '```',
  ].join('\n');
  const input = page.locator('.input-bar textarea');
  await input.fill('进入设置前的草稿');
  await page.locator('.settings-entry').click();
  const settings = page.locator('.desk-settings');
  await settings.waitFor();
  check(await settings.getByRole('button', {name:'桌面',exact:true}).count() === Number(desktop), 'desktop capability mismatch');
  await settings.getByRole('button', {name:/账号与套餐/}).click();
  await settings.locator('.account-panel').waitFor();
  if(!desktop){
    await page.goBack();
    check(await input.inputValue()==='进入设置前的草稿','browser back lost draft');
    await page.goForward();
    await settings.locator('.account-panel').waitFor();
  }
  await settings.getByRole('button', {name:'关于',exact:true}).click();
  await settings.locator('.about-panel').waitFor();
  await settings.getByRole('button', {name:'通用',exact:true}).click();
  await settings.locator('select').first().selectOption('dark');
  await settings.locator('select').nth(1).selectOption('en');
  await settings.getByRole('button',{name:'General',exact:true}).waitFor();
  await settings.locator('select').nth(1).selectOption('zh-Hans');
  await settings.locator('.settings-title button').click();
  check(await input.inputValue()==='进入设置前的草稿','lost draft');
  await input.fill(source); await input.press('Enter');
  const bubble=page.locator('.message-bubble').filter({has:page.getByRole('heading',{name:'发布记录'})});
  await bubble.waitFor();
  check(await bubble.locator('input[type=checkbox]:enabled').count()===2,'task list');
  check(await bubble.locator('th').count()===2 && await bubble.locator('td strong').innerText()==='完成','table');
  check(await bubble.locator('del').innerText()==='草案' && await bubble.locator('hr').count()===1,'strike/rule');
  check((await bubble.locator('pre code').textContent()).trim()==='const value = "<tag>";','code fidelity');
  await bubble.locator('.message-expand').click();
  const sizes = await bubble.locator('h4,h5,h6').evaluateAll(headings => headings.map(h => parseFloat(getComputedStyle(h).fontSize)));
  check(sizes.length === 3 && sizes[0] > sizes[1] && sizes[1] > sizes[2], 'heading hierarchy');
  check(await bubble.locator('u').innerText() === '标注', 'inline underline');
  const task = bubble.getByRole('checkbox', { name: '同步', exact: true });
  await task.focus();
  await task.press('Space');
  await bubble.locator('input[aria-label="同步"]:checked').waitFor();
  check(await bubble.locator('.message-expand').getAttribute('aria-expanded') === 'true', 'toggle collapsed message');
  check(await task.evaluate(el => el === document.activeElement), 'toggle lost keyboard focus');
  const checkedSource = source.replace('- [ ] 同步', '- [x] 同步');
  if(screenshot) await page.screenshot({path:screenshot});
  await bubble.getByRole('button',{name:'编辑文本',exact:true}).click();
  const editor=page.locator('.message-editor-input');
  check(await editor.inputValue()===checkedSource,'editor source');
  const amended=checkedSource.replace('~~草案~~','~~已归档~~');
  await editor.fill(amended); await editor.press('Control+Enter');
  await editor.waitFor({state:'detached'});
  await page.reload();
  await page.locator('.message-markdown del').filter({hasText:'已归档'}).waitFor();
  await bubble.getByRole('button',{name:'编辑文本',exact:true}).click();
  check(await editor.inputValue()===amended,'saved source after reload');
  await page.getByRole('button',{name:'取消',exact:true}).click();
}
