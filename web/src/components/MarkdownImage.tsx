import {useEffect,useState} from 'react';
import {api,type SyncaMessage} from '../api/client';
import {useAuth} from '../contexts/AuthContext';
import type {MarkdownNode} from '../markdown/parse';

/** Shared authenticated image presentation. Source fallback stays visible until loading succeeds. */
export function ProtectedMarkdownImage({asset,alt='',fallback}:{asset?:SyncaMessage;alt?:string;fallback?:string}){
 const token=localStorage.getItem('authToken');
 const [loaded,setLoaded]=useState<{url:string;assetURL:string;token:string|null}>();
 useEffect(()=>{
  let live=true,objectURL:string|undefined;const assetURL=asset?.imageUrl;
  if(assetURL&&token)void api.getProtectedFileBlob(assetURL,{cacheImage:true}).then(blob=>{
   if(!live||token!==localStorage.getItem('authToken'))return;
   objectURL=URL.createObjectURL(blob);setLoaded({url:objectURL,assetURL,token});
  }).catch(()=>{});
  return()=>{live=false;if(objectURL)URL.revokeObjectURL(objectURL);};
 },[asset?.imageUrl,token]);
 return loaded&&loaded.assetURL===asset?.imageUrl&&loaded.token===token?<img className="markdown-owned-image" src={loaded.url} alt={alt}/>:<span>{fallback??(alt||'▧')}</span>;
}

export function OwnedMarkdownImage({node}:{node:MarkdownNode}){
 const {userId,token}=useAuth();
 const [resolved,setResolved]=useState<{account:string;token:string;id:string;asset:SyncaMessage|null}>();
 const id=node.url?.slice('synca-image:'.length)??'';
 useEffect(()=>{
  let live=true;
  if(userId&&token)void api.markdownImageAsset(userId,id).then(asset=>{if(live)setResolved({account:userId,token,id,asset});}).catch(()=>{});
  return()=>{live=false;};
 },[id,userId,token]);
 const asset=resolved?.account===userId&&resolved?.token===token&&resolved?.id===id?resolved.asset:undefined;
 return <ProtectedMarkdownImage asset={asset??undefined} alt={node.alt} fallback={node.source}/>;
}
