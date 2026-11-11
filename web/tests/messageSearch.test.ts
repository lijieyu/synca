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
test('highlight ranges map phonetics, repeated hits and Unicode to original text', async () => {
 const {searchMatchRanges}=await import('../src/utils/messageSearch');
 const {searchPreview}=await import('../src/utils/searchExcerpt');
 for(const query of ['mianshi','ms','面试']) {
  const text='😀前文。'.repeat(200)+'面试安排，面试准备';
  const preview=searchPreview(text,query);
  assert.ok(preview.text.startsWith('…'));
  assert.deepEqual(preview.ranges.map(r=>preview.text.slice(r.start,r.end)),['面试','面试']);
 }
 for(const [text,query,expected] of [['😀Cafe\u0301 ＡＢＣ','cafe','Cafe\u0301'],['😀Cafe\u0301 ＡＢＣ','abc','ＡＢＣ'],['会议纪要.pdf','hyjy','会议纪要']]) {
  assert.deepEqual(searchMatchRanges(text,query).map(r=>text.slice(r.start,r.end)),[expected]);
 }
 assert.deepEqual(searchMatchRanges('苹果牛奶','pn'),[]);
 const preview=searchPreview('😀\n\t面试   准备','mszb');
 assert.deepEqual(preview.ranges.map(r=>preview.text.slice(r.start,r.end)),['面试 准备']);
});
test('worker returns mapped previews with revision and clears removed records', async () => {
 const previousSelf=globalThis.self;
 let response: {revision:number;ids:string[];results:{id:string;preview:{text:string;ranges:{start:number;end:number}[]};filenameRanges:{start:number;end:number}[]} };
 const worker={postMessage(value: typeof response){response=value;},onmessage: null as unknown as (event:{data:unknown})=>void};
 Object.assign(globalThis,{self:worker});
 try {
  await import('../src/utils/messageSearch.worker');
  worker.onmessage({data:{records:[record('late','前文。'.repeat(200)+'面试准备'),record('file','caption',{fileName:'面试.pdf'})],query:'mianshi',revision:7}});
  assert.equal(response!.revision,7);
  assert.deepEqual(response!.ids,['late','file']);
  const late=response!.results[0].preview;
  assert.deepEqual(late.ranges.map(r=>late.text.slice(r.start,r.end)),['面试']);
  assert.deepEqual(response!.results[1].filenameRanges,[{start:0,end:2}]);
  worker.onmessage({data:{records:[],query:'mianshi',revision:8}});
  assert.deepEqual(response!.results,[]);
 } finally { Object.assign(globalThis,{self:previousSelf}); }
});
test('contextual Greek case folding matches original text and lowercase queries', async () => {
 const {searchMatchRanges}=await import('../src/utils/messageSearch');
 const index=new MessageSearchIndex();index.update([record('g','😀 ΟΣ notes')]);
 for(const query of ['ΟΣ','ος','οσ']) {
  assert.equal(index.search(query)[0]?.id,'g');
  assert.deepEqual(searchMatchRanges('😀 ΟΣ notes',query),[{start:3,end:5}]);
 }
});
