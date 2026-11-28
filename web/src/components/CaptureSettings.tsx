import {useEffect,useState} from 'react';
import {useTranslation} from 'react-i18next';
export function CaptureSettings(){
 const {t}=useTranslation();const [shortcut,setShortcut]=useState('CommandOrControl+Shift+A'),[error,setError]=useState(false),[busy,setBusy]=useState(false);
 const desktop=window.syncaDesktop;
 useEffect(()=>{void desktop?.captureSettings?.().then(value=>{setShortcut(value.shortcut);setError(value.error);}).catch(()=>setError(true));},[desktop]);
 if(!desktop?.captureShortcut)return null;
 const key=(event:React.KeyboardEvent<HTMLInputElement>)=>{
  if(['Tab','Escape'].includes(event.key))return;event.preventDefault();if(busy||!/^[a-z0-9]$/i.test(event.key)||!(event.metaKey||event.ctrlKey||event.altKey))return;
  const keys=[...(event.metaKey?['Command']:[]),...(event.ctrlKey?['Control']:[]),...(event.altKey?['Alt']:[]),...(event.shiftKey?['Shift']:[]),event.key.toUpperCase()].join('+');
  setBusy(true);void desktop.captureShortcut!(keys).then(value=>{setShortcut(value.shortcut);setError(value.error);}).catch(()=>setError(true)).finally(()=>setBusy(false));
 };
 return <><h3>{t('capture.title')}</h3><div className="settings-pref-group"><label>{t('capture.shortcut')}<input value={shortcut.replace('CommandOrControl',desktop.platform==='macOS'?'Command':'Control')} onKeyDown={key} readOnly aria-label={t('capture.shortcut')} aria-describedby="capture-shortcut-help" disabled={busy}/></label><p id="capture-shortcut-help">{t('capture.help')}</p>{error&&<p role="alert">{t('capture.conflict')}</p>}<div className="desk-row"><span>{t('capture.description')}</span><button onClick={()=>void desktop.captureStart?.()}>{t('capture.start')}</button></div></div></>;
}
