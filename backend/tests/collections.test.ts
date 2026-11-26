import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import app from '../src/app.js';
import { connection, authenticate, createText, searchMessages, updateMessages, prepareDelete, mutationSchema } from '../src/aiCore.js';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb, createSession, purgeMessageMedia, deleteMessage, updateMessageCategoryAssignment, updateMessageText } from '../src/store.js';

let token: string, userId: string;
const modern = (req: request.Test) => req.set('Authorization', `Bearer ${token}`).set('X-Synca-Features', 'collections');
const legacy = (req: request.Test) => req.set('Authorization', `Bearer ${token}`);
beforeAll(async () => { await runMigrations(); });
beforeEach(async () => {
 await resetDb(); userId=randomUUID();token=randomUUID();const now=new Date().toISOString();
 await db.insertInto('users').values({id:userId,apple_user_id:randomUUID(),email:'fixture@example.com',nickname:'Fixture',created_at:now,updated_at:now} as any).execute();
 await createSession(token,userId);
});
async function record(isCollected=false) {
 const res=await modern(request(app).post('/messages')).send({textContent:'Account notes',isCollected});
 expect(res.status).toBe(201);return res.body;
}
async function collect(message:any) {
 return modern(request(app).patch(`/messages/${message.id}/collect`)).send({expectedUpdatedAt:message.updatedAt});
}
describe('collections',()=>{
 it('moves a record out of legacy tasks and preserves an incremental removal event',async()=>{
  const m=await record();const res=await collect(m);expect(res.status).toBe(200);expect(res.body.collectedAt).toBeTruthy();expect(res.body.isCleared).toBe(false);
  expect((await legacy(request(app).get('/messages'))).body.messages).toHaveLength(0);
  const delta=await legacy(request(app).get('/messages').query({since:m.updatedAt}));
  expect(delta.body.messages).toHaveLength(1);expect(delta.body.messages[0]).toMatchObject({id:m.id,isDeleted:true});expect(delta.body.messages[0].textContent).toBeUndefined();
  expect((await modern(request(app).get('/messages'))).body.messages[0].collectedAt).toBeTruthy();
  expect((await legacy(request(app).get('/messages/uncleared-count'))).body.count).toBe(0);
 });
 it('creates a collection directly without entering task bulk operations',async()=>{
  const m=await record(true);expect(m.collectedAt).toBeTruthy();
  await legacy(request(app).post('/messages/clear-all')).send({});
  await legacy(request(app).post('/messages/delete-completed')).send({});
  const rows=(await modern(request(app).get('/messages'))).body.messages;
  expect(rows).toHaveLength(1);expect(rows[0].isCleared).toBe(false);
 });
 it('prevents stale legacy clients from modifying or deleting a collection',async()=>{
  const m=await record(true);
  for(const req of [request(app).delete(`/messages/${m.id}`),request(app).patch(`/messages/${m.id}/text`).send({textContent:'stale',expectedUpdatedAt:m.updatedAt}),request(app).patch(`/messages/${m.id}/category`).send({categoryId:null})]) {
   expect((await legacy(req)).status).toBe(409);
  }
  expect((await modern(request(app).patch(`/messages/${m.id}/completion`)).send({isCleared:true})).status).toBe(409);
 });
 it('checks owner and version, and supports retrying the original collect request',async()=>{
  const m=await record();expect((await modern(request(app).patch(`/messages/${m.id}/collect`)).send({expectedUpdatedAt:'2000-01-01T00:00:00.000Z'})).status).toBe(409);
  const first=await collect(m);expect(first.status).toBe(200);const retry=await collect(m);expect(retry.status).toBe(200);expect(retry.body.updatedAt).toBe(first.body.updatedAt);
  const other=randomUUID();const now=new Date().toISOString();await db.insertInto('users').values({id:other,apple_user_id:randomUUID(),nickname:'Other',created_at:now,updated_at:now} as any).execute();await db.updateTable('messages').set({user_id:other}).where('id','=',m.id).execute();
  expect((await collect(m)).status).toBe(404);
 });
 it('refuses expired or purged attachments',async()=>{
  const m=await record();await db.updateTable('messages').set({type:'image',image_path:'fixture.png',attachment_expires_at:'2000-01-01T00:00:00.000Z'}).where('id','=',m.id).execute();
  expect((await collect(m)).status).toBe(410);
 });
});

 it('keeps a collected file when a sweeper holds a stale pre-collection row',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'synca-collect-race-'));
  try {
   const m=await record();await writeFile(path.join(root,'fixture.png'),'preserve');
   await db.updateTable('messages').set({type:'image',image_path:'fixture.png',attachment_expires_at:'2099-01-01T00:00:00.000Z'}).where('id','=',m.id).execute();
   const stale=await db.selectFrom('messages').selectAll().where('id','=',m.id).executeTakeFirstOrThrow();
   expect((await collect(m)).status).toBe(200);
   await purgeMessageMedia(stale,root,root,'2100-01-01T00:00:00.000Z');
   expect(await readFile(path.join(root,'fixture.png'),'utf8')).toBe('preserve');
   expect((await db.selectFrom('messages').selectAll().where('id','=',m.id).executeTakeFirstOrThrow()).attachment_purged).toBe(0);
  } finally {await rm(root,{recursive:true,force:true});}
 });
 it('refuses a file already claimed by the cleanup worker',async()=>{
  const m=await record();await db.updateTable('messages').set({type:'image',image_path:'fixture.png',attachment_purged:2}).where('id','=',m.id).execute();
  expect((await collect(m)).status).toBe(410);
 });
 it('supports MCP collections without completion actions or completed-only deletion',async()=>{
  await db.updateTable('users').set({lifetime_purchased_at:new Date().toISOString()}).where('id','=',userId).execute();
  const conn=await connection(userId,'fixture',['read','create','update','delete'],1);
  const actor=await authenticate('Bearer '+conn.token);
  const result=await createText(actor,{textContent:'Saved account',idempotencyKey:randomUUID(),isCollected:true} as any);
  const page=await searchMessages(actor,{isCollected:true,limit:30} as any);expect(page.messages).toHaveLength(1);
  expect(page.messages[0].collectedAt).toBeTruthy();
  await expect(updateMessages(actor,{items:[{id:result.id,expectedUpdatedAt:page.messages[0].updatedAt}],isCleared:true})).rejects.toMatchObject({code:'collection_not_task'});
  await expect(prepareDelete(actor,{completedOnly:true})).rejects.toMatchObject({code:'no_matching_records'});
  expect(mutationSchema.safeParse({items:[{id:result.id,expectedUpdatedAt:page.messages[0].updatedAt}],isCollected:false}).success).toBe(false);
 });

it('enforces legacy protection in conditional writes after the HTTP guard', async () => {
 const m = await record(true);
 expect(await deleteMessage(m.id, userId, 'uploads', 'files')).toBe(false);
 expect(await updateMessageCategoryAssignment({id:m.id,userId,categoryId:null,now:new Date().toISOString()})).toBeUndefined();
 expect(await updateMessageText({id:m.id,userId,textContent:'legacy',expectedUpdatedAt:m.updatedAt})).toHaveProperty('error');
 const edited=await modern(request(app).patch(`/messages/${m.id}/text`)).send({textContent:'updated collection',expectedUpdatedAt:m.updatedAt});
 expect(edited.status).toBe(200);expect(edited.body.collectedAt).toBeTruthy();
 expect((await modern(request(app).delete(`/messages/${m.id}`))).status).toBe(200);
});
