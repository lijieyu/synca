import { ArrowUpRight } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import './DeveloperSocialLink.css';

const developerProfileURL = 'https://www.xiaohongshu.com/user/profile/612f8178000000000201da34';

export function DeveloperSocialLink({ context = 'about' }: { context?: 'about' | 'feedback' }) {
  const { t } = useTranslation();
  const label = t(context === 'feedback' ? 'developer_social.contact' : 'developer_social.follow');
  return <a className="developer-social-link" href={developerProfileURL} target="_blank" rel="noopener noreferrer"
    aria-label={`${label}, ${t('developer_social.external')}`}>
    <img className="developer-social-logo" src="/xiaohongshu.png" width={24} height={24} alt="" aria-hidden="true"/><span>{label}</span>
    <ArrowUpRight size={16} aria-hidden="true" />
  </a>;
}
