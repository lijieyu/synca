import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Modal } from './Modal';
import { applyAppearance, readAppearancePreference, readLanguagePreference, resolveLanguage, type AppearancePreference, type LanguagePreference } from '../preferences';
import { chooseDownloadDirectory, downloadDirectoryName, resetDownloadDirectory, supportsDownloadDirectory } from '../utils/downloads';
export function SettingsPanel({ onClose }: { onClose: () => void }) {
  const { t, i18n } = useTranslation();
  const [language, setLanguage] = useState(readLanguagePreference);
  const [appearance, setAppearance] = useState(readAppearancePreference);
  const [directory, setDirectory] = useState(downloadDirectoryName);
  const [error, setError] = useState(false);
  return <Modal title={t('preferences.title')} message="" confirmText={t('navigation.close')} onConfirm={onClose} onCancel={onClose} closeLabel={t('navigation.close')} hideCancel neutral>
    <div className="preferences-panel">
      <label>{t('preferences.language')}<select aria-label={t('preferences.language')} value={language} onChange={e => {
        const value = e.target.value as LanguagePreference; setLanguage(value); localStorage.setItem('synca.language', value);
        void i18n.changeLanguage(resolveLanguage(value, navigator.languages));
      }}><option value="system">{t('preferences.system')}</option><option value="zh-Hans">简体中文</option><option value="zh-Hant">繁體中文</option><option value="en">English</option></select></label>
      <label>{t('preferences.appearance')}<select aria-label={t('preferences.appearance')} value={appearance} onChange={e => { const value = e.target.value as AppearancePreference; setAppearance(value); applyAppearance(value); }}>
        {(['system', 'light', 'dark'] as const).map(value => <option key={value} value={value}>{t(`preferences.${value}`)}</option>)}
      </select></label>
      <div className="download-preference"><span>{t('preferences.download_location')}</span><strong>{directory ?? t('preferences.browser_managed')}</strong>
        {supportsDownloadDirectory() && <div><button onClick={async () => { setError(false); try { await chooseDownloadDirectory(); setDirectory(downloadDirectoryName()); } catch (e) { if (!(e instanceof DOMException && e.name === 'AbortError')) setError(true); } }}>{t('preferences.choose_folder')}</button>{directory && <button onClick={() => { resetDownloadDirectory(); setDirectory(null); }}>{t('preferences.reset_folder')}</button>}</div>}
        <p>{t(supportsDownloadDirectory() ? 'preferences.folder_session' : 'preferences.browser_hint')}</p>
        {error && <p role="alert">{t('preferences.folder_failed')}</p>}
      </div>
    </div>
  </Modal>;
}
