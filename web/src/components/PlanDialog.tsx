import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';

export const SYNCA_APP_STORE_URL = 'https://apps.apple.com/cn/app/synca-灵感记录-即刻同步/id6761647007';

export function PlanContent({ showStorage = true }: { showStorage?: boolean } = {}) {
  const { t } = useTranslation();
  const { accessStatus: status } = useAuth();
  const paid = status?.isUnlimited === true;
  const benefits = <ul>
    {['access.unlock_benefit_unlimited', 'storage.paid_files', 'storage.paid_capacity', 'access.unlock_benefit_ai'].map(key => <li key={key}>{t(key)}</li>)}
  </ul>;
  const download = <a className="plan-download-link" href={SYNCA_APP_STORE_URL} target="_blank" rel="noopener noreferrer">{t('access.download_to_purchase')}</a>;
  return <div className="storage-plans">
      {showStorage && <StorageUsage />}
      {!status ? <p role="status">{t('access.status_load_failed')}</p> : <>
        <section className={paid ? 'storage-plan-paid' : undefined}>
          <div className="plan-card-header"><h4>{paid ? 'Synca Pro' : t('access.current_plan_title')}</h4>{paid && <span className="plan-activated">{t('polish.activated')}</span>}</div>
          {paid ? <>{benefits}
          </> : <>
            <ul><li>{t('access.free_daily_rule')}</li><li>{t('storage.free_types')}</li><li>{t('storage.free_benefits')}</li></ul>
          </>}
        </section>
        {!paid && <section className="storage-plan-paid">
          <div className="plan-card-header"><h4>{t('access.unlock_title')}</h4></div>{benefits}
          <div className="plan-price-line">
            <strong className="plan-price">¥28</strong>
            <span className="plan-purchase-kind">{t('access.buyout_label')}</span>
          </div>
          {download}
        </section>}

      </>}
    </div>;
}

export function PlanDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation();
  return <Modal size="standard" scrollBody title={t('access.center_title')} message="" onCancel={onClose} onConfirm={onClose} confirmText={t('common.ok')} hideCancel hideActions neutral><PlanContent /></Modal>;
}

export function StorageUsage() {
  const { t, i18n } = useTranslation();
  const { accessStatus } = useAuth();
  const storage = accessStatus?.storage;
  const bytes = (value: number) => {
    const unit = value >= 1073741824 ? 'GB' : value >= 1048576 ? 'MB' : 'KB';
    const divisor = unit === 'GB' ? 1073741824 : unit === 'MB' ? 1048576 : 1024;
    return `${new Intl.NumberFormat(i18n.language, { maximumFractionDigits: 1 }).format(value / divisor)} ${unit}`;
  };
  if (!storage) return null;
  return <div className="account-storage">
    <div className="account-storage-label"><span>{t('storage.used')}</span><span>{bytes(storage.usedBytes)} / {bytes(storage.limitBytes)}</span></div>
    <progress aria-label={t('storage.used')} value={Math.max(0, Math.min(storage.usedBytes, storage.limitBytes))} max={Math.max(1, storage.limitBytes)} />
  </div>;
}
