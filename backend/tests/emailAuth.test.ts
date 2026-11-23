import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { sql } from 'kysely';
vi.hoisted(() => { vi.stubEnv('SYNCA_EMAIL_AUTH_ENABLED', 'true'); });
afterAll(() => vi.unstubAllEnvs());
vi.mock('../src/emailDelivery.js', () => ({ isEmailDeliveryConfigured: vi.fn(() => true), sendVerificationEmail: vi.fn(async () => {}) }));
vi.mock('apple-signin-auth', () => ({ verifyIdToken: vi.fn() }));
import app from '../src/app.js';
import { db } from '../src/db.js';
import { resetDb, createUser, createSession } from '../src/store.js';
import { runMigrations } from '../src/migrate.js';
import { isEmailDeliveryConfigured, sendVerificationEmail } from '../src/emailDelivery.js';
import { verifyIdToken } from 'apple-signin-auth';
const delivery = vi.mocked(sendVerificationEmail);
const apple = vi.mocked(verifyIdToken);
async function account(appleUserId: string | null = randomUUID(), email='profile@example.com') {
 const id=randomUUID(),token=randomUUID(); await createUser({id,appleUserId,email,nickname:'Existing',now:new Date().toISOString()});await createSession(token,id);return {id,token};
}
async function send(email='new@example.com', token?: string) {
 const r=await request(app).post(token?'/me/login-methods/email/code':'/auth/email/code').set('Authorization',token?`Bearer ${token}`:'').send({email});
 expect(r.status).toBe(200);const code=delivery.mock.calls.at(-1)![0].code;return {id:r.body.challengeId,code,res:r};
}
async function verify(proof:{id:string,code:string},token?:string) {return request(app).post(token?'/me/login-methods/email/verify':'/auth/email/verify').set('Authorization',token?`Bearer ${token}`:'').send({challengeId:proof.id,code:proof.code});}
describe('email login and settings identities',()=>{
 beforeAll(async()=>{process.env.EMAIL_AUTH_SECRET='test-secret-only-012345678901234567890123456789';await runMigrations();});
 beforeEach(async()=>{await resetDb();vi.clearAllMocks();delivery.mockResolvedValue();});
 it('advertises email only with both signing and delivery configuration', async () => {
  expect((await request(app).get('/auth/capabilities')).body).toEqual({email:false});
  expect((await request(app).get('/auth/capabilities').set('X-Synca-Client','desktop')).body).toEqual({email:true});
  const saved = process.env.EMAIL_AUTH_SECRET;
  try {
   process.env.EMAIL_AUTH_SECRET = 'too-short';
   expect((await request(app).get('/auth/capabilities').set('X-Synca-Client','desktop')).body).toEqual({email:false});
  } finally { process.env.EMAIL_AUTH_SECRET = saved; }
  vi.mocked(isEmailDeliveryConfigured).mockReturnValueOnce(false);
  expect((await request(app).get('/auth/capabilities').set('X-Synca-Client','desktop')).body).toEqual({email:false});
 });
 it('creates on first verified login, preserves identity on repeat, never elevates email to admin',async()=>{
  const a=await verify(await send('Jieyu.Li@icloud.com'));expect(a.status).toBe(200);expect(a.body.user.isAdmin).toBe(false);expect(a.body.user.appleUserId).toBeNull();
  await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);await sql`DELETE FROM auth_rate_limits`.execute(db);
  const b=await verify(await send('jieyu.li@icloud.com'));expect(b.body.user.id).toBe(a.body.user.id);await runMigrations();expect((await db.selectFrom('users').select('is_admin').where('id','=',a.body.user.id).executeTakeFirst())?.is_admin).toBe(0);
 });
 it('does not treat unverified profile email as a login identity',async()=>{
  const old=await account('old-apple','same@example.com');const login=await verify(await send('same@example.com'));expect(login.body.user.id).not.toBe(old.id);
 });
 it('binds email to Apple account and both methods preserve records, plan and UUID',async()=>{
  const old=await account('old-apple');await db.updateTable('users').set({lifetime_purchased_at:new Date().toISOString()}).where('id','=',old.id).execute();
  await request(app).post('/messages').set('Authorization',`Bearer ${old.token}`).send({textContent:'keep me'}).expect(201);
  const bound=await verify(await send('linked@example.com',old.token),old.token);expect(bound.status).toBe(200);expect(bound.body).toEqual({apple:true,email:'linked@example.com'});
  await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);await sql`DELETE FROM auth_rate_limits`.execute(db);
  const login=await verify(await send('linked@example.com'));expect(login.body.user.id).toBe(old.id);expect(login.body.accessStatus.isUnlimited).toBe(true);
  const records=await request(app).get('/messages').set('Authorization',`Bearer ${login.body.token}`);expect(records.body.messages[0].textContent).toBe('keep me');
  apple.mockResolvedValue({sub:'old-apple',email:'relay@privaterelay.appleid.com'} as never);
  const again=await request(app).post('/auth/apple').send({idToken:'verified'});expect(again.body.user.id).toBe(old.id);expect(again.body.user.email).toBe('linked@example.com');
 });
 it('binds Apple to email account using one-time nonce, then Apple logs into same UUID',async()=>{
  const a=await verify(await send());const token=a.body.token;
  const challenge=await request(app).post('/me/login-methods/apple/challenge').set('Authorization',`Bearer ${token}`).send({});expect(challenge.status).toBe(200);
  apple.mockResolvedValue({sub:'new-apple',nonce:challenge.body.nonce,email:'different@icloud.com'} as never);
  const bind=()=>request(app).post('/me/login-methods/apple').set('Authorization',`Bearer ${token}`).send({challengeId:challenge.body.challengeId,idToken:'valid'});
  expect((await bind()).body).toEqual({apple:true,email:'new@example.com'});expect((await bind()).status).toBe(400);
  const login=await request(app).post('/auth/apple').send({idToken:'valid'});expect(login.body.user.id).toBe(a.body.user.id);
 });
 it('rejects binding conflicts without merging',async()=>{
  const a=await verify(await send());const b=await account('occupied');await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);await sql`DELETE FROM auth_rate_limits`.execute(db);
  const result=await verify(await send('new@example.com',b.token),b.token);expect(result.status).toBe(409);expect(result.body.error).toBe('email_in_use');
  const c=await request(app).post('/me/login-methods/apple/challenge').set('Authorization',`Bearer ${a.body.token}`).send({});apple.mockResolvedValue({sub:'occupied',nonce:c.body.nonce} as never);
  const r=await request(app).post('/me/login-methods/apple').set('Authorization',`Bearer ${a.body.token}`).send({idToken:'valid',challengeId:c.body.challengeId});expect(r.status).toBe(409);expect(r.body.error).toBe('apple_in_use');
 });
 it('rejects wrong purpose, other session, missing auth and wrong Apple nonce',async()=>{
  const a=await account();const b=await account();const p=await send('bind@example.com',a.token);
  expect((await verify(p)).status).toBe(400);expect((await verify(p,b.token)).status).toBe(400);expect((await verify(p,a.token)).status).toBe(200);
  await request(app).get('/me/login-methods').expect(401);
  const c=await request(app).post('/me/login-methods/apple/challenge').set('Authorization',`Bearer ${b.token}`).send({});apple.mockResolvedValue({sub:'a-different-apple',nonce:'wrong'} as never);
  expect((await request(app).post('/me/login-methods/apple').set('Authorization',`Bearer ${b.token}`).send({idToken:'valid',challengeId:c.body.challengeId})).status).toBe(400);
 });
 it('consumes proofs once even under overlapping verification',async()=>{
  const p=await send();const results=await Promise.all([verify(p),verify(p)]);expect(results.map(r=>r.status).sort()).toEqual([200,400]);expect((await db.selectFrom('users').selectAll().execute()).length).toBe(1);
 });
 it('enforces five attempts, expiry and cooldown without issuing a session',async()=>{
  const p=await send();expect((await request(app).post('/auth/email/code').send({email:'NEW@example.com'})).status).toBe(429);
  for(let i=0;i<5;i++)expect((await verify({...p,code:p.code==='000000'?'000001':'000000'})).status).toBe(400);
  expect((await verify(p)).body.error).toBe('code_attempts_exceeded');
  const expired=await send('expired@example.com');await sql`UPDATE email_auth_challenges SET expires_at=0 WHERE id=${expired.id}`.execute(db);expect((await verify(expired)).body.error).toBe('code_expired');expect((await db.selectFrom('sessions').selectAll().execute()).length).toBe(0);
 });
 it('resend invalidates old proof, provider failure preserves old proof and reports failure',async()=>{
  const p=await send();await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);const newer=await send();expect((await verify(p)).status).toBe(400);
  await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);delivery.mockRejectedValueOnce(new Error('private provider payload'));
  const failed=await request(app).post('/auth/email/code').send({email:'new@example.com'});expect(failed.status).toBe(503);expect(failed.text).not.toContain('private');expect((await verify(newer)).status).toBe(200);
 });
 it('does not overwrite a newly bound profile email when Apple sign-in was already in flight',async()=>{
  const a=await account('racing-apple');const proof=await send('winning@example.com',a.token);
  apple.mockResolvedValue({sub:'racing-apple',email:'old-relay@privaterelay.appleid.com'} as never);
  const prototype=Object.getPrototypeOf(db.getExecutor());const original=prototype.executeQuery;let interleaved=false;
  const spy=vi.spyOn(prototype,'executeQuery').mockImplementation(async function(this:unknown,query:any,...args:any[]){
   if(!interleaved && /update "?users"? set "?email"?/i.test(query.sql) && query.parameters.includes('old-relay@privaterelay.appleid.com')){
    interleaved=true;expect((await verify(proof,a.token)).status).toBe(200);
   }
   return original.call(this,query,...args);
  });
  try{const login=await request(app).post('/auth/apple').send({idToken:'valid'});expect(login.status).toBe(200);expect(interleaved).toBe(true);expect(login.body.user.email).toBe('winning@example.com');}
  finally{spy.mockRestore();}
 });
 it('reuses a session binding challenge and does not make unrelated users share its quota',async()=>{
  const a=await account(null);const endpoint='/me/login-methods/apple/challenge';
  const one=await request(app).post(endpoint).set('Authorization',`Bearer ${a.token}`).send({});
  const two=await request(app).post(endpoint).set('Authorization',`Bearer ${a.token}`).send({});
  expect(two.body.challengeId).toBe(one.body.challengeId);expect(Date.parse(two.body.expiresAt)).toBeGreaterThan(Date.now());
  for(let i=0;i<32;i++){const other=await account(null);await request(app).post(endpoint).set('Authorization',`Bearer ${other.token}`).send({}).expect(200);}
 });
 it('deletes identities and binding challenges with account',async()=>{
  const login=await verify(await send());await request(app).post('/me/login-methods/apple/challenge').set('Authorization',`Bearer ${login.body.token}`).send({});
  await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);
  const pendingLogin=await send();
  await request(app).delete('/me/account').set('Authorization',`Bearer ${login.body.token}`).expect(200);
  expect((await sql`SELECT * FROM email_identities`.execute(db)).rows).toHaveLength(0);expect((await sql`SELECT * FROM apple_binding_challenges`.execute(db)).rows).toHaveLength(0);
  expect((await sql`SELECT * FROM email_auth_challenges`.execute(db)).rows).toHaveLength(0);
  expect((await verify(pendingLogin)).status).toBe(400);
 });
});
