import { createRoot } from 'react-dom/client';
import { Toast } from '../src/components/Toast';
let root: ReturnType<typeof createRoot>;
export function showToast(message: string, variant: 'success' | 'error' = 'success') {
  if (!root) { const node = document.createElement('div'); document.body.append(node); root = createRoot(node); }
  root.render(<Toast key={message} message={message} variant={variant} visible duration={60000} onClose={() => root.render(null)} />);
}
export function hideToast() { root?.render(null); }
