import {useEffect,useState} from 'react';
import './UpdateNotice.css';
import {useTranslation} from 'react-i18next';
import {api} from '../api/client';
export interface UpdateState {phase:'idle'|'checking'|'current'|'available'|'downloading'|'ready'|'installing'|'error';version?:string;store?:boolean;migration?:boolean}
export function UpdateNotice({manual=false}:{manual?:boolean}) {
 const {t}=useTranslation();const [state,setState]=useState<UpdateState>({phase:'idle'});const [hidden,setHidden]=useState(false);const [blocked,setBlocked]=useState(false);const [engaged,setEngaged]=useState(false);
 const desktop=window.syncaDesktop;
 useEffect(()=>{if(!desktop?.updateState)return;
  const refresh=()=>{void desktop.updateState!().then(next=>{setState(next);setHidden(!manual&&Number(localStorage.getItem(`synca-update-snooze:${next.version}`))>Date.now());}).catch(()=>{});};refresh();return desktop.subscribe('update',refresh);
 },[desktop,manual]);
 if(!desktop?.updateAction||(!manual&&(hidden||!['available','downloading','ready',...(engaged?['error','checking','installing']:[])].includes(state.phase))))return null;
 async function act(action:'check'|'download'|'install'){
  if(action==='install'&&!api.canRestartForUpdate()){setBlocked(true);return;}
  setBlocked(false);setHidden(false);setEngaged(true);
  try{setState(await desktop!.updateAction!(action));}catch{setState({phase:'error'});}
 }
 return <div className="update-notice" role="status">
  <span>{t(`updates.${state.phase}`,{version:state.version})}</span>
  {state.phase==='available'&&<button onClick={()=>void act('download')}>{t(state.store?'updates.store':'updates.download')}</button>}
  {state.phase==='available'&&state.migration&&!state.store&&<small>{t('updates.migration')}</small>}
  {state.phase==='ready'&&<button onClick={()=>void act('install')}>{t('updates.restart')}</button>}
  {(manual||engaged&&state.phase==='error')&&['idle','current','error'].includes(state.phase)&&<button onClick={()=>void act('check')}>{t('updates.check')}</button>}
  {!manual&&state.phase==='available'&&<button onClick={()=>{localStorage.setItem(`synca-update-snooze:${state.version}`,String(Date.now()+86400000));setHidden(true);}}>{t('updates.later')}</button>}
  {blocked&&<p role="alert">{t('updates.finish_edit')}</p>}
 </div>;
}
