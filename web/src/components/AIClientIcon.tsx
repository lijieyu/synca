import { Link2 } from 'lucide-react';
import { matchAIClientBrand } from '../utils/aiClientBrand';

const icons = import.meta.glob<string>('../assets/ai-clients/*.png', { eager: true, query: '?url', import: 'default' });

export function AIClientIcon({ name }: { name: string }) {
  const brand = matchAIClientBrand(name);
  const src = brand && icons[`../assets/ai-clients/${brand.id}.png`];
  return <div className="ai-app-mark" aria-hidden="true" data-ai-brand={brand?.id ?? 'unknown'}>
    {src ? brand.template
      ? <span className="ai-client-mask" style={{ maskImage: `url("${src}")` }} />
      : <img src={src} alt="" draggable={false} style={{ transform: `scale(${brand.scale})` }} />
      : <Link2 size={20} />}
  </div>;
}
