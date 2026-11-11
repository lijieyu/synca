import { useEffect, useRef, useState } from 'react';
import { Search } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import type { MessageCategory, SyncaMessage } from '../api/client';
import { Modal } from './Modal';
import './MessageSearch.css';
import { categoryStyle } from './CategoryPalette';
import type { SearchMatchRange } from '../utils/messageSearch';
interface ResultPreview { id:string; preview:{text:string;ranges:SearchMatchRange[]}; filenameRanges:SearchMatchRange[] }
function HighlightedText({text,ranges}:{text:string;ranges:SearchMatchRange[]}) {
  let cursor=0;
  const parts=ranges.flatMap(({start,end})=>{const prefix=text.slice(cursor,start);cursor=end;return [prefix,<mark key={`${start}-${end}`}>{text.slice(start,end)}</mark>];});
  return <>{parts}{text.slice(cursor)}</>;
}
interface Props { query: string; onQueryChange: (query: string) => void; messages: SyncaMessage[]; categories: MessageCategory[]; currentCategoryId?: string; onCancel: () => void; onSelect: (id: string) => boolean }
export function MessageSearch({query,onQueryChange,messages,categories,currentCategoryId,onCancel,onSelect}: Props) {
  const {t,i18n}=useTranslation();
  const [localScope,setLocalScope]=useState(false);
  const [result,setResult]=useState<{revision:number;ids:string[];results:ResultPreview[];query:string;categoryId?:string}>({revision:0,ids:[],results:[],query:''});
  const [revision,setRevision]=useState(0);
  const [error,setError]=useState(false);
  const worker=useRef<Worker | null>(null);
  const sequence=useRef(0);
  const restoreFocus=useRef(true);
  const selectOnOpen=useRef(true);
  useEffect(()=>{
    const instance=new Worker(new URL('../utils/messageSearch.worker.ts',import.meta.url),{type:'module'});
    worker.current=instance;
    instance.onmessage=event=>{ if(event.data.revision===sequence.current) setResult(event.data); };
    instance.onerror=()=>setError(true);
    return ()=>{instance.terminate();worker.current=null;};
  },[]);
  const previousMessages=useRef<SyncaMessage[] | null>(null);
  useEffect(()=>{
    const next=++sequence.current; setRevision(next);
    const records=previousMessages.current===messages ? undefined : messages.map(({id,textContent,fileName,createdAt,categoryId,isDeleted})=>({id,textContent,fileName,createdAt,categoryId,isDeleted}));
    const timer=window.setTimeout(()=>{ worker.current?.postMessage({records,query,categoryId:localScope ? currentCategoryId : undefined,revision:next}); previousMessages.current=messages; },80);
    return ()=>window.clearTimeout(timer);
  },[messages,query,localScope,currentCategoryId]);
  const currentCategory=categories.find(category=>category.id===currentCategoryId);
  const currentName=currentCategory?.isDefault ? t('message_category.default_badge') : currentCategory?.name;
  const busy=!!query.trim() && (revision!==result.revision || query!==result.query || (localScope ? currentCategoryId : undefined)!==result.categoryId);
  const byId=new Map(messages.filter(message=>!message.isDeleted).map(message=>[message.id,message]));
  const results=!query.trim() || busy ? [] : result.results.flatMap(match=>{const message=byId.get(match.id);return message ? [{message,match}] : [];});
  return <Modal title={t('search.title')} message="" size="standard" className="message-search-modal" hideActions onCancel={onCancel} onConfirm={()=>{}} restoreFocusRef={restoreFocus}>
    <div className="message-search-field"><Search size={18} aria-hidden="true"/><input type="search" data-initial-focus onFocus={event=>{if(selectOnOpen.current){event.currentTarget.select();selectOnOpen.current=false;}}} value={query} onChange={event=>onQueryChange(event.target.value)} aria-label={t('search.placeholder')} placeholder={t('search.placeholder')}/></div>
    <div className="message-search-scopes" aria-label={t('search.scope')} role="group">
      <button aria-pressed={!localScope} onClick={()=>setLocalScope(false)}>{t('search.all')}</button>
      {currentCategoryId && <button aria-pressed={localScope} onClick={()=>setLocalScope(true)}>{t('search.current')}{currentName ? ` · ${currentName}` : ''}</button>}
    </div>
    {query.trim() && <p className="message-search-status" role="status">{error ? t('search.error') : busy ? t('search.loading') : results.length ? t('search.count',{count:results.length}) : t('search.empty')}</p>}
    {!query.trim() && <div className="message-search-empty"><Search size={32} aria-hidden="true"/><p>{t('search.prompt')}</p></div>}
    {query.trim() && <div className="message-search-results" aria-busy={busy}>
      {results.map(({message,match})=>{const category=categories.find(item=>item.id===message.categoryId);return <button className="message-search-result" key={message.id} onClick={()=>{restoreFocus.current=false;if(!onSelect(message.id)){restoreFocus.current=true;setError(true);}}}>
        <span className="message-search-preview"><HighlightedText text={match.preview.text} ranges={match.preview.ranges}/></span>
        {message.textContent && message.fileName && <span className="message-search-file"><HighlightedText text={message.fileName} ranges={match.filenameRanges}/></span>}
        <span className="message-search-meta"><span><i className="category-color-dot" style={categoryStyle(category?.colorHex ?? message.categoryColorHex,category?.color ?? message.categoryColor ?? 'slate')} aria-hidden="true"/>{category?.isDefault || message.categoryIsDefault ? t('message_category.default_badge') : category?.name ?? message.categoryName}</span><time dateTime={message.createdAt}>{new Date(message.createdAt).toLocaleDateString(i18n.language)}</time>{message.isCleared && <span><svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="m8 12 3 3 5-6" fill="none" stroke="var(--card-bg-color)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>{t('search.completed')}</span>}</span>
      </button>;})}
    </div>}
  </Modal>;
}
