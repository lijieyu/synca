type SelectionDirection = 'forward' | 'backward' | 'none';
type Draft = { text: string; start: number; end: number; direction: SelectionDirection };
type DraftStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
const empty: Draft = { text: '', start: 0, end: 0, direction: 'none' };

export function createComposerDrafts(storage?: DraftStorage, owner?: string, sessionIsCurrent = () => true) {
  const entries = new Map<string, Draft>();
  const listeners = new Set<() => void>();
  const key = (scope: string) => 'synca.desktop.draft.' + scope;

  function get(scope: string): Draft {
    const cached = entries.get(scope);
    if (cached) return cached;
    let draft = empty;
    try {
      const saved = storage && sessionIsCurrent() && JSON.parse(storage.getItem(key(scope)) ?? 'null');
      if (saved && saved.owner === owner && typeof saved.text === 'string') {
        const text = saved.text;
        const offset = (n: unknown) => typeof n === 'number' && Number.isInteger(n)
          ? Math.max(0, Math.min(text.length, n)) : text.length;
        const start = offset(saved.start);
        draft = { text, start, end: Math.max(start, offset(saved.end)),
          direction: ['forward', 'backward'].includes(saved.direction) ? saved.direction : 'none' };
      }
    } catch { /* A blocked storage area leaves in-memory drafts available. */ }
    entries.set(scope, draft);
    return draft;
  }

  return {
    get,
    // A deleted category must not strand its draft or overwrite the fallback's draft.
    recoverScopes(valid: readonly string[], fallback: string, active: string) {
      const lost = [...entries].filter(([scope, draft]) => !valid.includes(scope) && draft.text);
      if (!lost.length || !valid.includes(fallback)) return;
      lost.sort(([a], [b]) => Number(b === active) - Number(a === active));
      const target = get(fallback);
      const prefix = lost.map(([, draft]) => draft.text).join('\n\n');
      const text = target.text ? prefix + '\n\n' + target.text : prefix;
      const activeLost = lost.find(([scope]) => scope === active)?.[1];
      const offset = target.text ? prefix.length + 2 : prefix.length;
      const selection = activeLost ?? { ...target, start: target.start + offset, end: target.end + offset };
      this.set(fallback, text, selection.start, selection.end, selection.direction);
      lost.forEach(([scope]) => this.set(scope, '', 0, 0));
    },
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
    set(scope: string, text: string, start: number, end: number, direction: SelectionDirection = 'none') {
      const previous = get(scope);
      if (previous.text === text && previous.start === start && previous.end === end && previous.direction === direction) return;
      const draft = text ? { text, start, end, direction } : empty;
      entries.set(scope, draft);
      try {
        if (storage && sessionIsCurrent()) {
          if (text) storage.setItem(key(scope), JSON.stringify({ owner, ...draft }));
          else storage.removeItem(key(scope));
        }
      } catch { /* Continue editing if the storage quota is exhausted. */ }
      listeners.forEach(listener => listener());
    },
  };
}
