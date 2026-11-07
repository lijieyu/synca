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
  for (const text of ['Synca Pro', '今日 3/20', 'Pro（月付）', 'Pro（年付）', 'Pro（终身）', '同一账号，iPhone、Mac 和 Web 共享 Pro 权益。']) expect(html).toContain(text);
  expect(html).toContain('id6761647007');
  expect(html).toContain('下载 Synca，在 App 内购买');
  expect(html).not.toContain('附件到期自动删除');
  expect(html).toContain('解锁文件传输，单个最大 200 MB');
  expect(html).toContain('图片保留 3 天');
  expect(html).toContain('图片和文件保留 30 天');
});
it('shows lifetime purchase date without selling another upgrade', () => {
  Object.assign(state.status!, { isUnlimited: true, plan: 'unlimited', unlimitedSource: 'lifetime', purchaseDate: '2026-04-11T12:00:00Z' });
  const html = render();
  expect(html).toContain('购买日期');
  expect(html).toContain('2026');
  expect(html).not.toContain('下载 Synca');
  expect(html).not.toContain('免费版');
  expect(html).not.toContain('下次续费');
});
it('shows yearly renewal and lifetime upgrade entry', () => {
  Object.assign(state.status!, { isUnlimited: true, unlimitedSource: 'subscription', storeProductId: 'org.haerth.synca.unlimited.yearly', subscriptionExpiresAt: '2027-04-11T12:00:00Z' });
  const html = render();
  expect(html).toContain('Pro（年付）');
  expect(html).toContain('下次续费');
  expect(html).toContain('升级终身版');
  expect(html).toContain('id6761647007');
});
it('uses English copy without changing the verified product destination', () => {
  state.language = 'en';
  const html = render();
  expect(html).toContain('https://apps.apple.com/cn/app/synca-灵感记录-即刻同步/id6761647007');
  expect(html).toContain(en['access.purchase_shared_account']);
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
  for (const key of ['storage.free_types', 'storage.free_benefits', 'storage.paid_capacity', 'storage.retention_notice', 'storage.lifetime_notice']) expect(html).toContain(hant[key as keyof typeof hant]);
  expect(html).not.toContain('無限版');
});
