import { useLayoutEffect, useRef, useState } from 'react';
import { Check } from 'lucide-react';
import './SyncFeedback.css';

/** Center in the record header; collapse to a check when the title needs the space. */
export function SyncFeedback({ sequence, label }: { sequence: number; label: string }) {
  const node = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [compact, setCompact] = useState(false);
  useLayoutEffect(() => {
    if (!sequence) return;
    setVisible(true);
    const timeout = window.setTimeout(() => setVisible(false), 2200);
    return () => window.clearTimeout(timeout);
  }, [sequence]);
  useLayoutEffect(() => {
    const element = node.current, header = element?.parentElement;
    if (!element || !header) return;
    const measure = () => {
      const bounds = header.getBoundingClientRect();
      const heading = header.querySelector('.stream-heading');
      const textEdges = heading ? [...heading.children].map(child => {
        const range = document.createRange(); range.selectNodeContents(child);
        return Math.min(range.getBoundingClientRect().right, child.getBoundingClientRect().right);
      }) : [];
      const left = textEdges.length ? Math.max(...textEdges) : header.querySelector('.mobile-category-trigger')?.getBoundingClientRect().right ?? bounds.left;
      const right = header.querySelector('.header-actions')?.getBoundingClientRect().left ?? bounds.right;
      const center = bounds.left + bounds.width / 2;
      const labelWidth = element.querySelector('span')?.scrollWidth ?? 0;
      setCompact(Math.min(center - left, right - center) < (labelWidth + 28) / 2 + 12);
    };
    const observer = new ResizeObserver(measure);
    observer.observe(header);
    header.querySelectorAll('.stream-heading, .header-actions').forEach(child => observer.observe(child));
    measure();
    return () => observer.disconnect();
  }, [label, visible]);
  return <div ref={node} className="sync-feedback" data-visible={visible} data-compact={compact} role="status" aria-live="polite" aria-atomic="true">
    <Check size={16} aria-hidden="true"/><span>{visible ? label : ''}</span>
  </div>;
}
