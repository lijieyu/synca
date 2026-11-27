const {test}=require('node:test'),assert=require('node:assert/strict');
const {distribution}=require('./app/windows-distribution.cjs');
const {validateRelease}=require('./app/update-policy.cjs');
const {verifiedFeed}=require('./app/verified-feed.cjs');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),{createHash}=require('node:crypto');
const data=Buffer.from('verified package');
const release={version:'1.2.2',feed:'https://synca.haerth.cn/downloads/windows/x64/',url:'https://synca.haerth.cn/downloads/windows/x64/Synca-1.2.2-x64-Setup.exe',bytes:10,sha256:'a'.repeat(64),package:{name:'Synca-1.2.2-full.nupkg',bytes:data.length,sha256:createHash('sha256').update(data).digest('hex'),sha1:createHash('sha1').update(data).digest('hex')}};
test('Store marker and native Store identity independently disable website updates',()=>{
 for(const [runtime,marker] of [[true,null],[false,{channel:'store'}],[true,{channel:'website'}]])assert.equal(distribution('win32',runtime,marker).store,true);
 assert.equal(distribution('win32',false,null).store,false);
 assert.throws(()=>distribution('win32',false,{channel:'unknown'}));
 assert.equal(distribution('darwin',false,null).profile,null);
 assert.equal(distribution('win32',false,null).profile,'Synca Electron');
 assert.equal(distribution('win32',true,null).profile,'Synca Store');
});
test('release rejects malformed package metadata or path traversal',()=>{
 assert.equal(validateRelease(release,'win32','x64'),release);
 for(const patch of [{name:'../Synca-1.2.2-full.nupkg'},{name:'Synca-1.2.3-full.nupkg'},{sha256:'x'.repeat(64)},{sha1:'a'},{bytes:0}])assert.throws(()=>validateRelease({...release,package:{...release.package,...patch}},'win32','x64'));
});
test('verified loopback feed exposes only verified package and closes cleanly',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'synca-feed-test-'));let feed;
 try{
  const fetcher=async(url,opts)=>{assert.equal(url,release.feed+release.package.name);assert.equal(opts.redirect,'error');return new Response(data)};
  feed=await verifiedFeed(release,fetcher,root);
  assert.match(feed.url,/^http:\/\/127\.0\.0\.1:\d+\/[a-f0-9]{48}\/$/);
  assert.equal(await (await fetch(feed.url+'RELEASES')).text(),`${release.package.sha1} ${release.package.name} ${data.length}\n`);
  assert.deepEqual(Buffer.from(await (await fetch(feed.url+release.package.name)).arrayBuffer()),data);
  assert.equal((await fetch(feed.url+'missing')).status,404);
  assert.equal((await fetch(feed.url+'RELEASES',{method:'POST'})).status,405);
  await feed.close();await assert.rejects(fetch(feed.url+'RELEASES'));assert.deepEqual(await fs.readdir(root),[]);
  await assert.rejects(verifiedFeed({...release,package:{...release.package,sha256:'b'.repeat(64)}},fetcher,root));assert.deepEqual(await fs.readdir(root),[]);
 }finally{await feed?.close();await fs.rm(root,{recursive:true,force:true})}
});

test('Store startup registers no self-update timers, IPC or Squirrel shortcut process',()=>{
 const vm=require('node:vm'),syncFS=require('node:fs');
 for(const native of [true,false]){
  const box={module:{exports:{}},process:{platform:'win32',windowsStore:native,argv:['--squirrel-install']},require:id=>id==='electron'?{}:id.startsWith('./')?require(path.join(__dirname,'app',id)):id==='node:child_process'?{spawn(){throw Error('Store spawned installer')}}:require(id)};
  vm.runInNewContext(syncFS.readFileSync(path.join(__dirname,'app/updater.cjs'),'utf8'),box);
  assert.equal(box.module.exports.installUpdater(null,{store:!native},'1.2.1',()=>{}),undefined);
  assert.equal(box.module.exports.squirrelEvent({quit(){throw Error('Store quit')}},{store:!native}),false);
 }
});
