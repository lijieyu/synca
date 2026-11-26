import {test} from 'node:test';
import assert from 'node:assert/strict';
import {acceptedDraft,remoteDraft,localScratchCopies,persistScratchDraft} from '../src/utils/scratchpad.ts';
test('an in-flight save never drops newer typing',()=>{
 const current={content:'new typing',revision:2,dirty:true};
 assert.deepEqual(acceptedDraft(current,'sent',{content:'sent',revision:3}),{content:'new typing',revision:3,dirty:true});
 assert.deepEqual(acceptedDraft(current,'new typing',{content:'new typing',revision:3}),{content:'new typing',revision:3,dirty:false});
});
test('polling keeps offline edits and accepts remote content only when clean',()=>{
 assert.deepEqual(remoteDraft({content:'offline',revision:1,dirty:true},{content:'remote',revision:2}),{content:'offline',revision:1,dirty:true});
 assert.deepEqual(remoteDraft({content:'old',revision:1,dirty:false},{content:'remote',revision:2}),{content:'remote',revision:2,dirty:false});
});

test('a clean poll in another tab cannot erase an offline draft or another writer',()=>{
 const map=new Map<string,string>();const storage={get length(){return map.size;},key:(i:number)=>[...map.keys()][i]??null,getItem:(key:string)=>map.get(key)??null,setItem:(key:string,value:string)=>{map.set(key,value);},removeItem:(key:string)=>{map.delete(key);}} as Storage;
 persistScratchDraft(storage,'account','tab-a',{content:'offline A',revision:1,dirty:true});
 persistScratchDraft(storage,'account','tab-b',{content:'cloud',revision:2,dirty:false});
 assert.equal(localScratchCopies(storage,'account')[0].content,'offline A');
 persistScratchDraft(storage,'account','tab-b',{content:'offline B',revision:2,dirty:true});
 persistScratchDraft(storage,'account','tab-a',{content:'offline A',revision:3,dirty:false});
 assert.deepEqual(localScratchCopies(storage,'account').map(copy=>copy.content),['offline B']);
 assert.deepEqual(localScratchCopies(storage,'different-account'),[]);
});
