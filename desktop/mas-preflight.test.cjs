const test=require('node:test')
const assert=require('node:assert/strict')
const {variant}=require('./app/variant.cjs')
test('replacement identity preflight cannot contact app production or the ordinary preview host',()=>{
 const cfg=variant('mas-preflight')
 assert.equal(cfg.bundleId,'org.haerth.synca')
 assert.equal(cfg.profile,'Synca Electron TestFlight')
 assert.equal(cfg.offline,true)
 assert.equal(cfg.push,false)
 for(const u of ['https://synca.haerth.cn','https://synca-preview.haerth.cn','https://synca-preview.localhost','https://appleid.apple.com'])assert.equal(cfg.allows(u),false)
})
test('actual Mac TestFlight mode fixes the existing isolated HTTPS origin and keeps its own data path',()=>{
 const cfg=variant('mas-testflight')
 assert.equal(cfg.gate,true);
 assert.equal(cfg.offline,false);
 assert.equal(cfg.home,'https://synca-preview.haerth.cn');
 assert.equal(cfg.profile,'Synca Electron TestFlight');
 assert.equal(cfg.bundleId,'org.haerth.synca');
 assert.equal(cfg.push,false);
 assert.equal(cfg.allows('https://synca.haerth.cn/auth/email/code'),false);
 assert.equal(cfg.allows('https://synca-preview.haerth.cn/auth/email/code'),true);
});

test('only physical MAS preview binaries rely on macOS LaunchServices for singleton behavior',()=>{
 const {requestInstance}=require('./app/instance.cjs')
 let chromiumCalls=0
 const request=()=>{chromiumCalls++;return false}
 assert.equal(requestInstance({platform:'darwin',mas:true},'mas-testflight',request),true)
 assert.equal(requestInstance({platform:'darwin',mas:true},'mas-preflight',request),true)
 assert.equal(chromiumCalls,0)
 for(const [runtime,mode] of [
  [{platform:'darwin',mas:false},'mas-testflight'],
  [{platform:'darwin',mas:true},'production'],
  [{platform:'win32',mas:false},'production'],
  [{platform:'linux',mas:false},'local-preview'],
 ]) assert.equal(requestInstance(runtime,mode,request),false)
 assert.equal(chromiumCalls,4)
})
