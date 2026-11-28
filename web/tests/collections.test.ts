import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recordsInArea, taskCounts } from '../src/utils/collections.ts';
const records=[
 {id:'task',categoryId:'work',isCleared:false},
 {id:'done',categoryId:'work',isCleared:true},
 {id:'saved',categoryId:'work',isCleared:false,collectedAt:'2026-11-25T00:00:00Z'},
 {id:'account',categoryId:'account',isCleared:false,collectedAt:'2026-11-26T00:00:00Z'},
];
test('collection contents never enter task lists or counts',()=>{
 assert.deepEqual(recordsInArea(records,false).map(x=>x.id),['task','done']);
 assert.deepEqual(taskCounts(records),{total:1,categories:{work:1}});
});
test('collection filtering reuses categories and keeps newest collection first',()=>{
 assert.deepEqual(recordsInArea(records,true).map(x=>x.id),['account','saved']);
 assert.deepEqual(recordsInArea(records,true,'work').map(x=>x.id),['saved']);
});
