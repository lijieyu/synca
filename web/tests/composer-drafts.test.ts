import assert from 'node:assert/strict';
import test from 'node:test';
import { createComposerDrafts } from '../src/utils/composerDrafts.ts';

test('separate overview and category drafts restore text and selection across relaunch', () => {
  const values = new Map<string,string>();
  const storage = {getItem: (k: string) => values.get(k) ?? null, setItem: (k: string,v: string) => {values.set(k,v)}, removeItem: (k: string) => {values.delete(k)}};
  const first = createComposerDrafts(storage, 'demo', () => true);
  first.set('__all__', 'overview', 1, 4);
  first.set('inbox', 'category', 2, 5, 'backward');
  const reopened = createComposerDrafts(storage, 'demo', () => true);
  assert.deepEqual(reopened.get('inbox'), {text:'category',start:2,end:5,direction:'backward'});
  assert.equal(reopened.get('__all__').text, 'overview');
  reopened.set('inbox','',0,0);
  assert.equal(reopened.get('__all__').start, 1);
  assert.equal(createComposerDrafts(storage, 'other', () => true).get('__all__').text, '');
  createComposerDrafts(storage, 'demo', () => false).set('__all__','',0,0);
  assert.equal(createComposerDrafts(storage, 'demo', () => true).get('__all__').text, 'overview');
});

test('existing text-only desktop drafts open with the caret at the end', () => {
  const storage = {getItem: () => JSON.stringify({owner:'demo',text:'旧草稿'}),setItem(){},removeItem(){}};
  assert.equal(createComposerDrafts(storage,'demo', () => true).get('work').start, 3);
});
