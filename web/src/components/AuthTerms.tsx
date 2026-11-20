import { useTranslation } from 'react-i18next';
export function AuthTerms() {
  const { t, i18n } = useTranslation();
  const locale = i18n.language.startsWith('zh') ? 'zh-hans' : 'en';
  return <p className="auth-terms">{t('email_auth.terms_prefix')} <a href={`https://synca.haerth.cn/${locale}/terms-of-use`} target="_blank" rel="noopener noreferrer">{t('email_auth.terms')}</a> {t('email_auth.and')} <a href={`https://synca.haerth.cn/${locale}/privacy-policy`} target="_blank" rel="noopener noreferrer">{t('navigation.privacy')}</a></p>;
}
