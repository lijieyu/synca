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
  it('preserves ordinary whitespace and keeps image syntax literal', () => {
    expect(render('first\n\n\nlast')).toContain('first\n\n\nlast');
    expect(render('![photo](https://example.com/p.png)').replace(/<[^>]+>/g, '')).toContain('![photo](https://example.com/p.png)');
  });
});

it('renders standalone italic emphasis while preserving literal underscores in ordinary identifiers', () => {
  expect(render('*重点*')).toContain('<em>重点</em>');
  expect(render('_重点_')).toContain('<em>重点</em>');
  expect(render('some_long_identifier\n\n\nnext')).toContain('some_long_identifier\n\n\nnext');
});

it('renders each extended format on its own', () => {
  for (let level = 1; level <= 6; level++) {
    expect(render('#'.repeat(level) + ' 标题')).toContain(`<h${level}>标题</h${level}>`);
  }
  expect(render('章节\n===')).toContain('<h1>章节</h1>');
  expect(render('---')).toMatch(/<hr\s*\/?>/);
  expect(render('~~旧稿~~')).toContain('<del>旧稿</del>');
  expect(render('~~~js\n  a < b\n~~~')).toContain('<pre><code class="language-js">  a &lt; b\n</code></pre>');
  const table = render('阶段 | 状态\n:--- | ---:\n复核 | **完成**');
  expect(table).toContain('<table>'); expect(table).toContain('<strong>完成</strong>');
  expect(table.match(/<th[ >]/g)).toHaveLength(2);
  const tasks = render('- [x] 已完成\n- [ ] 待办');
  expect(tasks.match(/type="checkbox"/g)).toHaveLength(2);
  expect(tasks.match(/disabled/g)).toHaveLength(2);
  expect(tasks.match(/checked=/g)).toHaveLength(1);
});

it('renders the mobile H4 regression record with the same heading and list structure', () => {
  const html = render('#### 托管的产品功能与 Demo，和用户调研确认\n- 合作伙伴；\n- 用户访谈');
  expect(html).toContain('<h4>托管的产品功能与 Demo，和用户调研确认</h4>');
  expect(html).toContain('<li>合作伙伴；</li>');
  expect(html).not.toContain('####');
});

it('leaves remote images literal inside formatted documents and code untouched', () => {
  const html = render('# 标题\n\n![photo](https://example.com/p.png)\n\n```md\n~~literal~~\n# literal\n```');
  expect(html).toContain('![photo](https://example.com/p.png)');
  expect(html).not.toContain('<img'); expect(html).not.toContain('<del>');
  expect(html).toContain('~~literal~~\n# literal');
});

it('makes only parsed task checkboxes actionable, including quoted, loose and ordered items', () => {
  const source = ['> 1. [X] 任务', '>    - [ ] **子项**', '', '-','  [ ] continuation', '', '`- [ ] literal`', '', '\\- [ ] ordinary'].join('\r\n');
  const html = renderToStaticMarkup(createElement(MessageMarkdown, { text: source, onTaskToggle: () => {} }));
  expect(html.match(/type="checkbox"/g)).toHaveLength(3);
  expect(html).not.toContain('disabled');
  expect(render('-\t[ ] tab')).toContain('aria-label="tab"');
  expect(render('-\n  [ ] next line')).toContain('aria-label="next line"');
  for (const label of ['任务', '子项', 'continuation']) expect(html).toContain('aria-label="' + label + '"');
});

it('underlines only explicit paired inline tags, leaves code, attributes and escaped tags literal', () => {
  expect(render('<u>标注</u>')).toContain('<u>标注</u>');
  const html = render('**<u>yes</u>** and `<u>code</u>` and \\<u>escaped</u> and <u title="ignored">attributes</u> and <u>unclosed');
  expect(html.match(/<u>/g)).toHaveLength(1);
  expect(html).toContain('<strong><u>yes</u></strong>');
  expect(html).toContain('<code>&lt;u&gt;code&lt;/u&gt;</code>');
  expect(html).toContain('&lt;u title=');
  expect(render('```\n<u>verbatim</u>\n```')).not.toContain('<u>');
});
