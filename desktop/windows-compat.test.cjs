const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const {EventEmitter}=require('node:events');
const root=process.env.SYNCA_DESKTOP_ROOT||process.cwd();

async function saveDialogName(name){
 const handlers={};let selected;
 const page=new EventEmitter();page.getZoomFactor=()=>1;
 const electron={app:{once(){}},dialog:{showSaveDialog:async(_window,options)=>{selected=options.defaultPath;return {canceled:true}}},Menu:{buildFromTemplate:items=>({popup(){items[0].click()},closePopup(){}})}};
 const box={module:{exports:{}},process:{platform:'win32'},Buffer,URL,Blob,AbortSignal,setImmediate,console,require:id=>id==='electron'?electron:id==='node:path'?path.win32:id.startsWith('./')?require(path.join(root,'app',id)):require(id)};
 vm.runInNewContext(fs.readFileSync(path.join(root,'app/context-menu.cjs'),'utf8'),box);
 box.module.exports.installContextMenus({webContents:page},{},(name,fn)=>handlers[name]=fn,()=> 'fixture',()=> 'C:\\Downloads',{home:'https://synca.haerth.cn'});
 await handlers['record-menu']({items:[{id:'saveAs',label:'Save as'}],attachment:{url:'/api/media/test.png',name,kind:'file'}});
 return selected;
}

test('Windows attachment save dialog gets legal names, preserving Chinese and extension',async()=>{
 for(const [input,expected] of [['周报?.txt','周报_.txt'],['CON.txt','_CON.txt'],['LPT1','_LPT1'],['AUX.','_AUX'],['报告.txt. ','报告.txt'],['a<|>*\".png','a_____.png'],['..\\NUL.txt','_NUL.txt'],['普通文档.txt','普通文档.txt']]){
  assert.equal(await saveDialogName(input),'C:\\Downloads\\'+expected,input);
 }
 const long=await saveDialogName('🙂'.repeat(140)+'.txt');
 assert(path.win32.basename(long).length<=150);
 assert(!/[\uD800-\uDBFF]$/.test(path.win32.basename(long)));
});

async function mainFixture(platform){
 let menu,window;
 const app=Object.assign(new EventEmitter(),{getVersion:()=> '1.2.0',getLocale:()=> 'zh-CN',requestSingleInstanceLock:()=>true,isReady:()=>true,whenReady:()=>Promise.resolve(),setAppUserModelId(){},quit(){}});
 class BrowserWindow extends EventEmitter{
  constructor(options){super();this.options=options;this.webContents=Object.assign(new EventEmitter(),{sent:[],setWindowOpenHandler(){},send(...args){this.sent.push(args)}});window=this;}
  getSize(){return [1040,760]} getContentSize(){return [1024,721]}
  setMinimumSize(width,height){this.minimum=[width,height]}
  loadURL(){return Promise.resolve()} isVisible(){return true} isFocused(){return true}
 }
 const electron={app,BrowserWindow,Menu:{buildFromTemplate:x=>x,setApplicationMenu:x=>menu=x},session:{defaultSession:{setPermissionRequestHandler(){},setPermissionCheckHandler(){}}},shell:{},dialog:{}};
 const box={module:{exports:{}},__dirname:path.join(root,'app'),process:{platform,env:{}},URL,console,require:id=>id==='electron'?electron:id==='./platform.cjs'?{installPlatform(){}}:id==='./local-ui.cjs'?{installLocalUI(){}}:id.startsWith('./')?require(path.join(root,'app',id)):require(id)};
 vm.runInNewContext(fs.readFileSync(path.join(root,'app/main.cjs'),'utf8'),box);
 await new Promise(resolve=>setImmediate(resolve));
 return {window,items:menu.flatMap(x=>x.submenu||[])};
}

test('Windows keeps desktop layout and exposes Ctrl+Shift+Delete with IME/repeat guards',async()=>{
 const f=await mainFixture('win32');
 assert(f.window.options.minWidth>=640);assert(f.window.options.minHeight>=500);
 assert.deepEqual(f.window.minimum,[656,539], 'minimum applies to the content, excluding Windows frame');
 const item=f.items.find(x=>x.id==='clear-completed');assert(item,'Windows File menu offers scoped clearing');
 assert.equal(item.accelerator,'Control+Shift+Delete');
 const input={type:'keyDown',key:'Delete',control:true,shift:true,meta:false,alt:false};
 for(const extra of [{isAutoRepeat:true},{isComposing:true},{type:'keyUp'},{}]){
  let blocked=false;const n=f.window.webContents.sent.length;
  f.window.webContents.emit('before-input-event',{preventDefault(){blocked=true;}},{...input,...extra});
  assert(blocked);assert.equal(f.window.webContents.sent.length-n,Object.keys(extra).length?0:1);
 }
 let blocked=false;
 f.window.webContents.emit('before-input-event',{preventDefault(){blocked=true;}},{...input,shift:false});
 assert.equal(blocked,false,'ordinary Ctrl+Delete remains a text-editing shortcut');
});

test('Mac keeps its existing clear accelerator and minimum window',async()=>{
 const f=await mainFixture('darwin');assert.equal(f.window.options.minWidth,640);assert.equal(f.window.options.minHeight,500);
 const item=f.items.find(x=>x.id==='clear-completed');assert.equal(item.accelerator,'Command+Shift+Backspace');
});
