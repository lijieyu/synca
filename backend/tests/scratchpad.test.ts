import fs from 'node:fs/promises';
import {cleanupExpiredAttachments} from '../src/storage.js';
import {beforeAll,beforeEach,it,expect,vi} from 'vitest';
import request from 'supertest';
import {randomUUID} from 'node:crypto';
import app from '../src/app.js';
import {db} from '../src/db.js';
import {runMigrations} from '../src/migrate.js';
import {resetDb,createSession} from '../src/store.js';
let token:string,userId:string;
const auth=(r:request.Test)=>r.set('Authorization',`Bearer ${token}`);
const save=(content:string,expectedRevision:number,mutationId=randomUUID())=>auth(request(app).put('/scratchpad')).send({content,expectedRevision,mutationId});
beforeAll(runMigrations);
beforeEach(async()=>{await resetDb();userId=randomUUID();token=randomUUID();const now=new Date().toISOString();await db.insertInto('users').values({id:userId,apple_user_id:randomUUID(),nickname:'Scratch fixture',created_at:now,updated_at:now}).execute();await createSession(token,userId);});
it('shares one revisioned page and preserves concurrent edits as recoverable copies',async()=>{
 expect((await auth(request(app).get('/scratchpad'))).body).toMatchObject({content:'',revision:0});
 const id=randomUUID();const first=await save('# Notes',0,id);expect(first.status).toBe(200);expect(first.body.revision).toBe(1);
 expect((await save('# Notes',0,id)).body.revision).toBe(1);
 const conflict=await save('Offline writing',0);expect(conflict.status).toBe(409);expect(conflict.body.current.content).toBe('# Notes');
 const copies=await auth(request(app).get('/scratchpad/conflicts'));expect(copies.body.conflicts).toHaveLength(1);expect(copies.body.conflicts[0].content).toBe('Offline writing');
 expect((await save('Combined writing',1)).body.revision).toBe(2);
 expect((await request(app).get('/scratchpad')).status).toBe(401);
});
it('validates image references and keeps document saves out of record quota',async()=>{
 expect((await save(`![image](synca-image:${randomUUID()})`,0)).status).toBe(422);
 expect((await save('a'.repeat(250001),0)).status).toBe(400);
 expect((await save('Valid text',0)).status).toBe(200);
 expect(await db.selectFrom('message_usage_events').selectAll().execute()).toHaveLength(0);
});
it('stores images outside tasks/collections and prevents deleting referenced images',async()=>{
 const upload=await auth(request(app).post('/scratchpad/images')).set('X-Upload-Size','4').attach('image',Buffer.from('test'),'note.png');
 expect(upload.status).toBe(201);const id=upload.body.id;
 expect((await auth(request(app).delete(`/messages/${id}`)).set('X-Synca-Features','collections')).status).toBe(409);
 expect((await auth(request(app).get('/messages')).set('X-Synca-Features','collections')).body.messages).toHaveLength(0);
 expect((await save(`![image](synca-image:${id})`,0)).status).toBe(200);
 expect((await auth(request(app).delete(`/scratchpad/images/${id}`))).status).toBe(409);
 expect((await save('',1)).status).toBe(200);
 expect((await auth(request(app).delete(`/scratchpad/images/${id}`))).status).toBe(200);
});
it('preserves the cloud version when resolving and isolates other accounts',async()=>{
 await save('Cloud original',0);
 const resolved=await auth(request(app).put('/scratchpad')).send({content:'Continue local',expectedRevision:1,mutationId:randomUUID(),preserveCurrent:true});
 expect(resolved.status).toBe(200);
 const copies=(await auth(request(app).get('/scratchpad/conflicts'))).body.conflicts;
 expect(copies.map((copy:any)=>copy.content)).toContain('Cloud original');
 const firstToken=token;const other=randomUUID();const now=new Date().toISOString();token=randomUUID();
 await db.insertInto('users').values({id:other,apple_user_id:randomUUID(),nickname:'Other',created_at:now,updated_at:now}).execute();await createSession(token,other);
 expect((await auth(request(app).get('/scratchpad'))).body.content).toBe('');
 expect((await auth(request(app).get('/scratchpad/conflicts'))).body.conflicts).toHaveLength(0);
 await auth(request(app).delete(`/scratchpad/conflicts/${copies[0].id}`));
 token=firstToken;expect((await auth(request(app).get('/scratchpad/conflicts'))).body.conflicts).toHaveLength(1);
});
it('keeps the latest cloud page unchanged when preserving local text for cloud resolution',async()=>{
 await save('First cloud',0);await save('Newer third-device edit',1);
 const copy=await auth(request(app).post('/scratchpad/conflicts')).send({content:'My offline writing',mutationId:randomUUID()});
 expect(copy.status).toBe(200);expect(copy.body.content).toBe('Newer third-device edit');expect(copy.body.revision).toBe(2);
 expect((await auth(request(app).get('/scratchpad'))).body.content).toBe('Newer third-device edit');
 expect((await auth(request(app).get('/scratchpad/conflicts'))).body.conflicts.map((c:any)=>c.content)).toContain('My offline writing');
});
it('rejects scratchpad writes intended for an account different from the active token',async()=>{
 const response=await auth(request(app).put('/scratchpad')).set('X-Synca-Account',randomUUID()).send({content:'Wrong account draft',expectedRevision:0,mutationId:randomUUID()});
 expect(response.status).toBe(409);expect((await auth(request(app).get('/scratchpad'))).body.content).toBe('');
});

it('retries scratchpad image deletion after a transient disk failure',async()=>{
 const upload=await auth(request(app).post('/scratchpad/images')).set('X-Upload-Size','4').attach('image',Buffer.from('test'),'retry.png');
 expect(upload.status).toBe(201);const id=upload.body.id;
 const unlink=vi.spyOn(fs,'unlink').mockRejectedValueOnce(Object.assign(new Error('busy'),{code:'EBUSY'}));
 try{expect((await auth(request(app).delete(`/scratchpad/images/${id}`))).status).toBe(200);}finally{unlink.mockRestore();}
 const queued=await db.selectFrom('messages').selectAll().where('id','=',id).executeTakeFirstOrThrow();
 expect(queued.attachment_expires_at).not.toBeNull();expect(queued.attachment_purged).toBe(2);
 await cleanupExpiredAttachments();
 expect((await db.selectFrom('messages').selectAll().where('id','=',id).executeTakeFirstOrThrow()).attachment_purged).toBe(1);
});
