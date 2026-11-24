import { beforeAll, afterEach, expect, it } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import app from '../src/app.js';
import { db } from '../src/db.js';
import { createSession, createUser } from '../src/store.js';
import { runMigrations } from '../src/migrate.js';
import { closeSyncStreams, notifySync } from '../src/syncEvents.js';
let servers: ReturnType<typeof app.listen>[] = [];
beforeAll(() => runMigrations());
afterEach(() => { closeSyncStreams(); servers.forEach(s => s.closeAllConnections()); servers.forEach(s => s.close()); servers=[]; });
async function user() {
 const id=randomUUID(), token=randomUUID();
 await createUser({id,appleUserId:id,email:'sync-test@example.invalid',nickname:'Sync test',now:new Date().toISOString()});
 await createSession(token,id);
 return {id,token,auth:'Bearer '+token};
}
it('requires session authentication and returns stable scope hashes without content',async()=>{
 expect((await request(app).get('/sync/state')).status).toBe(401);
 expect((await request(app).get('/sync/events')).status).toBe(401);
 const u=await user();
 const get=()=>request(app).get('/sync/state').set('Authorization',u.auth);
 const a=await get(); expect(a.status).toBe(200); expect(JSON.stringify(a.body).length).toBeLessThan(500);
 expect((await get()).body).toEqual(a.body);
 const made=await request(app).post('/messages').set('Authorization',u.auth).send({textContent:'never include my text in notification'});
 expect(made.status).toBe(201);
 const b=await get(); expect(b.body.messages).not.toBe(a.body.messages); expect(b.body.count).toBe(1);
 expect(b.body.categories).toBe(a.body.categories); expect(JSON.stringify(b.body)).not.toContain('never include');
 await request(app).delete('/messages/'+made.body.id).set('Authorization',u.auth);
 const c=await get(); expect(c.body.messages).not.toBe(b.body.messages); expect(c.body.count).toBe(0);
 const cat=await request(app).post('/message-categories').set('Authorization',u.auth).send({name:'New category',color:'sky'});
 expect(cat.status).toBe(201); const d=await get(); expect(d.body.categories).not.toBe(c.body.categories);
 await db.updateTable('users').set({lifetime_purchased_at:new Date().toISOString()}).where('id','=',u.id).execute();
 expect((await get()).body.access).not.toBe(d.body.access);
});
it('streams initial catch-up and category mutation hints',async()=>{
 const u=await user(); const server=app.listen(0); servers.push(server);
 const port=(server.address() as any).port;
 const controller=new AbortController();
 const response=await fetch(`http://127.0.0.1:${port}/sync/events`,{headers:{Authorization:u.auth},signal:controller.signal});
 expect(response.headers.get('content-type')).toContain('text/event-stream');
 expect(response.headers.get('x-accel-buffering')).toBe('no');
 const reader=response.body!.getReader(), decoder=new TextDecoder();
 expect(decoder.decode((await reader.read()).value)).toContain('event: change');
 const made=await request(app).post('/message-categories').set('Authorization',u.auth).send({name:'notify category',color:'sky'});
 expect(made.status).toBe(201);
 const text=await Promise.race([reader.read().then(v=>decoder.decode(v.value)),new Promise<string>((_,reject)=>setTimeout(()=>reject(Error('missing change')),1500))]);
 expect(text).toContain('event: change'); expect(text).not.toContain('notify category');
 controller.abort();
});
it('does not deliver another account event',async()=>{
 const u=await user(),other=await user(); const server=app.listen(0); servers.push(server);
 const controller=new AbortController();
 const response=await fetch(`http://127.0.0.1:${(server.address() as any).port}/sync/events`,{headers:{Authorization:u.auth},signal:controller.signal});
 const reader=response.body!.getReader();await reader.read(); notifySync(other.id);
 const result=await Promise.race([reader.read().then(()=>true),new Promise<boolean>(r=>setTimeout(()=>r(false),350))]);
 expect(result).toBe(false);controller.abort();
});

it('bounds concurrent streams per account and removes revoked sessions on heartbeat',async()=>{
 const u=await user();const server=app.listen(0);servers.push(server);
 const url=`http://127.0.0.1:${(server.address() as any).port}/sync/events`;
 const controllers=Array.from({length:12},()=>new AbortController());
 const responses=await Promise.all(controllers.map(c=>fetch(url,{headers:{Authorization:u.auth},signal:c.signal})));
 expect(responses.every(r=>r.status===200)).toBe(true);
 expect((await fetch(url,{headers:{Authorization:u.auth}})).status).toBe(429);
 const reader=responses[0].body!.getReader();await reader.read();
 await db.deleteFrom('sessions').where('token','=',u.token).execute();
 const closed=await Promise.race([reader.read().then(v=>v.done),new Promise((_,reject)=>setTimeout(()=>reject(Error('revoked stream remained open')),27000))]);
 expect(closed).toBe(true);controllers.forEach(c=>c.abort());
},30000);
