export interface ScratchDocument {content:string;revision:number;updatedAt?:string|null}
export interface ScratchDraft extends ScratchDocument {dirty:boolean;preserveCurrent?:boolean}
export function acceptedDraft(current:ScratchDraft,sent:string,remote:ScratchDocument):ScratchDraft {
 return {...current,revision:remote.revision,dirty:current.content!==sent,...(current.preserveCurrent?{preserveCurrent:false}:{})};
}
export function remoteDraft(current:ScratchDraft,remote:ScratchDocument):ScratchDraft {
 return current.dirty ? current : {...remote,dirty:false};
}

// Each editor owns its unsynced key. A clean poll in another tab cannot erase it.
export type LocalScratchCopy = ScratchDraft & {id:string;created_at:string};
export function localScratchCopies(storage:Storage,key:string):LocalScratchCopy[] {
 const copies:LocalScratchCopy[]=[];
 try { for(let i=0;i<storage.length;i++) {
  const id=storage.key(i);if(!id||(id!==key&&!id.startsWith(key+':draft:')))continue;
  try{const value=JSON.parse(storage.getItem(id)??'null');
   if(value?.dirty&&typeof value.content==='string'&&Number.isInteger(value.revision))copies.push({...value,id,created_at:value.created_at??new Date(0).toISOString()});
  }catch{}
 }
 } catch { /* Storage can be unavailable; the editor reports persistence failure. */ }
 return copies.sort((a,b)=>b.created_at.localeCompare(a.created_at));
}
export function persistScratchDraft(storage:Storage,key:string,writer:string,draft:ScratchDraft) {
 const own=key+':draft:'+writer;
 if(draft.dirty)storage.setItem(own,JSON.stringify({...draft,created_at:new Date().toISOString()}));
 else {storage.setItem(key,JSON.stringify(draft));storage.removeItem(own);}
}
