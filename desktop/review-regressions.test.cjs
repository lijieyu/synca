const {test}=require('node:test');const assert=require('node:assert/strict');
const {localRequest}=require('./app/local-ui.cjs');
test('local preview forwards scratchpad, collection and upload contracts',async()=>{
 const original=global.fetch;const calls=[];
 global.fetch=async(url,options)=>{calls.push({url,options});return Response.json(url.endsWith('health')?{purpose:'synca-electron-local-preview'}:{ok:true});};
 try{
  for(const pathname of ['/scratchpad','/scratchpad/images','/scratchpad/conflicts','/app-updates','/sync/state']){
   const request=new Request('https://fixture.invalid'+pathname,{headers:{'Authorization':'Bearer fixture','X-Synca-Account':'account-a','X-Synca-Features':'collections','X-Upload-Size':'123','X-Upload-ID':'upload'}});
   assert.equal((await localRequest({upstream:'http://127.0.0.1:1234',readAdmission:()=> 'local-only'},new URL(request.url),request)).status,200);
   const forwarded=calls.at(-1).options.headers;
   assert.equal(forwarded.get('X-Synca-Account'),'account-a');assert.equal(forwarded.get('X-Synca-Features'),'collections');assert.equal(forwarded.get('X-Upload-Size'),'123');
  }
  const blocked=new Request('https://fixture.invalid/admin');assert.equal((await localRequest({},new URL(blocked.url),blocked)).status,404);
 }finally{global.fetch=original;}
});

test('local media responses preserve the virtual attachment origin without rewriting user content',async()=>{
 const {localMediaResponse}=require('./app/local-ui.cjs');
 const payload={images:[{imageUrl:'http://127.0.0.1:1234/api/media/a.png',textContent:'http://127.0.0.1:1234/api/media/a.png'},{imageUrl:'https://untrusted.invalid/api/media/a.png'}]};
 const response=await localMediaResponse(Response.json(payload),{upstream:'http://127.0.0.1:1234',home:'https://fixture.invalid'});
 const result=await response.json();assert.equal(result.images[0].imageUrl,'https://fixture.invalid/api/media/a.png');assert.equal(result.images[0].textContent,payload.images[0].textContent);assert.equal(result.images[1].imageUrl,payload.images[1].imageUrl);
});
