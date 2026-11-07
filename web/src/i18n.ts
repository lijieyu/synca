import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import en from './locales/en.json';
import zh from './locales/zh.json';
import zhHant from './locales/zh-Hant.json';
import { applyAppearance, readAppearancePreference, readLanguagePreference, resolveLanguage } from './preferences';
const queryLanguage = new URLSearchParams(window.location.search).get('lng');
const initialLanguage = queryLanguage ? resolveLanguage('system', [queryLanguage]) : resolveLanguage(readLanguagePreference(), navigator.languages);
void i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, 'zh-Hans': { translation: zh }, 'zh-Hant': { translation: zhHant } },
  lng: initialLanguage, fallbackLng: 'en', interpolation: { escapeValue: false },
});
i18n.on('languageChanged', language => { document.documentElement.lang = language; });
document.documentElement.lang = initialLanguage;
applyAppearance(readAppearancePreference());
window.addEventListener('languagechange', () => {
  if (readLanguagePreference() === 'system') void i18n.changeLanguage(resolveLanguage('system', navigator.languages));
});
export default i18n;
