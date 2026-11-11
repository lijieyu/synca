import { pinyin } from 'pinyin-pro';
export interface SearchRecord {
  id: string; textContent: string | null; fileName: string | null;
  createdAt: string; categoryId: string | null; isDeleted: boolean;
}
/** Half-open UTF-16 offsets in the original (unfolded) text. */
export type SearchMatchRange = { start: number; end: number };
type Token = { value: string; map: SearchMatchRange[] };
type Field = { raw: Token; full: Token; initials: Token };
type Entry = { record: SearchRecord; fields: Field[] };
const normalize = (value: string) => value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/ς/g, 'σ');
const compact = (value: string) => value.replace(/[\s']/g, '');
const fields = new Map<string, Field>();
// Mapping arrays are much larger than search tokens; retain only recent previews.
const mappedFields = new Map<string, Field>();
const maxMappedFields = 32;
const maxMappedCharacters = 200_000;
const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
function fieldFor(text: string, mapped = false): Field {
  const cache = mapped ? mappedFields : fields;
  const cached = cache.get(text);
  if (cached) {
    if (mapped) { cache.delete(text); cache.set(text, cached); }
    return cached;
  }
  const raw: Token = { value: '', map: [] };
  if (!mapped) raw.value = normalize(text);
  else for (const { segment, index } of segmenter.segment(text)) {
    const folded = normalize(segment);
    raw.value += folded;
    for (let i = 0; i < folded.length; i++) raw.map.push({ start: index, end: index + segment.length });
  }
  const full: Token = { value: '', map: [] }, initials: Token = { value: '', map: [] };
  let offset = 0;
  for (const part of pinyin(raw.value, { toneType: 'none', type: 'all', nonZh: 'consecutive', v: true })) {
    if (part.isZh) {
      const range = mapped ? { start: raw.map[offset].start, end: raw.map[offset + part.origin.length - 1].end } : undefined;
      for (const [token, value] of [[full, compact(part.result)], [initials, compact(part.first)]] as const) {
        token.value += value;
        if (range) for (let i = 0; i < value.length; i++) token.map.push(range);
      }
    } else if (!mapped) {
      const value = compact(part.origin); full.value += value; initials.value += value;
    } else {
      for (let i = 0; i < part.origin.length; i++) {
        const value = part.origin[i]; if (!compact(value)) continue;
        for (const token of [full, initials]) { token.value += value; if (mapped) token.map.push(raw.map[offset + i]); }
      }
    }
    offset += part.origin.length;
  }
  const field = { raw, full, initials }; cache.set(text, field);
  if (mapped) {
    let characters = [...cache.keys()].reduce((count, key) => count + key.length, 0);
    while (cache.size > maxMappedFields || characters > maxMappedCharacters) {
      const oldest = cache.keys().next().value!;
      characters -= oldest.length; cache.delete(oldest);
    }
  }
  return field;
}
function queryTokens(query: string) {
  const raw = normalize(query).trim();
  const roman = compact(normalize(query.normalize('NFKC').replace(/ü/gi, 'v')).trim());
  return { raw, roman, phonetic: /^[a-z]{2,}$/.test(roman) };
}
export function searchMatchRanges(text: string, query: string): SearchMatchRange[] {
  const q = queryTokens(query); if (!q.raw) return [];
  const field = fieldFor(text, true);
  const ranges: SearchMatchRange[] = [];
  for (const [token, needle] of [[field.raw, q.raw], ...(q.phonetic ? [[field.full, q.roman], [field.initials, q.roman]] : [])] as [Token, string][]) {
    let index = token.value.indexOf(needle);
    while (index >= 0) {
      ranges.push({ start: token.map[index].start, end: token.map[index + needle.length - 1].end });
      index = token.value.indexOf(needle, index + 1);
    }
  }
  ranges.sort((a, b) => a.start - b.start || a.end - b.end);
  const merged: SearchMatchRange[] = [];
  for (const range of ranges) {
    const last = merged.at(-1);
    if (last && range.start <= last.end) last.end = Math.max(last.end, range.end);
    else merged.push({ ...range });
  }
  return merged;
}
export class MessageSearchIndex {
  private entries: Entry[] = [];
  update(records: SearchRecord[]) {
    const used = new Set<string>();
    this.entries = records.filter(record => !record.isDeleted).map(record => ({ record, fields: [record.textContent, record.fileName].filter((value): value is string => !!value).map(text => {
      used.add(text); return fieldFor(text);
    }) }));
    for (const cache of [fields, mappedFields]) for (const key of cache.keys()) if (!used.has(key)) cache.delete(key);
  }
  search(query: string, categoryId?: string) {
    const { raw, roman, phonetic } = queryTokens(query); if (!raw) return [];
    return this.entries.flatMap(({ record, fields }) => {
      if (categoryId && record.categoryId !== categoryId) return [];
      const rank = fields.some(f => f.raw.value.includes(raw)) ? 0 : phonetic && fields.some(f => f.full.value.includes(roman)) ? 1 : phonetic && fields.some(f => f.initials.value.includes(roman)) ? 2 : -1;
      return rank < 0 ? [] : [{ id: record.id, rank, createdAt: record.createdAt }];
    }).sort((a, b) => a.rank - b.rank || Date.parse(b.createdAt) - Date.parse(a.createdAt) || (a.id > b.id ? -1 : a.id < b.id ? 1 : 0));
  }
}
