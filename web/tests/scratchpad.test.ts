import {test} from 'node:test';
import assert from 'node:assert/strict';
import {acceptedDraft,remoteDraft} from '../src/utils/scratchpad.ts';
test('an in-flight save never drops newer typing',()=>{
 const current={content:'new typing',revision:2,dirty:true};
 assert.deepEqual(acceptedDraft(current,'sent',{content:'sent',revision:3}),{content:'new typing',revision:3,dirty:true});
 assert.deepEqual(acceptedDraft(current,'new typing',{content:'new typing',revision:3}),{content:'new typing',revision:3,dirty:false});
});
test('polling keeps offline edits and accepts remote content only when clean',()=>{
 assert.deepEqual(remoteDraft({content:'offline',revision:1,dirty:true},{content:'remote',revision:2}),{content:'offline',revision:1,dirty:true});
 assert.deepEqual(remoteDraft({content:'old',revision:1,dirty:false},{content:'remote',revision:2}),{content:'remote',revision:2,dirty:false});
});
