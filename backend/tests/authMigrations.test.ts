import { it, expect } from 'vitest';
import SQLite from 'better-sqlite3';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
it('migrates populated legacy users without losing child references, indexes or privileges; rerun is idempotent',()=>{
 const directory=mkdtempSync(path.join(tmpdir(),'synca-legacy-auth-')),file=path.join(directory,'db.sqlite');
 try{
  const old=new SQLite(file);old.exec(`PRAGMA foreign_keys=ON;
   CREATE TABLE users(id TEXT PRIMARY KEY,apple_user_id TEXT UNIQUE NOT NULL,email TEXT,nickname TEXT NOT NULL DEFAULT 'Synca 用户',trial_started_at TEXT,trial_ends_at TEXT,purchase_date TEXT,subscription_expires_at TEXT,lifetime_purchased_at TEXT,store_product_id TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,is_admin INTEGER DEFAULT 0,timezone_offset_seconds INTEGER DEFAULT 28800);
   INSERT INTO users(id,apple_user_id,email,nickname,lifetime_purchased_at,is_admin,created_at,updated_at) VALUES('legacy','apple-id','old@example.com','Existing','2020-01-01',1,'2020-01-01','2020-01-01');
   CREATE TABLE preserved_reference(id TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id));
   INSERT INTO preserved_reference VALUES('child','legacy');
   CREATE INDEX custom_users_nickname ON users(nickname);`);
  const before=old.prepare('SELECT * FROM users').get();old.close();
  for(let i=0;i<2;i++)execFileSync(process.execPath,['--import','tsx','src/migrate.ts'],{cwd:process.cwd(),env:{...process.env,DB_PATH:file},stdio:'pipe'});
  const current=new SQLite(file);expect(current.prepare('SELECT * FROM users').get()).toEqual(before);expect(current.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
  expect(current.prepare("SELECT name FROM sqlite_master WHERE name='custom_users_nickname'").get()).toBeTruthy();expect(current.prepare('SELECT * FROM preserved_reference').all()).toEqual([{id:'child',user_id:'legacy'}]);
  expect(current.prepare('PRAGMA table_info(users)').all().find((r:any)=>r.name==='apple_user_id')).toMatchObject({notnull:0});
  current.prepare("INSERT INTO users(id,apple_user_id,nickname,created_at,updated_at) VALUES('email-only',NULL,'Email','2020-01-01','2020-01-01')").run();current.close();
 }finally{rmSync(directory,{recursive:true,force:true});}
});
