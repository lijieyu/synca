const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
const {readBuildInfo}=require('./app/build-info.cjs');
test('runtime identity reads the packaged build and safely handles development or invalid metadata',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'synca-build-info-'));
 try{
  assert.deepEqual(readBuildInfo(dir,'1.2.0'),{version:'1.2.0',build:''});
  fs.writeFileSync(path.join(dir,'build-info.json'),JSON.stringify({version:'1.2.0',build:'87'}));
  assert.deepEqual(readBuildInfo(dir,'0.0.0'),{version:'1.2.0',build:'87'});
  fs.writeFileSync(path.join(dir,'build-info.json'),JSON.stringify({version:'1.3.0',build:'104'}));
  assert.deepEqual(readBuildInfo(dir,'1.2.0'),{version:'1.3.0',build:'104'});
  fs.writeFileSync(path.join(dir,'build-info.json'),'{broken');
  assert.deepEqual(readBuildInfo(dir,'1.2.0'),{version:'1.2.0',build:''});
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('preload exposes packaged identity instead of a literal version',()=>{
 const vm=require('node:vm');let exposed;
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'app/preload.cjs'),'utf8'),{
  require:()=>({contextBridge:{exposeInMainWorld:(_name,value)=>{exposed=value;}},ipcRenderer:{}}),
  process:{argv:['--synca-version=1.3.0','--synca-build=104'],platform:'darwin',isMainFrame:true},
  location:{origin:'https://synca.haerth.cn'},
 });
 assert.equal(exposed.version,'1.3.0');assert.equal(exposed.build,'104');
});
test('archive identity uses the final plist even when the prepared build was older',{skip:process.platform!=='darwin'},()=>{
 const {execFileSync}=require('node:child_process');const dir=fs.mkdtempSync(path.join(os.tmpdir(),'synca-final-plist-'));
 try{
  const plist=path.join(dir,'Info.plist');
  fs.writeFileSync(plist,'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>1.3.0</string><key>CFBundleVersion</key><string>104</string></dict></plist>');
  execFileSync('/usr/bin/plutil',['-convert','binary1',plist]);
  fs.writeFileSync(path.join(dir,'build-info.json'),JSON.stringify({version:'1.2.0',build:'87'}));
  execFileSync('/bin/bash',[path.join(__dirname,'mas/write-build-info.sh'),plist,dir]);
  assert.deepEqual(readBuildInfo(dir,'1.2.0'),{version:'1.3.0',build:'104'});
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
