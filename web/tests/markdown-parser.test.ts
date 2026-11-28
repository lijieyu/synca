import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseMarkdown,toggleMarkdownTask,type MarkdownNode} from '../src/markdown/parse.ts';
const flatten=(nodes:MarkdownNode[]):MarkdownNode[]=>nodes.flatMap(node=>[node,...flatten(node.children??[])]);

test('shared corpus retains expected semantic nodes and visible content',()=>{
 const fixtures=JSON.parse(readFileSync(new URL('../../tests/fixtures/markdown-parity.json',import.meta.url),'utf8'));
 for(const fixture of fixtures){
  const doc=parseMarkdown(fixture.source);const nodes=flatten(doc.children);
  for(const type of fixture.types)assert.ok(nodes.some(node=>node.type===type),fixture.id+': '+type);
  const visible=nodes.map(node=>node.value??node.alt??'').join('\n');
  for(const content of fixture.contains)assert.ok(visible.includes(content),fixture.id+': '+content);
  assert.equal(nodes.filter(node=>node.taskOffset!==undefined).length,fixture.taskCount,fixture.id);
  if(fixture.plain!==undefined)assert.equal(doc.plain,fixture.plain,fixture.id);
 }
});
test('only parsed tasks can toggle; UTF16 offsets preserve every other source character',()=>{
 const source='😀\r\n\r\n> 1. [X] outer\r\n>    - [ ] nested\r\n\r\n-\r\n  [ ] continuation\r\n\r\n`- [ ] code`\r\n\\- [ ] escaped';
 const tasks=flatten(parseMarkdown(source).children).filter(n=>n.taskOffset!==undefined);
 assert.equal(tasks.length,3);
 for(const task of tasks){const offset=task.taskOffset!;const next=toggleMarkdownTask(source,offset)!;assert.equal(next.slice(0,offset),source.slice(0,offset));assert.equal(next.slice(offset+1),source.slice(offset+1));assert.notEqual(next[offset],source[offset]);}
 assert.equal(toggleMarkdownTask(source,source.indexOf('[ ] code')+1),null);
 assert.equal(toggleMarkdownTask(source,source.indexOf('[ ] escaped')+1),null);
 assert.equal(toggleMarkdownTask(source,-1),null);
});
test('normalizes reference links and images while restricting executable schemes',()=>{
 const nodes=flatten(parseMarkdown('[ok][ref] ![asset][image] [bad](javascript:alert%281%29)\n\n[ref]: https://example.com "Title"\n[image]: synca-image:00000000-0000-0000-0000-000000000001').children);
 assert.equal(nodes.find(n=>n.type==='link')?.url,'https://example.com');
 assert.equal(nodes.filter(n=>n.type==='link').length,1);
 assert.equal(nodes.find(n=>n.type==='image')?.source,'![asset][image]');
 assert.ok(nodes.some(n=>n.value==='bad'));
});
test('paired underline is inline only and cannot turn code or arbitrary HTML into markup',()=>{
 const nodes=flatten(parseMarkdown('**<u>yes</u>** `<u>code</u>` \\<u>escaped</u> <u title="x">attr</u> <u>open\n\n```\n<u>fenced</u>\n```').children);
 assert.equal(nodes.filter(n=>n.type==='underline').length,1);
 assert.equal(nodes.find(n=>n.type==='inlineCode')?.value,'<u>code</u>');
 assert.equal(nodes.find(n=>n.type==='code')?.value,'<u>fenced</u>');
});
test('ordinary whitespace stays raw while indented code and references are parsed',()=>{
 assert.equal(parseMarkdown('first\n\n\nlast').plain,true);
 assert.equal(parseMarkdown('    indented').plain,false);
 assert.equal(parseMarkdown('[site][a]\n\n[a]: https://example.com').plain,false);
});
test('extreme nesting falls back to complete source instead of breaking the record or scratch feed',()=>{
 const source='> '.repeat(3000)+'nested';
 const document=parseMarkdown(source);
 assert.equal(document.plain,true);
 assert.equal(document.children[0].children?.[0].value,source);
 assert.equal(toggleMarkdownTask(source,5),null);
});
test('long ordinary input and incomplete tags retain their original text',()=>{
 const source='中文 plain '.repeat(25000)+'\n\n<u>unfinished';
 const document=parseMarkdown(source);
 assert.equal(document.version,1);
 assert.ok(flatten(document.children).some(node=>node.value?.includes('unfinished')));
});
