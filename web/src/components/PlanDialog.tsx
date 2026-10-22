import { useTranslation } from 'react-i18next';
import { useAuth } from '../contexts/AuthContext';
import { Modal } from './Modal';

export function PlanDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation();
  const { accessStatus } = useAuth();
  const storage = accessStatus?.storage;
  return <Modal title={t('storage.title')} message="" onCancel={onClose}
    onConfirm={() => window.open('https://apps.apple.com/app/id6761647007', '_blank', 'noopener,noreferrer')}
    confirmText={t('access.go_to_appstore')} cancelText={t('common.ok')}>
    <div className="storage-plans">
      <section><h4>{t('storage.free_title')}</h4><p>{t('storage.free_benefits')}</p></section>
      <section className="storage-plan-paid"><h4>{t('storage.paid_title')}</h4>
        <ul><li>{t('storage.paid_files')}</li><li>{t('storage.paid_capacity')}</li><li>{t('access.unlock_benefit_unlimited', 'Unlimited new messages')}</li></ul>
      </section>
      {storage && <section><label htmlFor="storage-usage">{t('storage.used')}: {Math.ceil(storage.usedBytes / 1048576)} / {storage.limitBytes / 1048576} MB</label>
        <progress id="storage-usage" value={Math.min(storage.usedBytes, storage.limitBytes)} max={storage.limitBytes} /></section>}
      <p className="storage-notice">{t('storage.retention_notice')}</p>
    </div>
  </Modal>;
}
