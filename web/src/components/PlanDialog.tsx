import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';

export const SYNCA_APP_STORE_URL = 'https://apps.apple.com/cn/app/synca-灵感记录-即刻同步/id6761647007';

export function PlanContent() {
  const { t, i18n } = useTranslation();
  const { accessStatus: status } = useAuth();
  const storage = status?.storage;
  const isChinese = i18n.language.startsWith('zh');
  const paid = status?.isUnlimited === true;
  const lifetime = status?.unlimitedSource === 'lifetime';
  const purchaseDate = !lifetime && status?.purchaseDate ? date(status.purchaseDate) : null;
  const renewalDate = !lifetime && status?.subscriptionExpiresAt ? date(status.subscriptionExpiresAt) : null;
  const planName = lifetime ? 'access.purchased_lifetime'
    : status?.storeProductId === 'org.haerth.synca.unlimited.monthly' ? 'access.purchased_monthly'
    : status?.storeProductId === 'org.haerth.synca.unlimited.yearly' ? 'access.purchased_yearly'
    : 'access.status_unlimited';
  function date(value: string) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : new Intl.DateTimeFormat(i18n.language, { dateStyle: 'long' }).format(parsed);
  }
  const bytes = (value: number) => {
    const unit = value >= 1073741824 ? 'GB' : value >= 1048576 ? 'MB' : 'KB';
    const divisor = unit === 'GB' ? 1073741824 : unit === 'MB' ? 1048576 : 1024;
    return `${new Intl.NumberFormat(i18n.language, { maximumFractionDigits: 1 }).format(value / divisor)} ${unit}`;
  };
  const benefits = <ul>
    {['access.unlock_benefit_unlimited', 'storage.paid_files', 'storage.paid_capacity', 'access.unlock_benefit_ai'].map(key => <li key={key}>{t(key)}</li>)}
  </ul>;
  const legal = <div className="plan-legal-links">
    <a href={`https://synca.haerth.cn/${isChinese ? 'zh-hans' : 'en'}/privacy-policy`} target="_blank" rel="noopener noreferrer">{t('access.privacy_policy_link_title')}</a>
    <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" target="_blank" rel="noopener noreferrer">{t('access.terms_link_title')}</a>
  </div>;
  const previewPricing = import.meta.env.VITE_PREVIEW_PRICING === 'true';
  const download = previewPricing ? null : <a className="plan-download-link" href={SYNCA_APP_STORE_URL} target="_blank" rel="noopener noreferrer">{t('access.download_to_purchase')}</a>;
  return <div className="storage-plans">
      {!status ? <p role="status">{t('access.status_load_failed')}</p> : <>
        <section className={paid ? 'storage-plan-paid' : undefined}>
          <div className="plan-card-header"><h4>{t(paid ? planName : 'access.current_plan_title')}</h4><span className={`plan-badge${paid ? " plan-badge-pro" : ""}`}>{t(paid ? 'access.status_unlimited' : 'access.free_title')}</span></div>
          {paid ? <>
            {(purchaseDate || renewalDate) && <dl className="plan-dates">
              {purchaseDate && <><dt>{t('access.purchase_date_label')}</dt><dd>{purchaseDate}</dd></>}
              {renewalDate && <><dt>{t('access.subscription_expires_label')}</dt><dd>{renewalDate}</dd></>}
            </dl>}
            {benefits}{legal}
          </> : <>
            <ul><li>{t('access.free_daily_rule')}</li><li>{t('storage.free_types')}</li><li>{t('storage.free_benefits')}</li></ul>
          </>}
        </section>
        {!paid && <section className="storage-plan-paid">
          <div className="plan-card-header"><h4>{t('access.unlock_title')}</h4><span className="plan-badge plan-badge-pro">Pro</span></div>{benefits}
          <div className="plan-price-line">
            {previewPricing && <strong className="plan-price">{t('access.preview_lifetime_price')}</strong>}
            <span className="plan-purchase-kind">{t('access.buyout_label')}</span>
          </div>
          {download}{legal}
        </section>}
        {storage && <div><label htmlFor="storage-usage">{t('storage.used')}</label>
          <p className="plan-usage">{bytes(storage.usedBytes)} / {bytes(storage.limitBytes)}</p>
          <progress id="storage-usage" value={Math.min(storage.usedBytes, storage.limitBytes)} max={Math.max(1, storage.limitBytes)} />
        </div>}
      </>}
    </div>;
}

export function PlanDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation();
  return <Modal size="standard" scrollBody title={t('access.center_title')} message="" onCancel={onClose} onConfirm={onClose} confirmText={t('common.ok')} hideCancel hideActions neutral><PlanContent /></Modal>;
}
