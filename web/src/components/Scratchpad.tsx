import {useEffect,useRef,useState} from 'react';
import {useTranslation} from 'react-i18next';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import {ImagePlus,FileText,Eye,History} from 'lucide-react';
import {api,ScratchConflict,type ScratchCopy,type SyncaMessage} from '../api/client';
import {acceptedDraft,remoteDraft,type ScratchDraft,type ScratchDocument} from '../utils/scratchpad';
import './Scratchpad.css';

function ProtectedImage({asset}:{asset?:SyncaMessage}) {
 const [url,setURL]=useState<string>();
 useEffect(()=>{let live=true;let objectURL:string|undefined;
  if(asset?.imageUrl) void api.getProtectedFileBlob(asset.imageUrl).then(blob=>{objectURL=URL.createObjectURL(blob);if(live)setURL(objectURL);else URL.revokeObjectURL(objectURL);}).catch(()=>{});
  return()=>{live=false;if(objectURL)URL.revokeObjectURL(objectURL);};
 },[asset?.imageUrl]);
 return url?<img src={url} alt=""/>:<span role="img" aria-label="Image">▧</span>;
}
export function Scratchpad({account}:{account:string}) {
 const {t}=useTranslation();const key=`synca:scratchpad:v1:${account}`;
 const [draft,setDraft]=useState<ScratchDraft>(()=>{try{const value=JSON.parse(localStorage.getItem(key)??'null');if(value&&typeof value.content==='string'&&Number.isInteger(value.revision))return value;}catch{}return{content:'',revision:0,dirty:false};});
 const localSaveFailed=useRef(false);const current=useRef(draft);const busy=useRef(false);const alive=useRef(true);const blocked=useRef(false);
 const [status,setStatus]=useState('scratch.local');const [error,setError]=useState('');const [remote,setRemote]=useState<ScratchDocument>();
 const [preview,setPreview]=useState(false);const [copies,setCopies]=useState<ScratchCopy[]>([]);const [showCopies,setShowCopies]=useState(false);
 const [images,setImages]=useState<SyncaMessage[]>(()=>{try{return JSON.parse(localStorage.getItem(key+":images")??"[]");}catch{return [];}});const [uploading,setUploading]=useState(false);const [showImages,setShowImages]=useState(false);
 const input=useRef<HTMLInputElement>(null);const editor=useRef<HTMLTextAreaElement>(null);
 function persist(next:ScratchDraft){current.current=next;setDraft(next);try{localStorage.setItem(key,JSON.stringify(next));localSaveFailed.current=false;}catch{localSaveFailed.current=true;setError(t('scratch.local_error'));}}
 async function refreshExtras(){const [c,i]=await Promise.all([api.getScratchCopies(),api.getScratchImages()]);if(alive.current){setCopies(c.conflicts);setImages(i.images);try{localStorage.setItem(key+":images",JSON.stringify(i.images));}catch{}}}
 async function sync(){
  if(busy.current||blocked.current||!alive.current)return;busy.current=true;
  const snapshot={...current.current};
  try{
   if(snapshot.dirty){setStatus('scratch.saving');const result=await api.saveScratchpad(snapshot.content,snapshot.revision,crypto.randomUUID(),snapshot.preserveCurrent);if(!alive.current)return;persist(acceptedDraft(current.current,snapshot.content,result));}
   else {const result=await api.getScratchpad();if(!alive.current)return;const changed=result.revision!==current.current.revision;persist(remoteDraft(current.current,result));if(changed)void refreshExtras().catch(()=>{});}
   setStatus(current.current.dirty?(localSaveFailed.current?'scratch.local_error':'scratch.local'):'scratch.saved');if(!localSaveFailed.current)setError('');
  }catch(e){if(!alive.current)return;
   if(e instanceof ScratchConflict){blocked.current=true;setRemote(e.current);setStatus('scratch.conflict');void refreshExtras().catch(()=>{});}
   else {setStatus(localSaveFailed.current?'scratch.local_error':'scratch.local');setError(t(localSaveFailed.current?'scratch.local_error':'scratch.offline'));}
  }finally{busy.current=false;}
 }
 const syncRef=useRef(sync);syncRef.current=sync;
 useEffect(()=>{alive.current=true;void syncRef.current();void refreshExtras().catch(()=>{});
  const timer=setInterval(()=>{if(!document.hidden)void syncRef.current();},5000);
  const wake=()=>{if(!document.hidden)void syncRef.current();};
  const storage=(event:StorageEvent)=>{if(event.key===key&&!current.current.dirty){void syncRef.current();}};
  window.addEventListener('online',wake);document.addEventListener('visibilitychange',wake);window.addEventListener('storage',storage);
  return()=>{alive.current=false;clearInterval(timer);window.removeEventListener('online',wake);document.removeEventListener('visibilitychange',wake);window.removeEventListener('storage',storage);};
 },[key]);
 useEffect(()=>{if(!draft.dirty)return;const timer=setTimeout(()=>void syncRef.current(),700);return()=>clearTimeout(timer);},[draft]);
 function edit(content:string){persist({...current.current,content,dirty:true});setStatus(localSaveFailed.current?'scratch.local_error':'scratch.local');}
 async function upload(file?:File){if(!file||uploading)return;setUploading(true);setError('');try{const asset=await api.uploadScratchImage(file);if(!alive.current)return;setImages(list=>{const next=[...list,asset];try{localStorage.setItem(key+":images",JSON.stringify(next));}catch{}return next;});const text=`\n![${file.name.replace(/[\[\]\\\r\n]/g,'')}](synca-image:${asset.id})\n`;const at=editor.current?.selectionStart??current.current.content.length;edit(current.current.content.slice(0,at)+text+current.current.content.slice(at));}catch{if(alive.current)setError(t('scratch.upload_error'));}finally{if(alive.current)setUploading(false);}}
 async function useCloud(){
  if(!remote||busy.current)return;
  const local=current.current.content;busy.current=true;
  try {
   let cloud=remote;
   try {cloud=await api.saveScratchpad(local,remote.revision+1,crypto.randomUUID());}
   catch(e){if(e instanceof ScratchConflict)cloud=e.current;else throw e;}
   if(!alive.current)return;
   if(current.current.content!==local){setError(t('scratch.finish_current'));return;}
   persist({...cloud,dirty:false});setRemote(undefined);blocked.current=false;setStatus('scratch.saved');void refreshExtras().catch(()=>{});
  }catch{setError(t('scratch.offline'));}finally{busy.current=false;}
 }
 async function restore(copy:ScratchCopy){
  // Preserve any unsynced local content before switching to another copy.
  if(current.current.dirty){setError(t('scratch.finish_current'));return;}
  persist({...current.current,content:copy.content,dirty:true,preserveCurrent:true});setShowCopies(false);
 }
 return <section className="scratchpad" aria-label={t('scratch.title')}>
  <div className="scratch-tools">
   <div className="scratch-modes"><button aria-pressed={!preview} onClick={()=>setPreview(false)}><FileText size={16}/>{t('scratch.edit')}</button><button aria-pressed={preview} onClick={()=>setPreview(true)}><Eye size={16}/>{t('scratch.preview')}</button></div>
   <button onClick={()=>input.current?.click()} disabled={uploading}><ImagePlus size={16}/>{t(uploading?'scratch.uploading':'scratch.image')}</button>
   <button onClick={()=>{setShowCopies(!showCopies);void refreshExtras().catch(()=>setError(t('scratch.offline')));}}><History size={16}/>{t('scratch.copies')}{copies.length?` (${copies.length})`:''}</button>
   <button onClick={()=>{setShowImages(!showImages);void refreshExtras().catch(()=>{});}}>{t('scratch.images')}</button>
   <span className="scratch-status" role="status">{t(status)}</span>
   <input ref={input} type="file" accept="image/*" hidden onChange={e=>{void upload(e.target.files?.[0]);e.target.value='';}}/>
  </div>
  {remote&&<div className="scratch-notice" role="alert"><p>{t('scratch.conflict_detail')}</p><button onClick={()=>void useCloud()}>{t('scratch.use_cloud')}</button><button onClick={()=>{persist({...current.current,revision:remote.revision,dirty:true,preserveCurrent:true});setRemote(undefined);blocked.current=false;void syncRef.current();}}>{t('scratch.use_local')}</button></div>}
  {error&&<p className="scratch-notice" role="alert">{error}</p>}
  {showCopies&&<div className="scratch-copies">{copies.length===0?<p>{t('scratch.no_copies')}</p>:copies.map(copy=><article key={copy.id}><time>{new Date(copy.created_at).toLocaleString()}</time><pre>{copy.content}</pre><button onClick={()=>void restore(copy)}>{t('scratch.restore')}</button><button onClick={()=>{if(window.confirm(t('scratch.delete_copy')))void api.deleteScratchCopy(copy.id).then(refreshExtras).catch(()=>setError(t('scratch.offline')));}}>{t('common.delete')}</button></article>)}</div>}
  {showImages&&<div className="scratch-copies">{images.map(asset=><article key={asset.id}><ProtectedImage asset={asset}/><button onClick={()=>edit(current.current.content+`\n![](synca-image:${asset.id})\n`)}>{t('scratch.insert')}</button><button disabled={current.current.dirty} onClick={()=>{if(window.confirm(t('scratch.delete_image')))void api.deleteScratchImage(asset.id).then(refreshExtras).catch(()=>setError(t('scratch.image_in_use')));}}>{t('common.delete')}</button></article>)}</div>}
  {preview?<div className="scratch-preview"><Markdown remarkPlugins={[remarkGfm]} skipHtml urlTransform={(url)=>url.startsWith('synca-image:')?url:/^https?:|^mailto:/i.test(url)?url:''} components={{img:({src})=><ProtectedImage asset={images.find(asset=>`synca-image:${asset.id}`===src)}/>,a:({children,href})=><a href={href} target="_blank" rel="noopener noreferrer">{children}</a>}}>{draft.content}</Markdown></div>:<textarea ref={editor} value={draft.content} maxLength={250000} onChange={e=>edit(e.target.value)} onPaste={e=>{const image=[...e.clipboardData.files].find(file=>file.type.startsWith('image/'));if(image){e.preventDefault();void upload(image);}}} aria-label={t('scratch.editor')} placeholder={t('scratch.placeholder')} spellCheck/>}
 </section>;
}
