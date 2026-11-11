import { searchMatchRanges, type SearchMatchRange } from './messageSearch';
/** Bounded preview and half-open UTF-16 highlights, including phonetic matches. */
export function searchPreview(text: string, query: string, limit = 140): { text: string; ranges: SearchMatchRange[] } {
  const matches = searchMatchRanges(text, query);
  const segments = Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text));
  const hit = matches[0]?.start ?? 0;
  const hitIndex = Math.max(0, segments.findIndex(s => s.index >= hit));
  const first = segments.length > limit && hitIndex > 36 ? hitIndex - 24 : 0;
  const last = Math.min(segments.length, first + Math.max(1, limit));
  const start = segments[first]?.index ?? 0, end = segments[last]?.index ?? text.length;
  let output = first ? '…' : '';
  const map: SearchMatchRange[] = [];
  // Collapse whitespace while retaining the mapping into the displayed preview.
  for (let i = start; i < end;) {
    const match = /^\s+/.exec(text.slice(i, end));
    const length = match ? match[0].length : (text.codePointAt(i)! > 0xffff ? 2 : 1);
    const value = match ? ' ' : text.slice(i, i + length);
    const range = { start: output.length, end: output.length + value.length };
    for (let j = 0; j < length; j++) map[i + j - start] = range;
    output += value; i += length;
  }
  const ranges = matches.filter(r => r.start < end && r.end > start).map(r => ({
    start: map[Math.max(r.start, start) - start].start,
    end: map[Math.min(r.end, end) - start - 1].end,
  }));
  return { text: output + (end < text.length ? '…' : ''), ranges };
}
export function searchExcerpt(text: string, query: string, limit = 140): string {
  return searchPreview(text, query, limit).text;
}
