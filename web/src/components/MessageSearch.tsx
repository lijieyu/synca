import { useEffect, useRef, useState } from 'react';
import { Search, Check } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import type { MessageCategory, SyncaMessage } from '../api/client';
import { Modal } from './Modal';
import './MessageSearch.css';
import { searchExcerpt } from '../utils/searchExcerpt';
interface Props { messages: SyncaMessage[]; categories: MessageCategory[]; currentCategoryId?: string; onCancel: () => void; onSelect: (id: string) => boolean }
export function MessageSearch({messages,categories,currentCategoryId,onCancel,onSelect}: Props) {
  const {t,i18n}=useTranslation();
  const [query,setQuery]=useState('');
  const [localScope,setLocalScope]=useState(false);
  const [result,setResult]=useState<{revision:number;ids:string[];query:string;categoryId?:string}>({revision:0,ids:[],query:''});
  const [revision,setRevision]=useState(0);
  const [error,setError]=useState(false);
  const worker=useRef<Worker | null>(null);
  const sequence=useRef(0);
  const restoreFocus=useRef(true);
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
  const results=!query.trim() || busy ? [] : result.ids.flatMap(id=>{const message=byId.get(id);return message ? [message] : [];});
  return <Modal title={t('search.title')} message="" size="standard" className="message-search-modal" hideActions onCancel={onCancel} onConfirm={()=>{}} restoreFocusRef={restoreFocus}>
    <div className="message-search-field"><Search size={18} aria-hidden="true"/><input type="search" data-initial-focus value={query} onChange={event=>setQuery(event.target.value)} aria-label={t('search.placeholder')} placeholder={t('search.placeholder')}/></div>
    <div className="message-search-scopes" aria-label={t('search.scope')} role="group">
      <button aria-pressed={!localScope} onClick={()=>setLocalScope(false)}>{t('search.all')}</button>
      {currentCategoryId && <button aria-pressed={localScope} onClick={()=>setLocalScope(true)}>{t('search.current')}{currentName ? ` · ${currentName}` : ''}</button>}
    </div>
    <p className="message-search-status" role="status">{error ? t('search.error') : !query.trim() ? t('search.hint') : busy ? t('search.loading') : results.length ? t('search.count',{count:results.length}) : t('search.empty')}</p>
    <div className="message-search-results" aria-busy={busy}>
      {results.map(message=><button className="message-search-result" key={message.id} onClick={()=>{restoreFocus.current=false;if(!onSelect(message.id)){restoreFocus.current=true;setError(true);}}}>
        <span className="message-search-preview">{searchExcerpt(message.textContent || message.fileName || '',query)}</span>
        {message.textContent && message.fileName && <span className="message-search-file">{message.fileName}</span>}
        <span className="message-search-meta"><span>{categories.find(category=>category.id===message.categoryId)?.isDefault ? t('message_category.default_badge') : categories.find(category=>category.id===message.categoryId)?.name ?? message.categoryName}</span><time dateTime={message.createdAt}>{new Date(message.createdAt).toLocaleDateString(i18n.language)}</time>{message.isCleared && <span><Check size={12} aria-hidden="true"/>{t('search.completed')}</span>}</span>
      </button>)}
    </div>
  </Modal>;
}
