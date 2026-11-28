import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {parseMarkdown} from '../src/markdown/parse.ts';

test('native bundle runs without DOM or Node globals and matches every shared fixture',()=>{
 const context={};runInNewContext(readFileSync(new URL('../../ios/Synca/Resources/markdown-parser.js',import.meta.url),'utf8'),context,{timeout:3000});
 const fixtures=JSON.parse(readFileSync(new URL('../../tests/fixtures/markdown-parity.json',import.meta.url),'utf8'));
 for(const {id,source} of fixtures)assert.deepEqual(JSON.parse(context.SyncaMarkdown.parseJSON(source)),parseMarkdown(source),id);
 assert.equal(context.SyncaMarkdown.toggleTask('😀\r\n\r\n- [ ] task',9),'😀\r\n\r\n- [x] task');
 assert.equal(context.SyncaMarkdown.toggleTask('`- [ ] literal`',4),null);
});
