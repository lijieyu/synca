import { pinyin } from 'pinyin-pro';
export interface SearchRecord {
  id: string; textContent: string | null; fileName: string | null;
  createdAt: string; categoryId: string | null; isDeleted: boolean;
}
type Entry = { record: SearchRecord; fields: {raw: string; full: string; initials: string}[] };
const normalize = (value: string) => value.normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase().trim();
export class MessageSearchIndex {
  private entries: Entry[] = [];
  private cache = new Map<string, Entry['fields'][number]>();
  update(records: SearchRecord[]) {
    const used = new Set<string>();
    this.entries = records.filter(record => !record.isDeleted).map(record => ({ record, fields: [record.textContent,record.fileName].filter((value): value is string => !!value).map(text => {
      used.add(text);
      const cached = this.cache.get(text); if (cached) return cached;
      const raw = normalize(text);
      const field = { raw,
        full: pinyin(raw,{toneType:'none',type:'array',nonZh:'consecutive',v:true}).join('').replace(/[\s']/g,''),
        initials: pinyin(raw,{toneType:'none',type:'array',pattern:'first',nonZh:'consecutive',v:true}).join('').replace(/[\s']/g,'') };
      this.cache.set(text,field); return field;
    }) }));
    for (const key of this.cache.keys()) if (!used.has(key)) this.cache.delete(key);
  }
  search(query: string, categoryId?: string) {
    const raw = normalize(query); if (!raw) return [];
    const roman = normalize(query.normalize('NFKC').replace(/ü/gi,'v')).replace(/[\s']/g,'');
    const phonetic = /^[a-z]{2,}$/.test(roman);
    return this.entries.flatMap(({record,fields}) => {
      if (categoryId && record.categoryId !== categoryId) return [];
      const rank = fields.some(f=>f.raw.includes(raw)) ? 0 : phonetic && fields.some(f=>f.full.includes(roman)) ? 1 : phonetic && fields.some(f=>f.initials.includes(roman)) ? 2 : -1;
      return rank < 0 ? [] : [{id:record.id,rank,createdAt:record.createdAt}];
    }).sort((a,b)=>a.rank-b.rank || Date.parse(b.createdAt)-Date.parse(a.createdAt) || (a.id>b.id ? -1 : a.id<b.id ? 1 : 0));
  }
}
