import assert from 'node:assert/strict';
const base='http://127.0.0.1:3004';
const shared={Host:'synca-preview.haerth.cn','X-Forwarded-Host':'synca-preview.haerth.cn','X-Forwarded-Proto':'https'};
const unlock=await fetch(base+'/__preview/unlock',{headers:{...shared,'X-Preview-Authenticated':'1'},redirect:'manual'});
assert.equal(unlock.status,302);shared.Cookie=unlock.headers.get('set-cookie').split(';')[0];
async function request(p,options={}){return fetch(base+p,{...options,headers:{...shared,...options.headers}})}
assert.equal((await request('/health')).status,200);
assert.equal((await fetch(base+'/health')).status,421);
assert.equal((await request('/__preview/session',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"profile":"free"}'})).status,403);
for(const profile of ['free','unlimited']){
 const r=await request('/__preview/session',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://synca-preview.haerth.cn'},body:JSON.stringify({profile})});
 assert.equal(r.status,200);const {token}=await r.json();
 const headers={Authorization:`Bearer ${token}`,'Content-Type':'application/json'};
 const me=await(await request('/me/access-status',{headers})).json();
 assert.equal(me.accessStatus.isUnlimited,profile==='unlimited');
 const categories=await(await request('/message-categories',{headers})).json();assert.ok(JSON.stringify(categories).includes('工作'));
 const create=await request('/messages',{method:'POST',headers,body:JSON.stringify({type:'text',textContent:'预发独立接口验收',sourceDevice:'QA'})});
 assert.equal(create.status,201);const msg=await create.json();
 const edit=await request(`/messages/${msg.id}/text`,{method:'PATCH',headers,body:JSON.stringify({textContent:'预发编辑验证成功',expectedUpdatedAt:msg.updatedAt})});assert.equal(edit.status,200);
 assert.equal((await request('/me/purchases/sync',{method:'POST',headers,body:'{}'})).status,403);
 console.log(`PASS ${profile}: profile, isolated categories, create/edit, purchase blocked`);
}
const html=await(await request('/')).text();assert.ok(html.includes('/__preview/bootstrap.js'));assert.ok(!html.includes('authToken"'));
assert.equal((await request('/__preview/')).status,200);
console.log('PASS: host guard, origin guard, preview entry and production artifact overlay');
