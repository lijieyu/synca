import { expect, it } from 'vitest';
import SQLite from 'better-sqlite3';
import { Kysely, SqliteDialect, sql } from 'kysely';
import { nextMessageTimestamp } from '../src/messageRevision.js';

it('keeps every committed change beyond the account cursor despite delayed writes or clock rollback',async()=>{
 const sqlite=new SQLite(':memory:');
 sqlite.exec('CREATE TABLE messages(id TEXT PRIMARY KEY,user_id TEXT,updated_at TEXT); CREATE INDEX revisions ON messages(user_id,updated_at);');
 const db=new Kysely<any>({dialect:new SqliteDialect({database:sqlite})});
 const at='2026-11-24T12:00:10.000Z',past='2026-11-24T12:00:07.000Z';
 try{
  await db.insertInto('messages').values([{id:'seen',user_id:'a',updated_at:at},{id:'old',user_id:'a',updated_at:past},{id:'other',user_id:'b',updated_at:'2099-01-01T00:00:00.000Z'}]).execute();
  await db.updateTable('messages').set({updated_at:nextMessageTimestamp(past)}).where('id','=','old').execute();
  const changed=await db.selectFrom('messages').selectAll().where('user_id','=','a').where('updated_at','>',at).execute();
  expect(changed.map(row=>row.id)).toEqual(['old']);
  expect(changed[0].updated_at).toBe('2026-11-24T12:00:10.001Z');
  await db.insertInto('messages').values({id:'late',user_id:'a',updated_at:nextMessageTimestamp(past,'a')}).execute();
  const late=await db.selectFrom('messages').selectAll().where('id','=','late').executeTakeFirstOrThrow();
  expect(late.updated_at).toBe('2026-11-24T12:00:10.002Z');
  await db.updateTable('messages').set({updated_at:nextMessageTimestamp(past)}).where('user_id','=','a').execute();
  expect((await db.selectFrom('messages').selectAll().where('user_id','=','a').where('updated_at','>',late.updated_at).execute())).toHaveLength(3);
  await db.insertInto('messages').values({id:'first',user_id:'empty',updated_at:nextMessageTimestamp(past,'empty')}).execute();
  expect((await sql<any>`SELECT updated_at FROM messages WHERE id='first'`.execute(db)).rows[0].updated_at).toBe(past);
 }finally{await db.destroy();}
});
