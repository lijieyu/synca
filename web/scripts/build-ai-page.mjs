import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
const page = readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8')
  .replace('<title>Synca</title>', '<title>连接 AI · Synca — 让 AI 整理你的记录</title>\n    <meta name="description" content="通过标准 MCP，让支持连接的 AI 应用查找、整理和保存 Synca 记录。支持 OAuth、独立令牌与随时撤销。" />\n    <meta name="referrer" content="no-referrer" />\n    <meta property="og:title" content="随手记下，让 AI 接着处理。" />\n    <meta property="og:description" content="连接 Synca，在 AI 对话中查找、整理和保存你的记录。" />')
  .replace('<div id="root"></div>', '<div id="root"></div><noscript><h1>让 AI 连接你的 Synca</h1><p>通过支持 MCP 的 AI 应用查找、整理和保存记录。请启用 JavaScript 以登录和管理连接。</p></noscript>');
mkdirSync(new URL('../dist/ai/', import.meta.url), { recursive: true });
writeFileSync(new URL('../dist/ai/index.html', import.meta.url), page);
