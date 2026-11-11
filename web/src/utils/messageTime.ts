/** Local calendar boundaries and localized dates with a consistent 24-hour clock. */
export function formatMessageTime(value: string, locale: string, yesterdayFormat: string, now = new Date()): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  const time = date.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  if (sameDay(date, now)) return time;
  const yesterday = new Date(now); yesterday.setDate(yesterday.getDate() - 1);
  if (sameDay(date, yesterday)) return yesterdayFormat.replace('%@', time);
  return `${date.toLocaleDateString(locale, { ...(date.getFullYear() !== now.getFullYear() ? { year: 'numeric' as const } : {}), month: 'numeric', day: 'numeric' })} ${time}`;
}
