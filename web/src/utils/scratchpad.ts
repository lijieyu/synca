export interface ScratchDocument {content:string;revision:number;updatedAt?:string|null}
export interface ScratchDraft extends ScratchDocument {dirty:boolean;preserveCurrent?:boolean}
export function acceptedDraft(current:ScratchDraft,sent:string,remote:ScratchDocument):ScratchDraft {
 return {...current,revision:remote.revision,dirty:current.content!==sent,...(current.preserveCurrent?{preserveCurrent:false}:{})};
}
export function remoteDraft(current:ScratchDraft,remote:ScratchDocument):ScratchDraft {
 return current.dirty ? current : {...remote,dirty:false};
}
