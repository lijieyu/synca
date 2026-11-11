import { searchMatchRanges, type SearchMatchRange } from './messageSearch';
/** Bounded preview and half-open UTF-16 highlights, including phonetic matches. */
export function searchPreview(text: string, query: string, limit = 160, tailContext = 48): { text: string; ranges: SearchMatchRange[] } {
  const matches = searchMatchRanges(text, query);
  // Compact first so paragraph whitespace does not consume the context budget.
  let compact = '';
  const offsets = new Array<number>(text.length + 1).fill(0);
  let sourceOffset = 0;
  let previousWhitespace = false;
  for (const character of text) {
    const whitespace = /\s/u.test(character);
    const replacement = whitespace ? (previousWhitespace ? '' : ' ') : character;
    for (let unit = 0; unit < character.length; unit++) {
      offsets[sourceOffset + unit] = compact.length + Math.min(unit, replacement.length);
    }
    compact += replacement;
    sourceOffset += character.length;
    offsets[sourceOffset] = compact.length;
    previousWhitespace = whitespace;
  }
  const compactMatches = matches.map(range => ({ start: offsets[range.start], end: offsets[range.end] }))
    .filter(range => range.start < range.end);
  const segments = Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(compact));
  const budget = Math.max(1, Math.floor(limit));
  if (segments.length <= budget) return { text: compact, ranges: compactMatches };
  const hit = compactMatches[0]?.start ?? 0;
  const hitIndex = Math.max(0, segments.findIndex(segment => segment.index >= hit));
  const before = Math.min(32, budget - 1);
  const tailBudget = Math.min(budget - 1, Math.max(before, Math.floor(tailContext)));
  // Backfill at the tail, keeping the hit within the visible three-line context.
  const first = Math.max(0, hitIndex - tailBudget, Math.min(hitIndex - before, segments.length - budget));
  const last = Math.min(segments.length, first + budget);
  const start = segments[first]?.index ?? 0, end = segments[last]?.index ?? compact.length;
  const prefix = first ? '…' : '';
  const ranges = compactMatches.filter(range => range.start < end && range.end > start).map(range => ({
    start: Math.max(range.start, start) - start + prefix.length,
    end: Math.min(range.end, end) - start + prefix.length,
  }));
  return { text: prefix + compact.slice(start, end) + (end < compact.length ? '…' : ''), ranges };
}
export function searchExcerpt(text: string, query: string, limit = 160, tailContext = 48): string {
  return searchPreview(text, query, limit, tailContext).text;
}
