import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createChangeNotifications } from '../src/utils/changeNotifications.ts';
const wait=(n:number)=>new Promise(r=>setTimeout(r,n));
test('coalesces hints and retries a blocked/failed sync without dropping a concurrent change',async()=>{
 let calls=0;let release:()=>void=()=>{};
 const client=createChangeNotifications({token:'test',stream:false,interval:100000,retry:10,onChange:async()=>{calls++;if(calls===1)return false;if(calls===2)await new Promise<void>(r=>release=r);return true;}});
 client.hint();client.hint();await wait(25); assert.equal(calls,2);
 client.hint();release();await wait(20); assert.equal(calls,3);
 client.stop();client.hint();await wait(20);assert.equal(calls,3);
});
test('reads split SSE frames, reconnects after EOF, and aborts on stop',async()=>{
 let connections=0,changes=0;let signal:AbortSignal|undefined;
 const fetcher:typeof fetch=async(_url,options)=>{connections++;signal=options?.signal as AbortSignal;return new Response(new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('event: cha'));c.enqueue(new TextEncoder().encode('nge\ndata: {}\n\n')); if(connections===1)c.close();}}),{headers:{'Content-Type':'text/event-stream'}})};
 const client=createChangeNotifications({token:'test',fetcher,retry:10,interval:100000,onChange:async()=>{changes++;return true;}});
 await wait(60);assert(connections>=2);assert(changes>=2);client.stop();assert(signal?.aborted);
});
