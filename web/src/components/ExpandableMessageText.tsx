import { useLayoutEffect, useId, useRef, useState, type ReactNode } from 'react';
import { useTranslation } from 'react-i18next';

/** Measure actual wrapping so both newline-heavy and unbroken text fold at six lines. */
export function ExpandableMessageText({ text, children }: { text: string; children: ReactNode }) {
  const { t } = useTranslation();
  const content = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [overflowing, setOverflowing] = useState(false);
  const id = useId();
  useLayoutEffect(() => {
    const element = content.current;
    if (!element) return;
    const measure = () => {
      const lineHeight = Number.parseFloat(getComputedStyle(element).lineHeight);
      setOverflowing(element.scrollHeight > lineHeight * 6 + 1);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [text]);
  return <>
    <div ref={content} id={id} className={`message-content${expanded ? '' : ' message-content-collapsed'}`} onFocusCapture={() => setExpanded(true)}>{children}</div>
    {overflowing && <button className="message-expand" aria-expanded={expanded} aria-controls={id} onClick={() => setExpanded(!expanded)}>{t(expanded ? 'message_bubble.collapse' : 'message_bubble.expand')}</button>}
  </>;
}
