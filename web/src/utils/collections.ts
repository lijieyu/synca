type RecordArea = { id: string; categoryId?: string | null; collectedAt?: string | null; isCleared: boolean; isDeleted?: boolean };
export function recordsInArea<T extends RecordArea>(records: readonly T[], collections: boolean, categoryId?: string): T[] {
 const result=records.filter(record=>!record.isDeleted && Boolean(record.collectedAt)===collections && (!categoryId || record.categoryId===categoryId));
 return collections ? result.sort((a,b)=>(b.collectedAt ?? '').localeCompare(a.collectedAt ?? '') || a.id.localeCompare(b.id)) : result;
}
export function taskCounts(records: readonly RecordArea[]) {
 const categories: Record<string,number>={};let total=0;
 for(const record of records){if(record.isDeleted || record.collectedAt || record.isCleared)continue;total++;if(record.categoryId)categories[record.categoryId]=(categories[record.categoryId]??0)+1;}
 return {total,categories};
}
