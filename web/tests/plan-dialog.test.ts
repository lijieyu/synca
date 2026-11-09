import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { createInstance } from 'i18next';
import zh from '../src/locales/zh.json';
import en from '../src/locales/en.json';
import hant from '../src/locales/zh-Hant.json';
import type { AccessStatus } from '../src/api/client';
import { PlanDialog } from '../src/components/PlanDialog';
const state = vi.hoisted(() => ({ status: null as AccessStatus | null, language: 'zh' }));
const i18n = createInstance();
void i18n.init({ lng: 'zh', resources: { zh: { translation: zh }, en: { translation: en }, 'zh-Hant': { translation: hant } }, initImmediate: false });
vi.mock('../src/contexts/AuthContext', () => ({ useAuth: () => ({ accessStatus: state.status }) }));
vi.mock('react-i18next', () => ({ useTranslation: () => ({ t: i18n.getFixedT(state.language), i18n: { language: state.language } }) }));
vi.mock('../src/components/Modal', () => ({ Modal: ({ title, children }: { title: string; children: React.ReactNode }) => React.createElement('div', null, title, children) }));
const render = () => renderToStaticMarkup(React.createElement(PlanDialog, { onClose: () => {} }));
beforeEach(() => {
  vi.stubGlobal('React', React);
  state.language = 'zh';
  state.status = { plan: 'free', isUnlimited: false, isTrial: false, daysLeft: null, todayUsed: 3, todayLimit: 20 };
});
afterEach(() => vi.unstubAllGlobals());
it('shows free quota, native purchase options and product download link', () => {
  const html = render();
  for (const text of ['Synca Pro', '一次性买断']) expect(html).toContain(text);
  expect(html).not.toContain('今日 3/20');
  expect(html).not.toContain('Pro（月付）');
  expect(html).not.toContain('Pro（年付）');
  expect(html).toContain('id6761647007');
  expect(html).toContain('下载 Synca，在 App 内购买');
  expect(html).not.toContain('附件到期自动删除');
  expect(html).toContain('解锁文件传输，单个最大 200 MB');
  expect(html).toContain('图片保留 3 天');
  expect(html).toContain('图片和文件保留 30 天');
});
it('keeps lifetime ownership concise without purchase dates or another upgrade', () => {
  Object.assign(state.status!, { isUnlimited: true, plan: 'unlimited', unlimitedSource: 'lifetime', purchaseDate: '2026-04-11T12:00:00Z' });
  const html = render();
  expect(html).not.toContain('购买日期');
  expect(html).not.toContain('2026');
  expect(html).not.toContain(zh['access.current_plan_title']);
  expect(html).not.toContain('plan-dates');
  expect(html).toContain(zh.polish.activated);
  expect(html).not.toContain('下载 Synca');
  expect(html).not.toContain('免费版');
  expect(html).not.toContain('下次续费');
});
it('recognizes historical entitlement without upselling', () => {
  Object.assign(state.status!, { isUnlimited: true, unlimitedSource: 'subscription', storeProductId: 'org.haerth.synca.unlimited.yearly', subscriptionExpiresAt: '2027-04-11T12:00:00Z' });
  const html = render();
  expect(html).toContain('Synca Pro');
  expect(html).not.toContain('Pro（年付）');
  expect(html).not.toContain('下次续费');
  expect(html).not.toContain('升级终身版');
  expect(html).not.toContain('id6761647007');
});
it('uses English copy without changing the verified product destination', () => {
  state.language = 'en';
  const html = render();
  expect(html).toContain('https://apps.apple.com/cn/app/synca-灵感记录-即刻同步/id6761647007');
  expect(html).toContain(en['access.buyout_label']);
  expect(html).not.toContain('access.current_plan_title');
});
it('does not mislabel unknown account as free or offer a purchase', () => {
  state.status = null;
  const html = render();
  expect(html).not.toContain('id6761647007');
  expect(html).toContain(zh['access.status_load_failed']);
});

