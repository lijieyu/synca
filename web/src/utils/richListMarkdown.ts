const ignoredTags = new Set(['SCRIPT', 'STYLE', 'TEMPLATE', 'NOSCRIPT', 'IFRAME', 'OBJECT', 'SVG', 'IMG']);
const blockTags = new Set(['P', 'DIV', 'SECTION', 'ARTICLE', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6']);

/** Convert only semantic HTML lists. Template contents remain inert and are never attached. */
export function richListMarkdown(html: string): string | null {
  if (!html || html.length > 1_000_000) return null;
  const template = document.createElement('template');
  template.innerHTML = html;
  // Preserve the original plain text when list HTML also contains code blocks.
  if (template.content.querySelector('pre')) return null;
  if (!template.content.querySelector('ul > li, ol > li')) return null;

  const children = (node: Node): string => Array.from(node.childNodes).map(serialize).join('');
  const clean = (text: string) => text.replace(/[ \t]+\n/g, '\n').replace(/\n+/g, '\n').trim();
  function serialize(node: Node): string {
    if (node.nodeType === Node.TEXT_NODE) return (node.textContent ?? '').replace(/\s+/g, ' ');
    if (!(node instanceof Element)) return children(node);
    if (ignoredTags.has(node.tagName)) return '';
    if (node.tagName === 'BR') return '\n';
    if (node.tagName === 'UL' || node.tagName === 'OL') {
      const ordered = node.tagName === 'OL';
      let number = Number.parseInt(node.getAttribute('start') ?? '1', 10);
      if (!Number.isFinite(number) || number < 0 || number > 999_999_999) number = 1;
      const lines = Array.from(node.children).filter(child => child.tagName === 'LI').map(item => {
        const explicit = Number.parseInt(item.getAttribute('value') ?? '', 10);
        if (Number.isFinite(explicit) && explicit >= 0 && explicit <= 999_999_999) number = explicit;
        const marker = ordered ? `${number++}. ` : '- ';
        const content = clean(children(item));
        return marker + content.split('\n').join('\n' + ' '.repeat(marker.length));
      });
      return '\n' + lines.join('\n') + '\n';
    }
    const content = children(node);
    return blockTags.has(node.tagName) ? '\n' + content + '\n' : content;
  }
  return clean(children(template.content)) || null;
}

/** Replace the selection while keeping React in charge of the plain-text value. */
export function pasteRichList(event: React.ClipboardEvent<HTMLTextAreaElement>, update: (text: string) => void, afterPaste?: () => void): boolean {
  if (event.clipboardData.files.length) return false;
  const markdown = richListMarkdown(event.clipboardData.getData('text/html'));
  if (markdown === null) return false;
  event.preventDefault();
  const input = event.currentTarget;
  const start = input.selectionStart;
  const end = input.selectionEnd;
  update(input.value.slice(0, start) + markdown + input.value.slice(end));
  requestAnimationFrame(() => {
    if (!input.isConnected) return;
    input.setSelectionRange(start + markdown.length, start + markdown.length);
    afterPaste?.();
  });
  return true;
}
