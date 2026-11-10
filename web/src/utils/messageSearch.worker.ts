import { MessageSearchIndex, type SearchRecord } from './messageSearch';
const index = new MessageSearchIndex();
self.onmessage = (event: MessageEvent<{records?: SearchRecord[]; query: string; categoryId?: string; revision: number}>) => {
  const {records,query,categoryId,revision} = event.data;
  if (records) index.update(records);
  self.postMessage({revision,query,categoryId,ids:index.search(query,categoryId).map(result=>result.id)});
};
