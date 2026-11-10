import { Fragment } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { Root, RootContent, PhrasingContent } from 'mdast';

const elements = ['p', 'br', 'ul', 'ol', 'li', 'strong', 'em', 'blockquote', 'code', 'a'];
const basicMarkdown = /(^|\n) {0,3}(?:[-+*] |\d+[.)] |> ?)|\*\*[^\n]+\*\*|__[^\n]+__|\*(?!\s)[^*\n]*\S\*|(?:^|[^\p{L}\p{N}_])_(?!\s)[^_\n]*\S_(?![\p{L}\p{N}_])|`[^`\n]+`|(?<!!)\[[^\]\n]+\]\([^\n]+\)/u;
const urlPattern = /(https?:\/\/[^\s<>"{}|\\^`[\]，。！？；：、]+[^\s<>"{}|\\^`[\],.)!?;:，。！？；：、])/g;

/** GFM supplies bare URL detection; keep unsupported syntax literal instead of losing data. */
function preserveUnsupported({ source }: { source: string }) {
  return (tree: Root) => {
    function visit(node: Root | RootContent | PhrasingContent) {
      if (!('children' in node)) return;
      node.children = node.children.map(child => {
        if (['image', 'imageReference', 'code', 'heading', 'thematicBreak', 'table', 'delete'].includes(child.type)) {
          const text = { type: 'text' as const, value: source.slice(child.position?.start.offset, child.position?.end.offset) };
          return ['image', 'imageReference', 'delete'].includes(child.type) ? text : { type: 'paragraph' as const, children: [text] };
        }
        if (child.type === 'listItem' && child.checked !== null && child.checked !== undefined) {
          const first = child.children[0];
          if (first?.type === 'paragraph') first.children.unshift({ type: 'text', value: child.checked ? '[x] ' : '[ ] ' });
          child.checked = null;
        }
        visit(child);
        return child;
      }) as typeof node.children;
    }
    visit(tree);
  };
}

/** A display-only view. Stored, edited and copied text always remains the source. */
export function MessageMarkdown({ text }: { text: string }) {
  // Plain records retain every newline and space, including existing multi-blank paragraphs.
  if (!basicMarkdown.test(text)) return <>{text.split(urlPattern).map((part, index) => /^https?:\/\//.test(part)
    ? <a key={index} href={part} className="message-link" target="_blank" rel="noopener noreferrer">{part}</a>
    : <Fragment key={index}>{part}</Fragment>)}</>;
  return <div className="message-markdown"><Markdown
    remarkPlugins={[remarkGfm, [preserveUnsupported, { source: text }]]}
    allowedElements={elements}
    unwrapDisallowed
    urlTransform={url => /^(https?:\/\/|mailto:|tel:)/i.test(url) ? url : ''}
    components={{
      a: ({ href, children }) => href
        ? <a href={href} className="message-link" target="_blank" rel="noopener noreferrer">{children}</a>
        : <>{children}</>,
    }}
  >{text}</Markdown></div>;
}
