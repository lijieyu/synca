import { createComposerDrafts } from '../utils/composerDrafts';

// One desktop profile, one signed-in session. Only record metadata and text are cached.
const dbReady = new Promise<IDBDatabase>((resolve,reject)=>{
  const r=indexedDB.open('synca-desktop',1);
  r.onupgradeneeded=()=>r.result.createObjectStore('snapshots');
  r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);
});
function sessionId() {
  let value=localStorage.getItem('synca.desktop.session');
  if(!value){value=crypto.randomUUID();localStorage.setItem('synca.desktop.session',value)}
  return value;
}
export async function clearSnapshots() {
  localStorage.removeItem('synca.desktop.session');
  const db=await dbReady;
  db.transaction('snapshots','readwrite').objectStore('snapshots').clear();
}
export async function cachedList<T>(key:string,load:()=>Promise<T>,allowOffline=false):Promise<T> {
  const token=localStorage.getItem('authToken');
  const owner=sessionId();
  const current=()=>Boolean(token)&&token===localStorage.getItem('authToken');
  try{
    const value=await load();
    if(current()) void dbReady.then(db=>{
      if(current()) db.transaction('snapshots','readwrite').objectStore('snapshots').put({owner,value},key);
    }).catch(()=>{});
    return value;
  }catch(error){
    if(!allowOffline||!(error instanceof TypeError)||!current())throw error;
    const db=await dbReady;
    const saved=await new Promise<{owner:string;value:T}|undefined>((resolve,reject)=>{
      const r=db.transaction('snapshots').objectStore('snapshots').get(key);
      r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);
    });
    if(!current()||saved?.owner!==owner)throw error;
    return saved!.value;
  }
}
export function createDesktopDrafts() {
  try {
    const owner = sessionId();
    const token = localStorage.getItem('authToken');
    return createComposerDrafts(localStorage, owner, () => Boolean(token) &&
      token === localStorage.getItem('authToken') && owner === localStorage.getItem('synca.desktop.session'));
  } catch {
    return createComposerDrafts();
  }
}

// Save the merged view, never the response to /messages?since=.
export async function saveMessageSnapshot(messages: unknown[]) {
  const token=localStorage.getItem('authToken'), owner=sessionId();
  const db=await dbReady;
  if (!token || token!==localStorage.getItem('authToken') || owner!==localStorage.getItem('synca.desktop.session')) return;
  db.transaction('snapshots','readwrite').objectStore('snapshots').put({owner,value:{messages}},'messages');
}
