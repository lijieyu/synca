import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { SettingsChoice } from './SettingsChoice';
import { applyAppearance, readAppearancePreference, readLanguagePreference, resolveLanguage, type AppearancePreference, type LanguagePreference } from '../preferences';
export function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { t, i18n } = useTranslation();
  const [language, setLanguage] = useState(readLanguagePreference);
  const [appearance, setAppearance] = useState(readAppearancePreference);
  return <Modal size="compact" className="settings-modal" title={t('preferences.title')} message="" confirmText={t('navigation.close')} onConfirm={onClose} onCancel={onClose} closeLabel={t('navigation.close')} hideCancel hideActions neutral>
    <div className="preferences-panel">
      <div className="preferences-row"><span>{t('preferences.language')}</span><SettingsChoice<LanguagePreference> label={t('preferences.language')} value={language}
        options={[{ value: 'system', label: t('preferences.system') }, { value: 'zh-Hans', label: '简体中文' }, { value: 'zh-Hant', label: '繁體中文' }, { value: 'en', label: 'English' }]}
        onChange={value => {
          setLanguage(value); localStorage.setItem('synca.language', value);
          void i18n.changeLanguage(resolveLanguage(value, navigator.languages));
        }} /></div>
      <div className="preferences-row"><span>{t('preferences.appearance')}</span><SettingsChoice<AppearancePreference> label={t('preferences.appearance')} value={appearance}
        options={(['system', 'light', 'dark'] as const).map(value => ({ value, label: t(`preferences.${value}`) }))}
        onChange={value => { setAppearance(value); applyAppearance(value); }} /></div>
    </div>
  </Modal>;
}
