import { useEffect, useRef, useState } from 'react';
import { Search, X } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import type { MessageCategory, SyncaMessage } from '../api/client';
import { Modal } from './Modal';
import './MessageSearch.css';
import { formatMessageTime } from '../utils/messageTime';
import { categoryStyle } from './CategoryPalette';
import type { SearchMatchRange } from '../utils/messageSearch';
interface ResultPreview { id:string; preview:{text:string;ranges:SearchMatchRange[]}; filenameRanges:SearchMatchRange[] }
function HighlightedText({text,ranges}:{text:string;ranges:SearchMatchRange[]}) {
  const parts=ranges.flatMap(({start,end},index)=>[text.slice(index ? ranges[index-1].end : 0,start),<mark key={`${start}-${end}`}>{text.slice(start,end)}</mark>]);
  return <>{parts}{text.slice(ranges.at(-1)?.end ?? 0)}</>;
}
interface Props { query: string; onQueryChange: (query: string) => void; messages: SyncaMessage[]; categories: MessageCategory[]; currentCategoryId?: string; onCancel: () => void; onSelect: (id: string, matchedText?: string) => boolean }
export function MessageSearch({query,onQueryChange,messages,categories,currentCategoryId,onCancel,onSelect}: Props) {
  const {t,i18n}=useTranslation();
  const [localScope,setLocalScope]=useState(false);
  const [compositionDraft,setCompositionDraft]=useState<string | null>(null);
  const draft=compositionDraft ?? query;
  const composing=useRef(false);
  const [result,setResult]=useState<{revision:number;ids:string[];results:ResultPreview[];query:string;categoryId?:string}>({revision:0,ids:[],results:[],query:''});
  const [revision,setRevision]=useState(0);
  const [error,setError]=useState(false);
  const worker=useRef<Worker | null>(null);
  const sequence=useRef(0);
  const restoreFocus=useRef(true);
  const selectOnOpen=useRef(true);
  const input=useRef<HTMLInputElement>(null);
  useEffect(()=>{
    const instance=new Worker(new URL('../utils/messageSearch.worker.ts',import.meta.url),{type:'module'});
    worker.current=instance;
    instance.onmessage=event=>{ if(event.data.revision===sequence.current) {setResult(event.data);setError(false);} };
    instance.onerror=()=>setError(true);
    return ()=>{instance.terminate();worker.current=null;};
  },[]);
  const previousMessages=useRef<SyncaMessage[] | null>(null);
  useEffect(()=>{
    const next=++sequence.current; setRevision(next);
    const records=previousMessages.current===messages ? undefined : messages.map(({id,textContent,fileName,createdAt,categoryId,isDeleted})=>({id,textContent,fileName,createdAt,categoryId,isDeleted}));
    const timer=window.setTimeout(()=>{ worker.current?.postMessage({records,query,categoryId:localScope ? currentCategoryId : undefined,excerptTailContext:window.matchMedia('(min-width: 600px)').matches ? 96 : 48,revision:next}); previousMessages.current=messages; },80);
    return ()=>window.clearTimeout(timer);
  },[messages,query,localScope,currentCategoryId]);
  const currentCategory=categories.find(category=>category.id===currentCategoryId);
  const currentName=currentCategory?.isDefault ? t('message_category.default_badge') : currentCategory?.name;
  const hasCompletedQuery=!!result.query.trim();
  const refreshing=revision!==result.revision;
  const byId=new Map(messages.filter(message=>!message.isDeleted).map(message=>[message.id,message]));
  const results=!query.trim() ? [] : result.results.flatMap(match=>{const message=byId.get(match.id);return message ? [{message,match}] : [];});
  return <Modal title={t('search.title')} message="" size="standard" className="message-search-modal" hideActions onCancel={onCancel} onConfirm={()=>{}} restoreFocusRef={restoreFocus}>
    <div className="message-search-field"><Search size={18} aria-hidden="true"/><input ref={input} type="search" data-initial-focus onFocus={event=>{if(selectOnOpen.current){event.currentTarget.select();selectOnOpen.current=false;}}} value={draft} onCompositionStart={event=>{composing.current=true;setCompositionDraft(event.currentTarget.value);}} onCompositionEnd={event=>{if(!composing.current)return;composing.current=false;setCompositionDraft(null);onQueryChange(event.currentTarget.value);}} onChange={event=>{if(composing.current)setCompositionDraft(event.target.value);else onQueryChange(event.target.value);}} aria-label={t('search.placeholder')} placeholder={t('search.placeholder')}/>{draft && <button type="button" className="message-search-clear" aria-label={t('search.clear')} onClick={()=>{composing.current=false;setCompositionDraft(null);++sequence.current;onQueryChange('');input.current?.focus();}}><X size={16} aria-hidden="true"/></button>}</div>
    <div className="message-search-scopes" aria-label={t('search.scope')} role="group">
      <button aria-pressed={!localScope} onClick={()=>setLocalScope(false)}>{t('search.all')}</button>
      {currentCategoryId && <button aria-pressed={localScope} onClick={()=>setLocalScope(true)}>{t('search.current')}{currentName ? ` · ${currentName}` : ''}</button>}
    </div>
    {query.trim() && (error || (hasCompletedQuery && results.length>0)) && <p className="message-search-status" role="status">{error ? t('search.error') : t('search.count',{count:results.length})}</p>}
    {!query.trim() && <div className="message-search-empty"><Search size={32} aria-hidden="true"/><p>{t('search.prompt')}</p></div>}
    {query.trim() && hasCompletedQuery && !error && !results.length && <div className="message-search-empty" role="status"><p>{t('search.empty')}</p></div>}
    {query.trim() && <div className={`message-search-results${!results.length ? ' is-empty' : ''}`} aria-busy={refreshing}>
      {results.map(({message,match})=>{const category=categories.find(item=>item.id===message.categoryId);return <button className="message-search-result" key={message.id} onClick={()=>{restoreFocus.current=false;if(!onSelect(message.id, match.preview.ranges[0] ? match.preview.text.slice(match.preview.ranges[0].start,match.preview.ranges[0].end) : undefined)){restoreFocus.current=true;setError(true);}}}>
        <span className="message-search-preview"><HighlightedText text={match.preview.text} ranges={match.preview.ranges}/></span>
        {message.textContent && message.fileName && <span className="message-search-file"><HighlightedText text={message.fileName} ranges={match.filenameRanges}/></span>}
        <span className="message-search-meta"><span className="message-search-meta-left"><span className="message-search-category"><i className="category-color-dot" style={categoryStyle(category?.colorHex ?? message.categoryColorHex,category?.color ?? message.categoryColor ?? 'slate')} aria-hidden="true"/><span>{category?.isDefault || message.categoryIsDefault ? t('message_category.default_badge') : category?.name ?? message.categoryName}</span></span>{message.isCleared && <span className="message-search-completed"><svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="m8 12 3 3 5-6" fill="none" stroke="var(--card-bg-color)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>{t('search.completed')}</span>}</span><time dateTime={message.createdAt}>{formatMessageTime(message.createdAt,i18n.language,t('message.date.yesterday'))}</time></span>
      </button>;})}
    </div>}
  </Modal>;
}
