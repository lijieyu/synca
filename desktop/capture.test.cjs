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
test('IPC rejects malformed or oversized selections and limits annotation complexity',()=>{
 const display={width:1000,height:800};const good={rect:{x:10,y:20,width:200,height:150},marks:[{x:20,y:30,width:100,height:60,color:'#ff453a',stroke:3}]};
 assert.deepEqual(validateSelection(good,display),good);
 for(const value of [{...good,rect:{...good.rect,x:-1}},{...good,rect:{...good.rect,width:Infinity}},{...good,marks:Array(501).fill(good.marks[0])},{...good,marks:[{...good.marks[0],color:'url(evil)'}]}])assert.throws(()=>validateSelection(value,display));
});

test('Windows capture uses native PowerShell modules even when launched from PowerShell 7',async()=>{
 const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');let options;
 const root=path.join(__dirname,'app/capture');
 const box={module:{exports:{}},__dirname:root,process:{platform:'win32',env:{SystemRoot:'C:\\Windows',PSModulePath:'C:\\Program Files\\PowerShell\\7\\Modules'}},require:id=>id==='electron'?{screen:{screenToDipRect:(_window,r)=>r}}:id==='node:child_process'?{execFile:(_file,_args,value,callback)=>{options=value;callback(null,{stdout:'[]'})}}:id.startsWith('./')?require(path.join(root,id)):require(id)};
 vm.runInNewContext(fs.readFileSync(path.join(root,'main.cjs'),'utf8'),box);await box.module.exports.windowBounds();
 assert.ok(options.env,'inheritance must be explicitly sanitized');assert.equal(Object.keys(options.env).some(key=>key.toLowerCase()==='psmodulepath'),false);assert.equal(options.env.SystemRoot,'C:\\Windows');
});
