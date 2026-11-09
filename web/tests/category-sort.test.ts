import { moveItem } from '../src/hooks/usePointerSort';
it('moves across both boundaries without losing identities or changing the source', () => {
  const source = [{ id: 'work' }, { id: 'life' }, { id: 'ideas' }];
  const result = moveItem(source, 0, 2);
  expect(result.map(row => row.id)).toEqual(['life', 'ideas', 'work']);
  expect(moveItem(result, 2, 0)).toEqual(source);
  expect(source.map(row => row.id)).toEqual(['work', 'life', 'ideas']);
  expect(result[2]).toBe(source[0]);
});
it('rejects missing or out-of-range targets without removing a category', () => {
  for (const [from, to] of [[-1, 0], [0, -1], [3, 0], [0, 3]]) {
    expect(moveItem(['work', 'life', 'ideas'], from, to)).toEqual(['work', 'life', 'ideas']);
  }
  expect(moveItem([], 0, 0)).toEqual([]);
});
