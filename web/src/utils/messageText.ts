/** Extended grapheme clusters, matching Swift String.count (not UTF-16 length). */
export const MESSAGE_TEXT_LIMIT = 10_000;
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
export function messageTextLength(text: string): number {
  let count = 0;
  const segments = segmenter.segment(text)[Symbol.iterator]();
  while (!segments.next().done) count++;
  return count;
}
