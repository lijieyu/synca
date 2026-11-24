import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/utils/aiClientBrand.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText;
const { matchAIClientBrand } = await import('data:text/javascript;base64,' + Buffer.from(compiled).toString('base64'));
test('recognizes registered clients, localized aliases and version suffixes', () => {
  const names = {'ChatGPT Desktop 1.2':'chatgpt', '腾讯 WorkBuddy':'workbuddy', '千问办公':'qwen', '豆包工作':'doubao', '百度搭子':'baidu', '豆包':'doubaoApp', '通义千问':'qwenApp', '月之暗面 Kimi':'kimi', 'DeepSeek':'deepseek', 'Z.AI GLM':'zhipu', 'Gemini':'gemini', 'Claude Code':'claude', 'Cursor IDE':'cursor', 'Windsurf Editor':'windsurf', 'Cline':'cline', 'Cherry-Studio':'cherry', 'Visual Studio Code Insiders':'vscode', 'OpenAI Codex':'codex'};
  for (const [name,id] of Object.entries(names)) assert.equal(matchAIClientBrand(name)?.id,id,name);
  assert.equal(matchAIClientBrand('ＣＨＡＴＧＰＴ')?.id,'chatgpt');
});
test('does not assign arbitrary unknown apps a familiar brand', () => {
  for (const name of ['', 'My personal assistant', '<img src=x onerror=alert(1)>']) assert.equal(matchAIClientBrand(name), undefined);
});
