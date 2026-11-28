const {test}=require('node:test'),assert=require('node:assert/strict');const {rect,windowAt,pixels}=require('./app/capture/geometry.cjs');
test('reversed drags clamp to a display and preserve positive size',()=>{assert.deepEqual(rect({x:90,y:80},{x:-10,y:10},{width:100,height:100}),{x:0,y:10,width:90,height:70});});
test('window picking respects front-to-back order and negative screen origins',()=>{
 const display={x:-1920,y:0,width:1920,height:1080};const windows=[{x:-1800,y:100,width:300,height:200},{x:-1900,y:0,width:1000,height:800}];
 assert.deepEqual(windowAt({x:-1700,y:150},windows,display),{x:120,y:100,width:300,height:200});assert.equal(windowAt({x:100,y:10},windows,display),null);
});
test('DIP crop maps exactly to Retina image pixels and never exceeds edges',()=>{
 assert.deepEqual(pixels({x:10,y:20,width:100,height:50},{width:2000,height:1000},{width:1000,height:500}),{x:20,y:40,width:200,height:100});
 assert.deepEqual(pixels({x:99.5,y:49.5,width:1,height:1},{width:200,height:100},{width:100,height:50}),{x:199,y:99,width:1,height:1});
});
const {validateSelection}=require('./app/capture/selection.cjs');
test('capture accepts equivalent local file URL encoding without accepting another document',()=>{
 const {isCaptureDocument}=require('./app/capture/trusted-document.cjs');
 const expected='file:///C:/Users/RUNNER%7E1/Synca%20Electron/resources/app.asar/capture/index.html';
 assert.equal(isCaptureDocument('file:///C:/Users/RUNNER~1/Synca%20Electron/resources/app.asar/capture/index.html',expected),true);
 for(const actual of [expected+'?other',expected+'#other',expected.replace('index.html','other.html'),expected.replace('file:///','https://example.com/'),'file://evil.example/C:/capture/index.html',expected.replace('capture/','capture%2F')])assert.equal(isCaptureDocument(actual,expected),false,actual);
 assert.equal(isCaptureDocument(undefined,expected),false);
});
test('IPC rejects malformed or oversized selections and limits annotation complexity',()=>{
 const display={width:1000,height:800};const good={rect:{x:10,y:20,width:200,height:150},marks:[{x:20,y:30,width:100,height:60,color:'#ff453a',stroke:3}]};
 assert.deepEqual(validateSelection(good,display),good);
 for(const value of [{...good,rect:{...good.rect,x:-1}},{...good,rect:{...good.rect,width:Infinity}},{...good,marks:Array(501).fill(good.marks[0])},{...good,marks:[{...good.marks[0],color:'url(evil)'}]}])assert.throws(()=>validateSelection(value,display));
});

test('Windows capture runs the packaged native helper and maps physical bounds to DIP',async()=>{
 const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');let invoked;
 const root=path.join(__dirname,'app/capture');
 const box={module:{exports:{}},__dirname:root,process:{platform:'win32',resourcesPath:'/fixture/resources',env:{}},require:id=>id==='electron'?{screen:{screenToDipRect:(_window,r)=>({...r,x:r.x/2,width:r.width/2})}}:id==='node:child_process'?{execFile:(file,args,options,callback)=>{invoked={file,args,options};callback(null,{stdout:'[{"x":200,"y":100,"width":800,"height":600}]'})}}:id.startsWith('./')?require(path.join(root,id)):require(id)};
 vm.runInNewContext(fs.readFileSync(path.join(root,'main.cjs'),'utf8'),box);
 const bounds=await box.module.exports.windowBounds();
 assert.equal(invoked.file,path.join('/fixture/resources','native','synca-window-bounds.exe'));
 assert.equal(invoked.args.length,0);assert.equal(invoked.options.timeout,5000);assert.equal(invoked.options.windowsHide,true);
 assert.equal(bounds[0].x,100);assert.equal(bounds[0].width,400);
});
