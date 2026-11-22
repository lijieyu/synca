const test=require('node:test');
const assert=require('node:assert/strict');
const { gateVerified, submitGate }=require('../app/tf-gate.cjs');
const home='https://synca-preview.haerth.cn';
const cookie={name:'synca_preview_gate',domain:'synca-preview.haerth.cn',hostOnly:true,httpOnly:true,secure:true,path:'/',sameSite:'lax'};
function fixture(state={}) {
 const requests=[];
 const session={
  cookies:{get:async()=>state.cookie?[state.cookie]:[]},
  fetch:async(url,options)=>{
   requests.push({url,options});
   if(url.endsWith('/__preview/unlock')){
    if(state.accept)state.cookie=cookie;
    return new Response(null,{status:state.accept?302:401});
   }
   return Response.json(state.body||{ok:true,service:'synca'},{status:state.status||200});
  }
 };
 return {session,requests};
}
test('preview credential is sent exactly once, only to selected TLS unlock route without following redirects',async()=>{
 const {session,requests}=fixture({accept:true});
 assert.equal(await submitGate(session,home,'synthetic','example-fixture-only'),true);
 assert.equal(requests[0].url,home+'/__preview/unlock');
 assert.equal(requests[0].options.redirect,'manual');
 assert.equal(requests[0].options.credentials,'include');
 assert.notEqual(requests[0].options.headers.Authorization,undefined);
 assert.equal(requests[1].url,home+'/health');
 assert.equal(requests[1].options.headers.Authorization,undefined);
});
test('wrong host or malformed credentials result in no request',async()=>{
 const {session,requests}=fixture({accept:true});
 for(const origin of ['http://synca-preview.haerth.cn','https://synca.haerth.cn','https://synca-preview.haerth.cn:8443','https://synca-preview.haerth.cn/']){
  assert.equal(await submitGate(session,origin,'synthetic','example-fixture-only'),false);
 }
 assert.equal(await submitGate(session,home,'bad:user','example-fixture-only'),false);
 assert.equal(requests.length,0);
});
test('gate accepts only host-scoped secure HttpOnly cookie and verified preview health',async()=>{
 assert.equal(await gateVerified(fixture({cookie:{...cookie,domain:'.haerth.cn'}}).session,home),false);
 assert.equal(await gateVerified(fixture({cookie:{...cookie,httpOnly:false}}).session,home),false);
 assert.equal(await gateVerified(fixture({cookie:{...cookie,secure:false}}).session,home),false);
 assert.equal(await gateVerified(fixture({cookie,status:401}).session,home),false);
 assert.equal(await gateVerified(fixture({cookie,body:{ok:true,service:'unrelated'}}).session,home),false);
 assert.equal(await gateVerified(fixture({cookie}).session,home),true);
});
