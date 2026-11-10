import assert from 'node:assert/strict';
import { MessageSearchIndex } from '../src/utils/messageSearch.ts';
const record = (id: string, textContent: string, extra = {}) => ({id,textContent,fileName:null,createdAt:'2026-01-01',categoryId:'a',isDeleted:false,isCleared:false,...extra});
test('literal, pinyin, initials ranking and deterministic ties', () => {
 const index = new MessageSearchIndex();
 const items=[record('c','牛奶'),record('b','nn'),record('a','牛奶', {createdAt:'2025-01-01'})];
 index.update(items); assert.deepEqual(index.search('nn').map(x=>x.id),['b','c','a']);
 assert.equal(index.search('niunai')[0].id,'c');
 assert.equal(index.search('n').some(x=>x.id==='c'),false);
 index.update([record('z','牛奶'),record('a','牛奶')]); assert.deepEqual(index.search('牛奶').map(x=>x.id),['z','a']);
});
test('filenames, completed, deleted, category scope and no skipped initials',()=>{
 const index=new MessageSearchIndex(); index.update([record('a','苹果牛奶',{isCleared:true}),record('b','',{fileName:'会议纪要.pdf',categoryId:'b'}),record('c','牛奶',{isDeleted:true})]);
 assert.deepEqual(index.search('nn').map(x=>x.id),['a']); assert.equal(index.search('pn').length,0);
 assert.equal(index.search('huiyijiyao')[0].id,'b'); assert.equal(index.search('huiyijiyao','a').length,0);
 assert.equal(index.search('  ').length,0);
});
test('updates replace text and remove deleted records',()=>{
 const index=new MessageSearchIndex(); index.update([record('a','牛奶')]); index.update([record('a','咖啡')]);
 assert.equal(index.search('nn').length,0); assert.equal(index.search('kf').length,1); index.update([]); assert.equal(index.search('kf').length,0);
});
test('traditional Chinese, mixed Latin and folded literal matching',()=>{
 const index=new MessageSearchIndex();index.update([record('a','會議筆記 Synca café ＡＢＣ'),record('b','牛',{fileName:'奶'})]);
 for(const query of ['huiyibiji','hybj','synca','CAFE','abc']) assert.equal(index.search(query)[0].id,'a');
 assert.equal(index.search('niunai').length,0);
});
test('umlaut spelling and mixed pinyin initials',()=>{
 const index=new MessageSearchIndex();index.update([record('a','旅游'),record('b','面试 Synca 准备')]);
 for(const query of ['lvyou','lüyou']) assert.equal(index.search(query)[0].id,'a');
 assert.equal(index.search('mssyncazb')[0].id,'b');
});
test('result excerpts expose late literal matches without rendering whole records', async()=>{
 const {searchExcerpt}=await import('../src/utils/searchExcerpt');
 const text='前文'.repeat(500)+'目标内容'+'后文'.repeat(500);
 const excerpt=searchExcerpt(text,'目标');assert.ok(excerpt.includes('目标内容'));assert.ok(excerpt.length<180);assert.ok(excerpt.startsWith('…'));
});
