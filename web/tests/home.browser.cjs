/** Run with an existing Playwright Page. No app login or production writes. */
module.exports = async function checkHome(page, { baseURL = 'http://127.0.0.1:4181', screenshotDir } = {}) {
  const failures = [];
  const checks = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  for (const [path, language] of [['/home/', 'zh-Hans'], ['/home/zh-Hant/', 'zh-Hant'], ['/home/en/', 'en']]) {
    for (const [width, scheme] of [[1440, 'light'], [390, 'light'], [320, 'dark'], [768, 'dark']]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.emulateMedia({ colorScheme: scheme, reducedMotion: 'reduce' });
      const response = await page.goto(baseURL + path);
      await page.locator('footer').scrollIntoViewIfNeeded();
      await page.evaluate(async () => { await Promise.all([...document.images].map(image => image.decode().catch(() => {}))); });
      const result = await page.evaluate(() => ({
        language: document.documentElement.lang,
        overflow: document.documentElement.scrollWidth > innerWidth,
        brokenImages: [...document.images].filter(image => !image.complete || !image.naturalWidth).map(image => image.src),
        headings: document.querySelectorAll('h1').length,
        outsideAssets: [...document.querySelectorAll('img[src],link[rel=stylesheet],link[rel=icon],link[rel=apple-touch-icon]')].map(el => el.getAttribute('src') || el.getAttribute('href')).filter(path => !path.startsWith('/home/')),
        relativeServiceLinks: [...document.querySelectorAll('a[href]')].map(el => el.getAttribute('href')).filter(href => href.startsWith('/') && !href.startsWith('/home/')),
        scripts: document.querySelectorAll('script').length,
        webLinks: [...document.querySelectorAll('.button')].filter(a => a.getAttribute('href') === 'https://synca.haerth.cn/').length,
        unsafePageLinks: [...document.querySelectorAll('a[href]')].filter(a => !a.getAttribute('href').startsWith('#') && (a.target !== '_blank' || !a.relList.contains('noopener') || !a.relList.contains('noreferrer'))).map(a => a.href),
        missingAnchors: [...document.querySelectorAll('a[href^="#"]')].filter(a => !document.querySelector(a.getAttribute('href'))).map(a => a.href),
        missingAlt: document.querySelectorAll('img:not([alt])').length,
        horizontalActions: [...document.querySelectorAll('.button,.languages a')].filter(a => a.getBoundingClientRect().height < 44).length,
        canonical: document.querySelector('link[rel="canonical"]')?.href,
        registrations: [...document.querySelectorAll('.registration a')].map(a => a.textContent.trim()),
      }));
      const label = `${language} ${width}px ${scheme}`;
      if (response.status() !== 200 || result.language !== language || result.overflow || result.brokenImages.length || result.headings !== 1 || result.scripts || result.outsideAssets.length || result.relativeServiceLinks.length || result.webLinks !== 3 || result.unsafePageLinks.length || result.missingAnchors.length || result.missingAlt || result.horizontalActions || result.canonical !== 'https://synca.haerth.cn' + path || result.registrations.join('|') !== '浙ICP备2026013056号|浙公网安备33010602014403号') failures.push({ label, result });
      await page.evaluate(() => scrollTo(0, 0));
      if (screenshotDir && ((width === 1440 && language === 'zh-Hans') || (width === 390 && language === 'zh-Hans') || (width === 320 && language === 'en'))) await page.screenshot({ path: `${screenshotDir}/home-${language}-${width}-${scheme}.png`, fullPage: true });
      checks.push(label);
    }
  }
  // Locale links open a new tab and preserve the marketing page.
  await page.goto(baseURL + '/home/');
  const [localePage] = await Promise.all([page.waitForEvent('popup'), page.getByRole('link', { name: 'EN', exact: true }).click()]);
  await localePage.waitForLoadState('domcontentloaded');
  if (await localePage.locator('html').getAttribute('lang') !== 'en' || !page.url().endsWith('/home/')) failures.push('English new-tab navigation failed');
  await localePage.close();
  await page.goto(baseURL + '/home/');
  await page.keyboard.press('Tab');
  if (await page.locator(':focus').getAttribute('href') !== '#main') failures.push('Skip link is not first keyboard target');
  if (errors.length) failures.push({ errors });
  if (failures.length) throw new Error(JSON.stringify(failures, null, 2));
  return { passed: checks.length, checks, keyboard: 'skip link first', localeNavigation: 'passed', javascript: 'not required', pageErrors: errors };
};
