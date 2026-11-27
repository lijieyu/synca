const {test}=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events');
const {UpdateController,downloadInstaller}=require('./app/updater.cjs');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),{createHash}=require('node:crypto');
const release={version:'1.2.2',feed:'https://synca.haerth.cn/downloads/windows/x64/',url:'https://synca.haerth.cn/downloads/windows/x64/Synca-1.2.2-x64-Setup.exe',sha256:'a'.repeat(64),bytes:100};
test('installed Windows requires ready download before restart',async()=>{
 const native=new EventEmitter();let checks=0,restarts=0;native.setFeedURL=({url})=>assert.equal(url,'http://127.0.0.1/verified/');native.checkForUpdates=()=>checks++;native.quitAndInstall=()=>restarts++;
 const updater=new UpdateController({platform:'win32',arch:'x64',version:'1.2.1',installed:true,autoUpdater:native,prepareFeed:async()=>({url:'http://127.0.0.1/verified/',close:async()=>{}}),catalog:async()=>({windows:{x64:release}}),prepareRestart:()=>{}});
 await updater.install();assert.equal(restarts,0);assert.equal((await updater.check()).phase,'available');await updater.download();assert.equal(checks,1);await updater.install();assert.equal(restarts,0);
 native.emit('update-downloaded');assert.equal(updater.state.phase,'ready');await updater.install();assert.equal(restarts,1);
});
test('download fails closed on size or digest mismatch and removes staged executable',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'synca-updater-test-'));try{
  const data=Buffer.from('test installer'),manifest={...release,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')};
  const fetcher=async()=>new Response(data);
  for(const bad of [{...manifest,bytes:1},{...manifest,sha256:'b'.repeat(64)}]){await assert.rejects(downloadInstaller(bad,fetcher,root));assert.deepEqual(await fs.readdir(root),[]);}
  const file=await downloadInstaller(manifest,fetcher,root);assert.deepEqual(await fs.readFile(file.path),data);
 }finally{await fs.rm(root,{recursive:true,force:true});}
});
test('macOS uses only the store and never downloads executable updates',async()=>{
 let opened;const updater=new UpdateController({platform:'darwin',version:'1.2.1',catalog:async()=>({macos:{version:'1.2.2',storeURL:'https://apps.apple.com/app/id6761647007'}}),openStore:async url=>opened=url});
 await updater.check();await updater.download();assert.equal(opened,'https://apps.apple.com/app/id6761647007');assert.equal(updater.state.phase,'available');
});
