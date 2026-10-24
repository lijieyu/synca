import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';

export const SYNCA_APP_STORE_URL = 'https://apps.apple.com/cn/app/synca-灵感记录-即刻同步/id6761647007';

export function PlanDialog({ onClose }: { onClose: () => void }) {
  const { t, i18n } = useTranslation();
  const { accessStatus: status } = useAuth();
  const storage = status?.storage;
  const isChinese = i18n.language.startsWith('zh');
  const paid = status?.isUnlimited === true;
  const lifetime = status?.unlimitedSource === 'lifetime';
  const planName = lifetime ? 'access.purchased_lifetime'
    : status?.storeProductId === 'org.haerth.synca.unlimited.monthly' ? 'access.purchased_monthly'
    : status?.storeProductId === 'org.haerth.synca.unlimited.yearly' ? 'access.purchased_yearly'
    : 'access.status_unlimited';
  const date = (value: string) => {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : new Intl.DateTimeFormat(i18n.language, { dateStyle: 'long' }).format(parsed);
  };
  const bytes = (value: number) => {
    const unit = value >= 1073741824 ? 'GB' : value >= 1048576 ? 'MB' : 'KB';
    const divisor = unit === 'GB' ? 1073741824 : unit === 'MB' ? 1048576 : 1024;
    return `${new Intl.NumberFormat(i18n.language, { maximumFractionDigits: 1 }).format(value / divisor)} ${unit}`;
  };
  const benefits = <ul>
    {['access.unlock_benefit_unlimited', 'access.purchase_shared_account', 'storage.paid_files', 'storage.paid_capacity'].map(key => <li key={key}>{t(key)}</li>)}
  </ul>;
  const legal = <div className="plan-legal-links">
    <a href={`https://synca.haerth.cn/${isChinese ? 'zh-hans' : 'en'}/privacy-policy`} target="_blank" rel="noopener noreferrer">{t('access.privacy_policy_link_title')}</a>
    <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" target="_blank" rel="noopener noreferrer">{t('access.terms_link_title')}</a>
  </div>;
  const download = <a className="plan-download-link" href={SYNCA_APP_STORE_URL} target="_blank" rel="noopener noreferrer">{t('access.download_to_purchase')}</a>;
  return <Modal title={t('access.center_title')} message="" onCancel={onClose}
    onConfirm={onClose} confirmText={t('common.ok')} hideCancel neutral>
    <div className="storage-plans">
      {!status ? <p role="status">{t('access.status_load_failed')}</p> : <>
        <section className={paid ? 'storage-plan-paid' : undefined}>
          <div className="plan-card-header"><h4>{t('access.current_plan_title')}</h4><span className="plan-badge">{t(paid ? 'access.status_unlimited' : 'access.free_title')}</span></div>
          {paid ? <>
            <h4>{t(planName)}</h4>
            <dl className="plan-dates">
              {status.purchaseDate && date(status.purchaseDate) && <><dt>{t('access.purchase_date_label')}</dt><dd>{date(status.purchaseDate)}</dd></>}
              {!lifetime && status.subscriptionExpiresAt && date(status.subscriptionExpiresAt) && <><dt>{t('access.subscription_expires_label')}</dt><dd>{date(status.subscriptionExpiresAt)}</dd></>}
            </dl>
            {benefits}{legal}
            {!lifetime && <div className="plan-upgrade"><h4>{t('access.lifetime_upgrade_title')}</h4><p>{t('access.option_lifetime_subtitle')}</p>{download}</div>}
          </> : <>
            <p>{t('access.current_free_summary', { used: status.todayUsed, limit: status.todayLimit ?? 20 })}</p>
            <ul><li>{t('access.free_daily_rule')}</li><li>{t('storage.free_benefits')}</li></ul>
          </>}
        </section>
        {!paid && <section className="storage-plan-paid">
          <h4>{t('access.unlock_title')}</h4>{benefits}
          <div className="plan-options">{['monthly', 'yearly', 'lifetime'].map(plan => <div key={plan}>
            <strong>{t(`access.option_${plan}_title`)}</strong><p>{t(`access.option_${plan}_subtitle`)}</p>
          </div>)}</div>
          {download}{legal}
        </section>}
        {storage && <div><label htmlFor="storage-usage">{t('storage.used')}</label>
          <p className="plan-usage">{bytes(storage.usedBytes)} / {bytes(storage.limitBytes)}</p>
          <progress id="storage-usage" value={Math.min(storage.usedBytes, storage.limitBytes)} max={Math.max(1, storage.limitBytes)} />
        </div>}
      </>}
    </div>
  </Modal>;
}
