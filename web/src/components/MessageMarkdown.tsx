import { createContext, Fragment, useContext } from 'react';
import Markdown, { type Components } from 'react-markdown';
import type { Root as HtmlRoot, Element, ElementContent } from 'hast';
import remarkGfm from 'remark-gfm';
import type { Root, RootContent, PhrasingContent } from 'mdast';

const elements = [
  'p', 'br', 'ul', 'ol', 'li', 'strong', 'em', 'blockquote', 'code', 'a',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'hr', 'del', 'input',
  'u', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
];
// Keep plain-text records on the whitespace-preserving path.
const blockMarker = /^ {0,3}(?:#{1,6}(?:[ \t]|$)|`{3,}|~{3,}|(?:=[= \t]*|[-_*](?:[ \t]*[-_*]){2,})[ \t]*$|\|?[ \t]*:?-+:?[ \t]*\|)/m;
const strikeOrImage = /~~[^\n]+?~~|!\[/;
const basicMarkdown = /(^|\n) {0,3}(?:(?:[-+*]|\d+[.)])(?:[ \t]|\r?\n)|> ?)|\*\*[^\n]+\*\*|__[^\n]+__|\*(?!\s)[^*\n]*\S\*|(?:^|[^\p{L}\p{N}_])_(?!\s)[^_\n]*\S_(?![\p{L}\p{N}_])|`[^`\n]+`|(?<!!)\[[^\]\n]+\]\([^\n]+\)/u;
const urlPattern = /(https?:\/\/[^\s<>"{}|\\^`[\]，。！？；：、]+[^\s<>"{}|\\^`[\],.)!?;:，。！？；：、])/g;

/** GFM supplies bare URL detection; keep unsupported syntax literal instead of losing data. */
function preserveImageSource({ source }: { source: string }) {
  return (tree: Root) => {
    function visit(node: Root | RootContent | PhrasingContent) {
      if (!('children' in node)) return;
      node.children = node.children.map(child => {
        if (child.type === 'image' || child.type === 'imageReference') {
          return { type: 'text' as const, value: source.slice(child.position?.start.offset, child.position?.end.offset) };
        }
        visit(child);
        return child;
      }) as typeof node.children;
    }
    visit(tree);
  };
}

interface TaskControls {
  onTaskToggle?: (offset: number) => void;
  taskPending?: boolean;
  taskLabel?: string;
}

const Tasks = createContext<TaskControls>({});
const underline = /<u>[^\r\n]+?<\/u>/;
function inlineText(node: ElementContent): string {
  if (node.type === 'text' || node.type === 'raw') return node.value;
  return node.type === 'element' ? node.children.map(inlineText).join('') : '';
}

// Only GFM creates input elements. Raw HTML remains inert throughout this pass.
function enhanceMessage({ source }: { source: string }) {
  return (tree: HtmlRoot) => {
    function visit(parent: HtmlRoot | Element) {
      for (const child of parent.children) {
        if (child.type === 'element') visit(child);
      }
      if (parent.type === 'element' && parent.tagName === 'li') {
        const first = parent.children.find(child => child.type === 'element');
        const checkbox = first?.tagName === 'p' ? first.children[0] : first;
        const start = parent.position?.start.offset;
        if (checkbox?.type === 'element' && checkbox.tagName === 'input' && start !== undefined) {
          // GFM has already classified this item. Its first bracket is its task marker,
          // including when the marker starts on a continuation line inside a quote.
          const offset = source.indexOf('[', start) + 1;
          if (offset > start && offset < (parent.position?.end.offset ?? start) && /^[ xX]\]/.test(source.slice(offset, offset + 2))) {
            checkbox.properties.dataTaskOffset = offset;
            const labelNodes = first?.tagName === 'p' ? first.children : parent.children;
            checkbox.properties.ariaLabel = labelNodes.filter(child => child.type !== 'element' || !['ul', 'ol'].includes(child.tagName)).map(inlineText).join('').trim();
          }
        }
      }
      let opening = -1;
      for (let i = 0; i < parent.children.length; i++) {
        const child = parent.children[i];
        if (child.type !== 'raw') continue;
        if (child.value === '<u>') { opening = i; continue; }
        if (child.value === '</u>' && opening >= 0 && child.position?.start.line === parent.children[opening].position?.end.line) {
          const children = parent.children.slice(opening + 1, i) as ElementContent[];
          parent.children.splice(opening, i - opening + 1, { type: 'element', tagName: 'u', properties: {}, children });
          i = opening;
        }
        opening = -1;
      }
    }
    visit(tree);
  };
}

const components: Components = {
  table: ({ children }) => <div className="message-table-scroll"><table>{children}</table></div>,
  a: ({ href, children }) => href
    ? <a href={href} className="message-link" target="_blank" rel="noopener noreferrer">{children}</a>
    : <>{children}</>,
  input: function TaskCheckbox({ node, checked, 'aria-label': label }) {
    const { onTaskToggle, taskPending, taskLabel } = useContext(Tasks);
    const offset = node?.properties.dataTaskOffset;
    const editable = typeof offset === 'number' && Boolean(onTaskToggle);
    return <input type="checkbox" checked={Boolean(checked)} disabled={!editable}
      aria-label={label || taskLabel} aria-disabled={taskPending || undefined}
      onChange={() => { if (!taskPending && typeof offset === 'number') onTaskToggle?.(offset); }} />;
  },
};

export function MessageMarkdown({ text, ...controls }: { text: string } & TaskControls) {
  if (!basicMarkdown.test(text) && !blockMarker.test(text) && !strikeOrImage.test(text) && !underline.test(text)) return <>{text.split(urlPattern).map((part, index) => /^https?:\/\//.test(part)
    ? <a key={index} href={part} className="message-link" target="_blank" rel="noopener noreferrer">{part}</a>
    : <Fragment key={index}>{part}</Fragment>)}</>;
  return <Tasks.Provider value={controls}><div className="message-markdown"><Markdown
    remarkPlugins={[remarkGfm, [preserveImageSource, { source: text }]]}
    rehypePlugins={[[enhanceMessage, { source: text }]]}
    allowedElements={elements}
    unwrapDisallowed
    urlTransform={url => /^(https?:\/\/|mailto:|tel:)/i.test(url) ? url : ''}
    components={components}
  >{text}</Markdown></div></Tasks.Provider>;
}
