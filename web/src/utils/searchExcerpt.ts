/** A bounded preview that keeps a late literal match in the visible first line. */
export function searchExcerpt(text: string, query: string, limit = 140): string {
  const fold = (value: string) => value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
  const index = query.trim() ? fold(text).indexOf(fold(query.trim())) : -1;
  const start = index > 36 ? index - 24 : 0;
  const end = Math.min(text.length, start + limit);
  return `${start ? '…' : ''}${text.slice(start, end).replace(/\s+/g, ' ')}${end < text.length ? '…' : ''}`;
}
