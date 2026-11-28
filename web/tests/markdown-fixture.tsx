// Isolated acceptance entry: real production surfaces, synthetic account APIs, no service writes.
import {useState} from 'react';
import {createRoot} from 'react-dom/client';
import {MessageBubble} from '../src/components/MessageBubble';
import {AuthProvider} from '../src/contexts/AuthContext';
import {Scratchpad} from '../src/components/Scratchpad';
import {api,MessageEditError,ScratchConflict,type SyncaMessage} from '../src/api/client';
import fixtures from '../../tests/fixtures/markdown-parity.json';
import '../src/i18n';
import {applyAppearance} from '../src/preferences';
import '../src/index.css';
import '../src/calm.css';
import './markdown-fixture.css';

applyAppearance('light');
localStorage.setItem('authToken','isolated-markdown-fixture');
localStorage.setItem('synca.language','zh-Hans');
localStorage.setItem('userId','markdown-fixture-account');
api.getMyProfile=async()=>({userId:'markdown-fixture-account',email:'fixture@example.invalid',isAdmin:false,plan:'pro'}) as Awaited<ReturnType<typeof api.getMyProfile>>;
const showcase=fixtures.find(fixture=>fixture.id==='showcase')!.source;
const stamp='2026-11-28T08:00:00.000Z';
const makeRecord=(text:string):SyncaMessage=>({id:'fixture-record',sourceDevice:'Acceptance',type:'text',textContent:text,imagePath:null,imageUrl:null,filePath:null,fileUrl:null,fileName:null,fileSize:null,fileMimeType:null,categoryId:null,categoryName:null,categoryColor:null,categoryIsDefault:false,isCleared:false,isDeleted:false,createdAt:stamp,updatedAt:stamp});
let record=makeRecord(showcase),cloud={content:showcase,revision:1},failure='none';
const delay=()=>new Promise(resolve=>setTimeout(resolve,180));
api.updateMessageText=async(_id,content)=>{await delay();if(failure==='record'){failure='none';throw new MessageEditError('message_edit_conflict');}record={...record,textContent:content,updatedAt:new Date().toISOString()};return record;};
api.getScratchpad=async()=>cloud;
api.saveScratchpad=async(_account,content)=>{await delay();if(failure==='scratch'){failure='none';throw new ScratchConflict({...cloud,revision:cloud.revision+1});}cloud={content,revision:cloud.revision+1};return cloud;};
api.getScratchCopies=async()=>({conflicts:[]});
api.preserveScratchCopy=async()=>cloud;
api.getScratchImages=async()=>({images:[{...makeRecord(''),id:'11111111-1111-4111-8111-111111111111',type:'image',imageUrl:'/fixture-owned-image'}]});
api.getProtectedFileBlob=async()=>new Blob(['<svg xmlns="http://www.w3.org/2000/svg" width="240" height="100"><rect width="240" height="100" rx="12" fill="#e4eef8"/><text x="22" y="58" font-family="sans-serif" font-size="20" fill="#243c58">Owned image fixture</text></svg>'],{type:'image/svg+xml'});
Object.assign(window,{markdownAcceptance:{record:()=>record.textContent,scratch:()=>cloud.content,failNext:(kind:string)=>{failure=kind;}}});
function Fixture(){
 const [message,setMessage]=useState(record),[selected,setSelected]=useState('showcase'),[generation,setGeneration]=useState(0),[theme,setTheme]=useState('light');
 function reset(id:string){const source=fixtures.find(fixture=>fixture.id===id)!.source;record=makeRecord(source);cloud={content:source,revision:1};failure='none';setMessage(record);setSelected(id);setGeneration(n=>n+1);}
 return <main className="markdown-acceptance" data-theme={theme}>
  <header><strong>Markdown · 跨端验收</strong><label>样例 <select value={selected} onChange={e=>reset(e.target.value)}>{fixtures.map(fixture=><option key={fixture.id}>{fixture.id}</option>)}</select></label><button onClick={()=>{const next=theme==='light'?'dark':'light';setTheme(next);applyAppearance(next);}}>切换明暗</button><button onClick={()=>{failure='record';}}>下次记录保存冲突</button><button onClick={()=>{failure='scratch';}}>下次草稿保存冲突</button><button onClick={()=>reset(selected)}>重置样例</button></header>
  <div className="fixture-surfaces"><section className="fixture-record"><h2>记录</h2><MessageBubble key={generation} message={message} categories={[]} onUpdate={()=>{}} onTextSaved={setMessage} onEdit={()=>{}}/></section><section className="fixture-scratch"><h2>草稿本</h2><Scratchpad key={generation} account={`markdown-acceptance-${generation}-${performance.timeOrigin}`}/></section></div>
 </main>;
}
createRoot(document.getElementById('root')!).render(<AuthProvider><Fixture/></AuthProvider>);
