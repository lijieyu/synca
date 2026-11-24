// Run through the browser-test harness against the local Vite server on port 5199.
async (page) => {
  const context = await page.context().browser().newContext({ viewport: { width: 1200, height: 850 } });
  const p = await context.newPage();
  const errors = [];
  p.on('pageerror', error => errors.push(error.message));
  const stamp = '2026-11-10T08:00:00Z';
  const categories = [{ id: 'work', name: '长分类 LongCategory'.repeat(30), color: 'sky', createdAt: stamp, updatedAt: stamp }];
  const messages = Array.from({ length: 35 }, (_, i) => ({
    id: `overflow-${i}`, type: 'text', textContent: `牛奶 ${'LongUnbrokenContent'.repeat(40)}`,
    fileName: `${'LongUnbrokenFilename'.repeat(20)}.txt`, categoryId: 'work', isCleared: true,
    isDeleted: false, createdAt: stamp, updatedAt: stamp,
  }));
  const assert = (condition, message) => { if (!condition) throw new Error(message); };
  await context.addInitScript(() => {
    localStorage.setItem('authToken', 'isolated-search-overflow');
    localStorage.setItem('userEmail', 'demo@example.com');
    localStorage.setItem('synca.language', 'zh-Hans');
  });
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.hostname !== '127.0.0.1') return route.abort();
    if (url.pathname === '/me/access-status') return route.fulfill({ json: { email: 'demo@example.com', accessStatus: { plan: 'pro', isUnlimited: true, todayUsed: 0 } } });
    if (url.pathname === '/messages') return route.fulfill({ json: { messages } });
    if (url.pathname === '/message-categories') return route.fulfill({ json: { categories } });
    return route.continue();
  });
  const measurements = [];
  const inspect = async label => {
    const sizes = await p.evaluate(() => {
      const selectors = ['.message-search-modal', '.message-search-results'];
      return selectors.flatMap(selector => {
        const element = document.querySelector(selector);
        if (!element) return [];
        return { selector, clientWidth: element.clientWidth, scrollWidth: element.scrollWidth,
          height: element.getBoundingClientRect().height, width: element.getBoundingClientRect().width,
          scrollbarWidth: element.offsetWidth - element.clientWidth };
      });
    });
    measurements.push({ label, sizes });
    for (const size of sizes) assert(size.scrollWidth <= size.clientWidth, `${label}: ${size.selector} overflows ${size.scrollWidth - size.clientWidth}px (${JSON.stringify(sizes)})`);
    return sizes;
  };
  try {
    await p.goto('http://127.0.0.1:5199/');
    await p.getByRole('button', { name: '搜索记录', exact: true }).click();
    await p.getByRole('searchbox').fill('牛奶');
    await p.locator('.message-search-result').first().waitFor();
    // Wait for the existing opening animation before comparing fixed dimensions.
    await p.waitForFunction(() => document.querySelector('.message-search-modal')?.getBoundingClientRect().width === 640);
    await p.screenshot({ path: '/tmp/synca-search-overflow-current.png' });
    const nativeSizes = await inspect('native-desktop');
    assert(nativeSizes[0].width === 640 && nativeSizes[0].height === 560, 'desktop search dimensions changed');
    const fieldHeight = await p.locator('.message-search-field').evaluate(element => element.clientHeight);
    // Explicit scrollbar dimensions exercise classic, space-consuming gutters even on overlay hosts.
    await p.addStyleTag({ content: `
      .message-search-modal, .message-search-results { scrollbar-color:auto; }
      .message-search-modal::-webkit-scrollbar, .message-search-results::-webkit-scrollbar { width:15px; height:15px; }
      .message-search-modal::-webkit-scrollbar-thumb, .message-search-results::-webkit-scrollbar-thumb { background:#999; }
    ` });
    for (const width of [1200, 640, 639, 390, 320]) {
      await p.setViewportSize({ width, height: 850 });
      for (const colorScheme of ['light', 'dark']) {
        await p.emulateMedia({ colorScheme });
        const sizes = await inspect(`classic-${width}-${colorScheme}`);
        assert(sizes[1].scrollbarWidth === 15, 'classic scrollbar gutter was not exercised');
        await p.screenshot({ path: `/tmp/synca-search-overflow-after-${width}-${colorScheme}.png` });
      }
    }
    await p.setViewportSize({ width: 1200, height: 850 });
    await p.getByRole('searchbox').fill('niunai');
    await p.waitForFunction(() => document.querySelector('.message-search-result mark')?.textContent === '牛奶');
    assert(await p.locator('.message-search-result').count() === messages.length, 'pinyin results changed');
    await p.getByRole('searchbox').dispatchEvent('compositionstart');
    await p.getByRole('searchbox').fill('ni');
    await p.getByRole('searchbox').dispatchEvent('keydown', { key: 'Escape', isComposing: true });
    assert(await p.getByRole('dialog').count() === 1, 'IME Escape dismissed search');
    assert(await p.locator('.message-search-result').count() === messages.length, 'IME draft replaced committed results');
    await p.getByRole('searchbox').fill('牛奶');
    await p.getByRole('searchbox').dispatchEvent('compositionend', { data: '牛奶' });
    await p.locator('.message-search-results').evaluate(element => { element.scrollTop = element.scrollHeight; });
    assert(await p.locator('.message-search-results').evaluate(element => element.scrollTop > 0), 'vertical results scrolling broken');
    await p.getByRole('button', { name: '清除搜索', exact: true }).click();
    await inspect('empty-desktop');
    assert(await p.locator('.message-search-field').evaluate(element => element.clientHeight) === fieldHeight, 'search field height changed');
    await p.getByRole('searchbox').fill('不存在匹配');
    await p.getByText('没有找到相关记录', { exact: true }).waitFor();
    await inspect('zero-results-desktop');
    await p.keyboard.press('Escape');
    assert(await p.getByRole('dialog').count() === 0, 'Escape no longer dismisses search');
    await p.evaluate(() => localStorage.setItem('synca.language', 'en'));
    await p.reload();
    await p.locator('.search-trigger').click();
    await p.getByRole('searchbox').fill('牛奶');
    await p.locator('.message-search-result').first().waitFor();
    await p.waitForFunction(() => document.querySelector('.message-search-modal')?.getBoundingClientRect().width === 640);
    await inspect('english-desktop');
    await p.setViewportSize({ width: 1200, height: 360 });
    const shortSizes = await inspect('short-desktop');
    assert(shortSizes[0].height === 328, 'short-window dialog does not fit the viewport');
    assert(errors.length === 0, errors.join('\n'));
    return { passed: true, measurements, checks: ['fixed dimensions', 'native and classic scrollbars', 'long text/file/category', '320/390/639/640/1200 widths', 'short viewport', 'Chinese/English', 'light/dark', 'pinyin', 'IME Escape', 'vertical scrolling', 'empty/zero results', 'fixed field height'] };
  } finally {
    await context.close();
  }
}