it('renders Traditional Chinese Pro benefits and retention notes', () => {
  state.language = 'zh-Hant';
  const html = render();
  for (const key of ['storage.free_types', 'storage.free_benefits', 'storage.paid_capacity']) expect(html).toContain(hant[key as keyof typeof hant]);
  expect(html).not.toContain('無限版');
});

it('shows verified mainland pricing with the App Store entry in all locales', () => {
  vi.stubEnv('VITE_PREVIEW_PRICING', 'true');
  try {
    for (const language of ['zh', 'zh-Hant', 'en']) {
      state.language = language;
      const html = render();
      expect(html).toContain('¥98');
      expect(html).toContain(i18n.getFixedT(language)('access.mainland_price_note'));
      expect(html).toContain('100 MB');
      expect(html).toContain('1 GB');
      expect(html).toContain('id6761647007');
      expect(html).toContain(i18n.getFixedT(language)('access.buyout_label'));
      for (const key of ['access.preview_price_notice', 'storage.retention_notice', 'access.purchase_shared_account', 'storage.lifetime_notice', 'access.ai_service_notice']) expect(html).not.toContain(i18n.getFixedT(language)(key));
    }
  } finally { vi.unstubAllEnvs(); }
});

it.each(['zh', 'zh-Hant', 'en'])('suppresses redundant Pro labels and stale lifetime renewal metadata in %s', (language) => {
  state.language = language;
  Object.assign(state.status!, { isUnlimited: true, unlimitedSource: 'lifetime', purchaseDate: '2026-04-11T12:00:00Z', subscriptionExpiresAt: '2027-04-11T12:00:00Z' });
  const html = render();
  const t = i18n.getFixedT(language);
  expect(html).not.toContain(t('access.current_plan_title'));
  expect(html).not.toContain(t('access.purchase_date_label'));
  expect(html).not.toContain(t('access.subscription_expires_label'));
  expect(html).toContain(t('polish.activated'));
  expect(html).toContain(t('storage.paid_capacity'));
});
it('keeps valid subscription dates while omitting malformed metadata', () => {
  Object.assign(state.status!, { isUnlimited: true, unlimitedSource: 'subscription', storeProductId: 'org.haerth.synca.unlimited.monthly', purchaseDate: 'invalid', subscriptionExpiresAt: '2027-04-11T12:00:00Z' });
  const html = render();
  expect(html).toContain('Synca Pro');
  expect(html).not.toContain(zh['access.purchased_monthly']);
  expect(html).not.toContain(zh['access.subscription_expires_label']);
  expect(html).not.toContain('2027');
  expect(html).not.toContain(zh['access.purchase_date_label']);
  expect(html).not.toContain(zh['access.current_plan_title']);
});

it.each(['zh', 'zh-Hant', 'en'])('uses API storage allowance for the current plan in %s', language => {
  state.language = language;
  Object.assign(state.status!, { isUnlimited: true, storage: { usedBytes: 1200 * 1048576, limitBytes: 1073741824, retentionDays: 30, imageLimitBytes: 50 * 1048576, fileLimitBytes: 200 * 1048576, canUploadFiles: true } });
  let html = render();
  expect(html).toContain('1 GB');
  expect(html).not.toContain('<li>2 GB');
  state.status!.storage!.limitBytes = 512 * 1048576;
  state.status!.storage!.retentionDays = 14;
  html = render();
  expect(html).toContain('512 MB');
  expect(html).toContain('14');
  expect(html).not.toContain('30');
});

it('uses live free daily and storage allowances without losing the paid offer', () => {
  Object.assign(state.status!, { todayLimit: 25, storage: { usedBytes: 0, limitBytes: 64 * 1048576, retentionDays: 2, imageLimitBytes: 50 * 1048576, fileLimitBytes: 0, canUploadFiles: false } });
  const html = render();
  expect(html).toContain('每日可新增 25 条记录');
  expect(html).toContain('64 MB 附件空间，图片保留 2 天');
  expect(html).toContain('1 GB 附件空间，图片和文件保留 30 天');
});
