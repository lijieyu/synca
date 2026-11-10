import { ArrowUpRight } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import './DeveloperSocialLink.css';

const developerProfileURL = 'https://www.xiaohongshu.com/user/profile/612f8178000000000201da34';

export function DeveloperSocialLink({ purpose }: { purpose: 'follow' | 'contact' }) {
  const { t } = useTranslation();
  return <a className="developer-social-link" href={developerProfileURL} target="_blank" rel="noopener noreferrer"
    aria-label={`${t(`developer_social.${purpose}`)}, ${t('developer_social.external')}`}>
    <span className="developer-social-mark" aria-hidden="true">小红书</span>
    <span className="developer-social-title">{t(`developer_social.${purpose}`)}</span>
    <ArrowUpRight size={16} aria-hidden="true" />
  </a>;
}
