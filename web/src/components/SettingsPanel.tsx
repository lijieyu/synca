import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { applyAppearance, readAppearancePreference, readLanguagePreference, resolveLanguage, type AppearancePreference, type LanguagePreference } from '../preferences';
export function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { t, i18n } = useTranslation();
  const [language, setLanguage] = useState(readLanguagePreference);
  const [appearance, setAppearance] = useState(readAppearancePreference);
  const [pointerInteraction, setPointerInteraction] = useState(false);
  return <Modal size="compact" className="settings-modal" title={t('preferences.title')} message="" confirmText={t('navigation.close')} onConfirm={onClose} onCancel={onClose} closeLabel={t('navigation.close')} hideCancel hideActions neutral>
    <div className="preferences-panel" data-pointer-interaction={pointerInteraction}
      onPointerDownCapture={() => setPointerInteraction(true)}
      onKeyDownCapture={event => {
        if (['Tab', 'ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight', 'Home', 'End', 'Enter', ' '].includes(event.key)) setPointerInteraction(false);
      }}
      onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget)) setPointerInteraction(false); }}>
      <label>{t('preferences.language')}<select aria-label={t('preferences.language')} value={language} onChange={e => {
        const value = e.target.value as LanguagePreference; setLanguage(value); localStorage.setItem('synca.language', value);
        void i18n.changeLanguage(resolveLanguage(value, navigator.languages));
      }}><option value="system">{t('preferences.system')}</option><option value="zh-Hans">简体中文</option><option value="zh-Hant">繁體中文</option><option value="en">English</option></select></label>
      <label>{t('preferences.appearance')}<select aria-label={t('preferences.appearance')} value={appearance} onChange={e => { const value = e.target.value as AppearancePreference; setAppearance(value); applyAppearance(value); }}>
        {(['system', 'light', 'dark'] as const).map(value => <option key={value} value={value}>{t(`preferences.${value}`)}</option>)}
      </select></label>
    </div>
  </Modal>;
}
