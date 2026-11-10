import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { MessageMarkdown } from '../src/components/MessageMarkdown';

const render = (text: string) => renderToStaticMarkup(createElement(MessageMarkdown, { text }));

describe('message Markdown presentation', () => {
  it('renders nested lists, ordered starts, emphasis, quotes and code as semantic content', () => {
    const html = render('- **第一项**\n  - 子项 `code`\n- 第二项\n\n3. three\n4. four\n\n> quote');
    expect(html.match(/<ul>/g)?.length).toBe(2);
    expect(html).toContain('<li>子项 <code>code</code></li>');
    expect(html).toContain('<strong>第一项</strong>');
    expect(html).toContain('<ol start="3">');
    expect(html).toMatch(/<blockquote>\s*<p>quote<\/p>/);
  });
  it('keeps links and bare URLs clickable without executing HTML or dangerous URLs', () => {
    const html = render('[site](https://example.com) https://example.org\n\n<img src=x onerror=alert(1)>\n\n[bad](javascript:alert%281%29)');
    expect(html.match(/href="[^"]+"/g)).toEqual(['href="https://example.com"', 'href="https://example.org"']);
    expect(html).not.toMatch(/<(img|script)/);
    expect(html).toContain('&lt;img');
    expect(html).toContain('bad');
  });
  it('does not load remote Markdown images', () => {
    const html = render('![private image](https://tracker.example/pixel)');
    expect(html).not.toContain('<img');
    expect(html).toContain('private image');
  });
});

describe('source fidelity', () => {
  it('preserves ordinary whitespace and leaves unsupported Markdown literal', () => {
    expect(render('first\n\n\nlast')).toContain('first\n\n\nlast');
    expect(render('![photo](https://example.com/p.png)').replace(/<[^>]+>/g, '')).toContain('![photo](https://example.com/p.png)');
    expect(render('```swift\nlet value = 1\n```')).toContain('```swift\nlet value = 1\n```');
  });
});

it('renders standalone italic emphasis while preserving literal underscores in ordinary identifiers', () => {
  expect(render('*重点*')).toContain('<em>重点</em>');
  expect(render('_重点_')).toContain('<em>重点</em>');
  expect(render('some_long_identifier\n\n\nnext')).toContain('some_long_identifier\n\n\nnext');
});

it('preserves unsupported syntax mixed with supported Markdown', () => {
  const text = '**bold**\n\n![photo](https://example.com/p.png)\n\n```swift\nlet value = 1\n```\n\n# heading\n\n~~deleted~~';
  const html = render(text);
  expect(html).toContain('<strong>bold</strong>');
  const visible = html.replace(/<[^>]+>/g, '');
  for (const literal of ['![photo](https://example.com/p.png)', '```swift\nlet value = 1\n```', '# heading', '~~deleted~~']) expect(visible).toContain(literal);
});
