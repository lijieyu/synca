import assert from 'node:assert/strict';
import { mergeMessageChanges, nextMessageCheckpoint, messageChangesSince } from '../src/utils/messageSync';
import { api, type SyncaMessage } from '../src/api/client';
declare const test: (name: string, fn: () => void | Promise<void>) => void;
const row=(id:string, updatedAt='2026-11-24T02:00:00.000Z',extra:Partial<SyncaMessage>={}):SyncaMessage=>({id,updatedAt,createdAt:updatedAt,textContent:id,type:'text',isCleared:false,isDeleted:false,...extra} as SyncaMessage);
test('delta preserves old records and applies completion, insertion and deletion',()=>{
 const initial=[row('a'),row('b'),row('c')];
 const result=mergeMessageChanges(initial,[row('b','2026-11-24T02:00:01.000Z',{isCleared:true}),row('c','2026-11-24T02:00:01.000Z',{isDeleted:true}),row('d')]);
 assert.deepEqual(result.map(x=>x.id),['a','b','d']);assert(result[1].isCleared);assert.equal(result[0],initial[0]);
});
test('stale response cannot replace saved edit; unchanged deltas reuse state',()=>{
 const initial=[row('a','2026-11-24T02:00:02.000Z',{textContent:'saved'})];
 assert.equal(mergeMessageChanges(initial,[row('a')]),initial);assert.equal(mergeMessageChanges(initial,[{...initial[0]}]),initial);assert.equal(mergeMessageChanges(initial,[]),initial);
});
test('checkpoint covers tombstones, empty accounts and same-millisecond writes',()=>{
 assert.equal(nextMessageCheckpoint(null,[]),'1970-01-01T00:00:00.000Z');
 const checkpoint=nextMessageCheckpoint(null,[row('a'),row('gone','2026-11-24T02:00:01.000Z',{isDeleted:true})]);
 assert.equal(checkpoint,'2026-11-24T02:00:01.000Z');assert.equal(messageChangesSince(checkpoint),'2026-11-24T02:00:00.000Z');
 assert.equal(nextMessageCheckpoint(checkpoint,[]),checkpoint);assert.equal(nextMessageCheckpoint(checkpoint,[row('a')]),checkpoint);
 assert.throws(()=>nextMessageCheckpoint(checkpoint,[row('bad','invalid')]));
});
test('delta HTTP revalidation preserves retry payload and isolates account tokens',async()=>{
 const originalFetch=globalThis.fetch;let token:string|null='account-a';let calls=0;
 Object.assign(globalThis,{localStorage:{getItem:()=>token},window:{location:{reload(){} }}});
 const result={messages:[row('server')]};
 globalThis.fetch=async(input,init)=>{
  calls++;assert.equal(String(input),'/messages?since='+encodeURIComponent('2026-11-24T02:00:00.000Z'));
  const headers=new Headers(init?.headers);assert.equal(headers.get('Authorization'),'Bearer '+token);
  if(calls===1){assert.equal(headers.get('If-None-Match'),null);return new Response(JSON.stringify(result),{headers:{ETag:'"one"'}});}
  if(calls===2){assert.equal(headers.get('If-None-Match'),'"one"');return new Response(null,{status:304});}
  assert.equal(headers.get('If-None-Match'),null);return new Response(JSON.stringify({messages:[]}));
 };
 try{
  assert.deepEqual(await api.listMessageChanges('2026-11-24T02:00:00.000Z'),result);
  assert.deepEqual(await api.listMessageChanges('2026-11-24T02:00:00.000Z'),result,'category failure retry must not lose delta');
  token='account-b';assert.deepEqual(await api.listMessageChanges('2026-11-24T02:00:00.000Z'),{messages:[]});
 }finally{globalThis.fetch=originalFetch;delete (globalThis as any).localStorage;delete (globalThis as any).window;}
});

test('in-flight deltas from an old session cannot reach the new account',async()=>{
 const originalFetch=globalThis.fetch;let token:string|null='old-account';
 Object.assign(globalThis,{localStorage:{getItem:()=>token},window:{location:{reload(){throw new Error('must not reload new account');}}}});
 let release!:(response:Response)=>void;
 globalThis.fetch=()=>new Promise(resolve=>{release=resolve;});
 try{
  const pending=api.listMessageChanges('2026-11-24T02:00:00.000Z');
  token='new-account';release(new Response(JSON.stringify({messages:[row('private-old')]}),{headers:{ETag:'"old"'}}));
  await assert.rejects(pending,{name:'AbortError'});
  globalThis.fetch=async(_input,init)=>{
   assert.equal(new Headers(init?.headers).get('If-None-Match'),null);
   return new Response(JSON.stringify({messages:[]}));
  };
  assert.deepEqual(await api.listMessageChanges('2026-11-24T02:00:00.000Z'),{messages:[]});
 }finally{globalThis.fetch=originalFetch;delete (globalThis as any).localStorage;delete (globalThis as any).window;}
});
