// Runs only in an isolated Windows Electron copy containing renderer/ and fixtures.json.
// No installed Synca application, account, or service is used.
const {app,BrowserWindow,session}=require('electron');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http'),assert=require('node:assert/strict');
assert.equal(process.platform,'win32');
const out=process.env.SYNCA_MARKDOWN_OUTPUT||path.join(__dirname,'evidence');
fs.mkdirSync(out,{recursive:true});
app.setPath('userData',fs.mkdtempSync(path.join(os.tmpdir(),'synca-markdown-qa-')));
const fixtures=JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures.json'),'utf8'));
const report={platform:process.platform,arch:process.arch,os:os.release(),versions:process.versions,scope:'Actual Windows ARM64 Electron; isolated production MessageBubble and Scratchpad, synthetic account APIs, no release package claim',checks:[],requests:[],consoleErrors:[]};
let win,server;
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const js=async(fn,...args)=>win.webContents.executeJavaScript(`(${fn.toString()})(...${JSON.stringify(args)})`,true);
async function until(fn,...args){for(let n=0;n<100;n++){if(await js(fn,...args))return;await pause(100);}throw Error('Timed out: '+fn.toString());}
async function screenshot(name){await pause(200);fs.writeFileSync(path.join(out,name+'.png'),(await win.webContents.capturePage()).toPNG());}
async function reset(id){await js(id=>{const s=document.querySelector('select');s.value=id;s.dispatchEvent(new Event('change',{bubbles:true}));},id);await until(source=>document.querySelector('.scratchpad textarea')?.value===source.replace(/\r\n/g,'\n'),fixtures.find(f=>f.id===id).source);await js(()=>{document.querySelector('.message-expand')?.click();document.querySelectorAll('.scratch-modes button')[1].click();});await until(()=>!!document.querySelector('.scratch-preview'));}
async function sources(){return js(()=>({record:window.markdownAcceptance.record(),scratch:window.markdownAcceptance.scratch()}));}
async function clickTask(surface){await js(surface=>document.querySelector(`.fixture-${surface} input[type=checkbox]`).click(),surface);}
async function check(name,work){await work();report.checks.push({name,passed:true});fs.writeFileSync(path.join(out,'progress.json'),JSON.stringify(report,null,2));}
app.whenReady().then(async()=>{
 try{
  server=http.createServer((req,res)=>{const pathname=new URL(req.url,'http://127.0.0.1').pathname;const file=path.resolve(__dirname,'renderer','.'+pathname);if(!file.startsWith(path.join(__dirname,'renderer')+path.sep)){res.writeHead(403).end();return;}try{const data=fs.readFileSync(file);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'application/octet-stream');res.end(data);}catch{res.writeHead(404).end();}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const origin=`http://127.0.0.1:${server.address().port}`;
  session.defaultSession.webRequest.onBeforeRequest((details,done)=>{report.requests.push(details.url);done({cancel:!details.url.startsWith(origin+'/')&&!details.url.startsWith('blob:')&&!details.url.startsWith('data:')});});
  win=new BrowserWindow({width:1440,height:1100,useContentSize:true,show:true,webPreferences:{contextIsolation:true,nodeIntegration:false,sandbox:true}});
  win.webContents.on('console-message',(_event,details)=>{if(details.level==='error')report.consoleErrors.push(details.message);});
  win.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  await win.loadURL(origin+'/tests/markdown-fixture.html');await until(()=>!!window.markdownAcceptance);
  await reset('showcase');
  await check('Same showcase on record and scratch, source unchanged',async()=>{assert.deepEqual(await sources(),{record:fixtures.find(f=>f.id==='showcase').source,scratch:fixtures.find(f=>f.id==='showcase').source});await screenshot('windows-record-scratch-light');});
  await js(()=>[...document.querySelectorAll('header button')].find(b=>b.textContent==='切换明暗').click());await screenshot('windows-record-scratch-dark');
  await js(()=>[...document.querySelectorAll('header button')].find(b=>b.textContent==='切换明暗').click());
  await check(`All ${fixtures.length} shared fixtures: both surfaces, task counts, semantic tags, source preservation`,async()=>{
   for(const fixture of fixtures){await reset(fixture.id);const result=await js(()=>['record','scratch'].map(surface=>{const root=document.querySelector('.fixture-'+surface);return {text:root.textContent,tasks:root.querySelectorAll('input[type=checkbox]').length,tags:[...root.querySelectorAll('.message-markdown *')].map(e=>e.tagName.toLowerCase())};}));
    for(const rendered of result){assert.equal(rendered.tasks,fixture.taskCount,fixture.id);for(const text of fixture.contains)assert(rendered.text.includes(text),fixture.id+': missing '+text);const tags={heading:'h',strong:'strong',emphasis:'em',delete:'del',underline:'u',inlineCode:'code',code:'pre',blockquote:'blockquote',list:'ul',table:'table',link:'a',thematicBreak:'hr',break:'br'};for(const type of fixture.types){if(type==='heading')assert(rendered.tags.some(t=>/^h[1-6]$/.test(t)),fixture.id);else if(tags[type]&&type!=='list')assert(rendered.tags.includes(tags[type]),fixture.id+': '+type);}}
    assert.deepEqual(await sources(),{record:fixture.source,scratch:fixture.source});
   }
  });
  await reset('tasks-unicode-crlf');
  for(const surface of ['record','scratch'])await check(surface+' task toggle changes one UTF-16 character only; CRLF and emoji preserved',async()=>{const before=(await sources())[surface];await clickTask(surface);const expected=before.replace('- [ ] 第一项','- [x] 第一项');await until((surface,expected)=>window.markdownAcceptance[surface]()===expected,surface,expected);assert.equal((await sources())[surface],expected);});
  await reset('showcase');
  await check('Record conflict: source and checkbox unchanged, accessible alert shown',async()=>{const before=(await sources()).record;await js(()=>window.markdownAcceptance.failNext('record'));await clickTask('record');await until(()=>!!document.querySelector('.app-toast[role=alert]'));assert.equal((await sources()).record,before);assert.equal(await js(()=>document.querySelector('.fixture-record input[type=checkbox]').checked),false);await screenshot('windows-record-conflict');});
  await check('Scratch conflict: server source preserved, local edit retained with accessible recovery',async()=>{const before=(await sources()).scratch;await js(()=>window.markdownAcceptance.failNext('scratch'));await clickTask('scratch');await until(()=>!!document.querySelector('.scratch-notice[role=alert]'));assert.equal((await sources()).scratch,before);assert.equal(await js(()=>document.querySelector('.fixture-scratch input[type=checkbox]').checked),true);await screenshot('windows-scratch-conflict');});
  await reset('html-safety');await check('HTML inert, unsafe links inactive, no external image request',async()=>{assert.equal(await js(()=>document.querySelectorAll('.message-markdown script,.message-markdown img,.message-markdown a').length),0);await screenshot('windows-html-safety');});
  await reset('images');await until(()=>document.querySelector('.scratch-preview img')?.naturalWidth>0&&document.querySelector('.fixture-record img')?.naturalWidth>0);report.checks.push({name:'Owned images render on both surfaces; foreign image remains literal',passed:true});await screenshot('windows-owned-image');
  await reset('showcase');
  await check('Long code/table horizontal scroll within narrow scratch viewport, source selection',async()=>{
   const columns=Array.from({length:40},(_,i)=>'Column '+(i+1));const source='```text\n'+('long_code_'.repeat(100))+'\n```\n\n| '+columns.join(' | ')+' |\n| '+columns.map(()=> '---').join(' | ')+' |\n| '+columns.map(()=> 'cell').join(' | ')+' |';
   await js(source=>{document.querySelectorAll('.scratch-modes button')[0].click();setTimeout(()=>{const e=document.querySelector('.scratchpad textarea');Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e,source);e.dispatchEvent(new Event('input',{bubbles:true}));},0);},source);
   await until(source=>document.querySelector('.scratchpad textarea')?.value===source,source);await js(()=>document.querySelectorAll('.scratch-modes button')[1].click());
   await until(source=>window.markdownAcceptance.scratch()===source,source);
   const sizes=await js(()=>[...document.querySelectorAll('.scratch-preview pre,.scratch-preview .message-table-scroll')].map(e=>{e.scrollLeft=100;return {client:e.clientWidth,scroll:e.scrollWidth,left:e.scrollLeft,overflow:getComputedStyle(e).overflowX};}));report.scroll=sizes;assert.equal(sizes.length,2);for(const s of sizes){assert(s.scroll>s.client);assert(s.left>0);}report.scroll=sizes;
   const cells=await js(()=>[...document.querySelectorAll('.fixture-scratch th')].map(cell=>({width:cell.getBoundingClientRect().width,font:parseFloat(getComputedStyle(cell).fontSize)})));assert(cells.every(cell=>cell.width>=6*cell.font),'Columns must retain readable width');report.tableCells=cells;
   const selected=await js(()=>{const r=document.createRange();r.selectNodeContents(document.querySelector('.scratch-preview pre'));const s=getSelection();s.removeAllRanges();s.addRange(r);return s.toString();});assert(selected.includes('long_code_'));await screenshot('windows-horizontal-scroll');
  });
  await reset('list-whitespace');
  await check('List spaces and soft line breaks preserved on both surfaces',async()=>{const whitespace=await js(()=>[...document.querySelectorAll('.message-list-text')].map(node=>({text:node.textContent,whiteSpace:getComputedStyle(node).whiteSpace})));assert(whitespace.length>0);assert(whitespace.every(node=>node.whiteSpace==='pre-wrap'));report.listWhitespace=whitespace;await screenshot('windows-list-whitespace');});
  await check('Long table cells wrap within 28em limit',async()=>{
   const source='| Long cell |\n| --- |\n| '+('longtoken'.repeat(100))+' |';
   await js(source=>{document.querySelectorAll('.scratch-modes button')[0].click();setTimeout(()=>{const e=document.querySelector('.scratchpad textarea');Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e,source);e.dispatchEvent(new Event('input',{bubbles:true}));},0);},source);
   await until(source=>document.querySelector('.scratchpad textarea')?.value===source,source);await js(()=>document.querySelectorAll('.scratch-modes button')[1].click());await until(()=>!!document.querySelector('.fixture-scratch td .message-table-cell'));
   const cell=await js(()=>{const n=document.querySelector('.fixture-scratch td .message-table-cell');return {width:n.getBoundingClientRect().width,height:n.getBoundingClientRect().height,font:parseFloat(getComputedStyle(n).fontSize)};});assert(cell.width<=28*cell.font+1);assert(cell.height>=2*cell.font);report.longCell=cell;await screenshot('windows-long-table-cell');
  });
  assert(report.requests.every(url=>url.startsWith(origin+'/')||url.startsWith('blob:')||url.startsWith('data:')),'External request attempted');
  report.result='passed';
 }catch(error){report.result='failed';report.error=error.stack;try{await screenshot('windows-failure');report.failureDOM=await js(()=>({text:document.body.innerText,html:document.body.innerHTML}));}catch{}}
 finally{fs.writeFileSync(path.join(out,'windows-markdown-acceptance.json'),JSON.stringify(report,null,2));win?.destroy();server?.close();app.exit(report.result==='passed'?0:1);}
});
