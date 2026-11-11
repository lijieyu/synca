import { MessageSearchIndex, searchMatchRanges, type SearchRecord } from './messageSearch';
import { searchPreview } from './searchExcerpt';
const index = new MessageSearchIndex();
let recordsByID = new Map<string, SearchRecord>();
self.onmessage = (event: MessageEvent<{records?: SearchRecord[]; query: string; categoryId?: string; revision: number}>) => {
  const {records,query,categoryId,revision} = event.data;
  if (records) {
    index.update(records);
    recordsByID = new Map(records.filter(record => !record.isDeleted).map(record => [record.id, record]));
  }
  const results = index.search(query, categoryId).map(({id}) => {
    const record = recordsByID.get(id)!;
    return {
      id,
      preview: searchPreview(record.textContent || record.fileName || '', query),
      filenameRanges: searchMatchRanges(record.fileName || '', query),
    };
  });
  self.postMessage({revision,query,categoryId,ids:results.map(result => result.id),results});
};
