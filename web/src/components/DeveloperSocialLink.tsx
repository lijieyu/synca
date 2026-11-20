import { ArrowUpRight } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import './DeveloperSocialLink.css';

const developerProfileURL = 'https://www.xiaohongshu.com/user/profile/612f8178000000000201da34';

export function DeveloperSocialLink() {
  const { t } = useTranslation();
  return <a className="developer-social-link" href={developerProfileURL} target="_blank" rel="noopener noreferrer"
    aria-label={`${t('developer_social.follow')}, ${t('developer_social.external')}`}>
    <span className="developer-social-icon" aria-hidden="true">小红书</span><span>{t('developer_social.follow')}</span>
    <ArrowUpRight size={16} aria-hidden="true" />
  </a>;
}
