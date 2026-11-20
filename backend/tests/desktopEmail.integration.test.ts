import { beforeAll, afterAll, expect, it, vi } from 'vitest';
import express from 'express';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { sql } from 'kysely';
import fs from 'node:fs/promises';
vi.mock('../src/emailDelivery.js',()=>({isEmailDeliveryConfigured:()=>true,sendVerificationEmail:vi.fn(async()=>{})}));
vi.mock('apple-signin-auth',()=>({verifyIdToken:vi.fn(async(token:string)=>JSON.parse(token))}));
import app from '../src/app.js';
import { db } from '../src/db.js';
import { runMigrations } from '../src/migrate.js';
import { resetDb,createUser } from '../src/store.js';
import { sendVerificationEmail } from '../src/emailDelivery.js';
// Opt in: this integration drives a built Web bundle and requires local Chrome.
const enabled=process.env.SYNCA_BROWSER_TEST==='1';
let server:ReturnType<typeof app.listen>,origin:string,browser:any;
const clients:any[]=[];
beforeAll(async()=>{
 if(!enabled)return;
 process.env.EMAIL_AUTH_SECRET='isolated-browser-test-secret-01234567890123456789';
 await runMigrations();await resetDb();
 const web=path.resolve('../web/dist');server=express().use(app).use(express.static(web)).get('*',(_req,res)=>res.sendFile(path.join(web,'index.html'))).listen(0,'127.0.0.1');
 await new Promise<void>(r=>server.once('listening',r));origin=`http://127.0.0.1:${(server.address() as any).port}`;
 const {chromium}=await import('../../desktop/node_modules/playwright-core/index.mjs');
 browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
});
afterAll(async()=>{if(!enabled)return;for(const c of clients)await c.close();await browser?.close();await new Promise<void>(r=>server.close(()=>r()));});
async function pageFor(subject:string){
 const context=await browser.newContext({viewport:{width:640,height:500}});clients.push(context);
 await context.addInitScript((subject:string)=>{localStorage.setItem('synca.language','zh-Hans');let options:any;(window as any).AppleID={auth:{init(o:any){options=o},async signIn(){return {authorization:{state:options.state,id_token:JSON.stringify({sub:subject,nonce:options.nonce})}}}}};},subject);
 await context.route('**/*',async(r:any)=>new URL(r.request().url()).origin===origin?r.continue():r.abort());
 const page=await context.newPage();page.setDefaultTimeout(8000);await page.goto(origin);return page;
}
async function emailLogin(page:any,email:string){
 await page.getByRole('button',{name:'使用邮箱登录',exact:true}).click();await page.getByLabel('邮箱地址').fill(email);await page.getByRole('button',{name:'发送验证码',exact:true}).click();await page.getByLabel('6 位验证码').waitFor();
 const code=vi.mocked(sendVerificationEmail).mock.calls.at(-1)![0].code;
 await page.getByLabel('6 位验证码').fill(code);await page.getByRole('button',{name:'登录',exact:true}).click();await page.locator('.settings-entry').waitFor();return await page.evaluate(()=>localStorage.getItem('authToken'));
}
async function settings(page:any){await page.locator('.settings-entry').click();await page.locator('.desk-settings nav').getByRole('button',{name:/账号与套餐/}).click();await page.getByRole('heading',{name:'登录方式',exact:true}).waitFor();}
it.skipIf(!enabled)('built desktop UI uses real API/database across email signup, Apple binding, second-device sync and Apple->email binding',async()=>{
 const first=await pageFor('new-apple');const token=await emailLogin(first,'real-path@example.com');
 const firstUser=await db.selectFrom('sessions').select('user_id').where('token','=',token).executeTakeFirstOrThrow();
 const created=await first.request.post(origin+'/messages',{headers:{Authorization:`Bearer ${token}`},data:{textContent:'Email identity sync verification'}});expect(created.status()).toBe(201);
 await settings(first);await first.locator('.login-method-rows').getByRole('button',{name:'绑定',exact:true}).click();await first.getByRole('status').filter({hasText:'登录方式已绑定'}).waitFor();
 expect((await db.selectFrom('users').select('apple_user_id').where('id','=',firstUser.user_id).executeTakeFirstOrThrow()).apple_user_id).toBe('new-apple');
 const appleAgain=await first.request.post(origin+'/auth/apple',{data:{idToken:JSON.stringify({sub:'new-apple'})}});expect((await appleAgain.json()).user.id).toBe(firstUser.user_id);
 await sql`UPDATE email_auth_challenges SET resend_at=0`.execute(db);
 const second=await pageFor('unused');const secondToken=await emailLogin(second,'real-path@example.com');expect(secondToken).not.toBe(token);
 await second.getByText('Email identity sync verification',{exact:true}).waitFor();expect((await db.selectFrom('sessions').select('user_id').where('token','=',secondToken).executeTakeFirstOrThrow()).user_id).toBe(firstUser.user_id);
 const legacyId=randomUUID();await createUser({id:legacyId,appleUserId:'legacy-native-apple',nickname:'Original',email:'relay@privaterelay.appleid.com',now:new Date().toISOString()});
 await db.updateTable('users').set({lifetime_purchased_at:new Date().toISOString()}).where('id','=',legacyId).execute();
 const third=await pageFor('legacy-native-apple');await third.getByRole('button',{name:'通过 Apple 登录',exact:true}).click();await third.locator('.settings-entry').waitFor();await settings(third);
 await third.locator('.login-method-rows').getByRole('button',{name:'绑定',exact:true}).click();await third.getByLabel('邮箱地址').fill('native-linked@example.com');await third.getByRole('button',{name:'发送验证码',exact:true}).click();await third.getByLabel('6 位验证码').waitFor();
 const before=await third.locator('.email-verification h1,.email-verification input,.email-verification form button').evaluateAll((nodes:any[])=>nodes.map(n=>n.getBoundingClientRect().y));await third.getByText('没有收到邮件？',{exact:true}).click();
 expect(await third.locator('.email-verification h1,.email-verification input,.email-verification form button').evaluateAll((nodes:any[])=>nodes.map(n=>n.getBoundingClientRect().y))).toEqual(before);
 await third.getByLabel('6 位验证码').fill(vi.mocked(sendVerificationEmail).mock.calls.at(-1)![0].code);await third.getByRole('button',{name:'验证并绑定',exact:true}).click();await third.locator('.account-email').filter({hasText:'native-linked@example.com'}).waitFor();
 const identity=(await sql<{user_id:string}>`SELECT user_id FROM email_identities WHERE email='native-linked@example.com'`.execute(db)).rows[0];expect(identity.user_id).toBe(legacyId);
 const output='/tmp/synca-email-real-api';await fs.mkdir(output,{recursive:true});await third.screenshot({path:output+'/settings-bound.png'});await second.screenshot({path:output+'/second-device-record.png'});
},60_000);
it.skipIf(!enabled || !process.env.SYNCA_ELECTRON_BINARY)('packaged Electron uses shared email login and stable help with a real isolated backend',async()=>{
 const { _electron: electron }=await import('../../desktop/node_modules/playwright-core/index.mjs');
 const profile=await fs.mkdtemp('/tmp/synca-electron-email-profile-');
 const desktop=await electron.launch({executablePath:process.env.SYNCA_ELECTRON_BINARY!,args:['--user-data-dir='+profile]});
 try{
  const page=await desktop.firstWindow();page.setDefaultTimeout(10000);
  await desktop.evaluate(({session}:any,local:string)=>{
   const ses=session.defaultSession,original=ses.fetch.bind(ses);
   ses.fetch=(input:any,options:any)=>{
    const url=new URL(typeof input==='string'?input:input.url);
    if(url.origin==='https://synca.haerth.cn' && /^\/(auth|me|messages|message-categories)(\/|$)/.test(url.pathname)){
     const init=typeof input==='string'?options:{method:input.method,headers:input.headers,body:['GET','HEAD'].includes(input.method)?undefined:input.body,duplex:'half'};
     return original(local+url.pathname+url.search,init);
    }
    return original(input,options);
   };
  },origin);
  await page.context().route('**/*',async(route:any)=>{
   const url=new URL(route.request().url());
   if(url.origin!=='https://synca.haerth.cn')return route.abort();
   if(/^\/(auth|me|messages|message-categories)(\/|$)/.test(url.pathname))return route.fulfill({response:await route.fetch({url:origin+url.pathname+url.search,maxRedirects:0})});
   return route.continue();
  });
  await page.reload();await page.locator('.auth-primary.auth-apple').waitFor();
  await page.waitForFunction(()=>Array.from(document.querySelectorAll<HTMLImageElement>('.auth-apple-logo')).every(image=>image.complete && image.naturalWidth>0));
  await desktop.evaluate(({BrowserWindow}:any)=>BrowserWindow.getAllWindows()[0].setSize(640,500));
  await page.waitForFunction(()=>document.documentElement.scrollHeight<=window.innerHeight);
  await page.getByRole('button',{name:/使用邮箱登录|Sign in with email/,exact:true}).click();await page.locator('input[type=email]').fill('electron@example.com');await page.locator('.email-verification form button').click();await page.locator('input.auth-code').waitFor();
  const controls=page.locator('.email-verification h1,.email-verification input,.email-verification form button');const before=await controls.evaluateAll((nodes:any[])=>nodes.map(n=>n.getBoundingClientRect().y));
  await page.locator('.auth-help summary').click();expect(await controls.evaluateAll((nodes:any[])=>nodes.map(n=>n.getBoundingClientRect().y))).toEqual(before);
  await fs.mkdir('/tmp/synca-email-real-api',{recursive:true});await page.screenshot({path:'/tmp/synca-email-real-api/electron-help.png'});
  await page.locator('input.auth-code').fill(vi.mocked(sendVerificationEmail).mock.calls.at(-1)![0].code);await page.locator('.email-verification form button').click();await page.locator('.settings-entry').waitFor();
  const token=await page.evaluate(()=>localStorage.getItem('authToken'));expect(await db.selectFrom('sessions').select('user_id').where('token','=',token!).executeTakeFirst()).toBeTruthy();
 }finally{await desktop.close();await fs.rm(profile,{recursive:true,force:true});}
},60_000);
