// Run with a local Vite server on port 5178; all authentication and external traffic is intercepted.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || '/Users/haer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core/index.mjs');
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
const out = '/tmp/synca-email-ui-evidence'; await fs.mkdir(out, { recursive: true });
try {
for (const theme of ['light','dark']) {
 const context = await browser.newContext({ viewport: { width: 640, height: 500 }, colorScheme: theme });
 await context.addInitScript(theme => { window.syncaDesktop = { emailAuth:true, platform:'macOS', version:'1.2.0', subscribe:()=>()=>{}, session:()=>{}, count:()=>{}, preferences:async()=>({badge:true,ask:true,directory:''}), change:async()=>({badge:true,ask:true,directory:''}), directory:async()=>({badge:true,ask:true,directory:''}) }; localStorage.setItem('synca.language','zh-Hans'); localStorage.setItem('synca.appearance',theme); let options; window.AppleID = { auth: { init(value) { options = value; }, async signIn() { if(window.cancelApple) throw { error:'popup_closed_by_user' }; return { authorization: { id_token:'test-token', state:options.state } }; } } }; }, theme);
 let verifies = 0; let codeSends = 0; let methods = { apple: false, email: 'test@example.com' };
 await context.route('**/*', async route => {
  const url = new URL(route.request().url()); if (url.origin !== 'http://127.0.0.1:5178') return route.abort();
  if(url.pathname==='/auth/capabilities') return route.fulfill({json:{email:true}});
  const p = url.pathname; const json = value => route.fulfill({json:value});
  if(p.endsWith('/email/code')) { codeSends++; return json({challengeId:'challenge-'+codeSends,resendAt:new Date(Date.now()-1000).toISOString(),expiresAt:new Date(Date.now()+600000).toISOString()}); }
  if(p==='/auth/email/verify') { verifies++; if(verifies===1) return route.fulfill({status:401,json:{error:'invalid_code'}}); return json({token:'test-session',user:{id:'user-1',email:'test@example.com',isAdmin:false}}); }
  if(p==='/me/login-methods/email/verify') { methods.email='linked@example.com'; return json(methods); }
  if(p==='/me/login-methods') return json(methods);
  if(p==='/me/login-methods/apple/challenge') return json({challengeId:'apple-challenge',nonce:'nonce',expiresAt:new Date(Date.now()+600000).toISOString()});
  if(p==='/me/login-methods/apple') { methods.apple=true; return json(methods); }
  if(p==='/me/access-status') return json({userId:'user-1',email:'test@example.com',accessStatus:{plan:'free',isUnlimited:false,isTrial:false,todayUsed:0,todayLimit:10}});
  if(p==='/messages') return json({messages:[]}); if(p==='/message-categories') return json({categories:[]});
  if(p.startsWith('/me/') || p.startsWith('/api/ai/')) return json({connections:[],operations:[],links:[]});
  return route.continue();
 });
 const page = await context.newPage(); const errors=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto('http://127.0.0.1:5178'); await page.getByRole('button',{name:'使用邮箱登录',exact:true}).waitFor();
 await page.screenshot({path:`${out}/${theme}-welcome.png`});
 await page.setViewportSize({width:1200,height:800});await page.screenshot({path:`${out}/${theme}-desktop.png`});await page.setViewportSize({width:640,height:500});
 await page.evaluate(()=>window.cancelApple=true);await page.getByRole('button',{name:'通过 Apple 登录',exact:true}).click();await page.getByRole('alert').filter({hasText:'已取消'}).waitFor();
 await page.getByRole('button',{name:'使用邮箱登录',exact:true}).click(); await page.getByText('未注册的邮箱将在验证成功后自动创建账号。').waitFor();
 await page.getByLabel('邮箱地址').fill('test@example.com');await page.getByRole('button',{name:'发送验证码',exact:true}).click();
 await page.getByLabel('6 位验证码').waitFor();
 const controls=page.locator('.email-verification h1, .email-verification input, .email-verification form button');
 const before=await controls.evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().y));
 await page.getByText('没有收到邮件？',{exact:true}).click();
 const after=await controls.evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().y));assert.deepEqual(after,before);
 assert(await page.locator('body').evaluate(n=>n.scrollWidth<=640));
 await page.screenshot({path:`${out}/${theme}-help.png`});
 await page.getByRole('button',{name:'重新发送',exact:true}).click(); assert.equal(codeSends,2);
 await page.getByLabel('6 位验证码').fill('000000');await page.getByRole('button',{name:'登录',exact:true}).click();await page.getByRole('alert').filter({hasText:'验证码不正确'}).waitFor();
 assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),null);assert.equal(new URL(page.url()).pathname,'/');
 await page.getByLabel('6 位验证码').fill('123456');await page.getByRole('button',{name:'登录',exact:true}).click();await page.locator('.settings-entry').waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),'test-session');
 await page.locator('.settings-entry').click();await page.locator('.desk-settings nav').getByRole('button',{name:/账号与套餐/}).click();await page.getByRole('button',{name:'登录方式',exact:true}).click();await page.getByRole('heading',{name:'登录方式',exact:true}).waitFor();
 await page.evaluate(()=>window.cancelApple=false);await page.locator('.login-method-rows').getByRole('button',{name:'绑定',exact:true}).click();await page.getByRole('status').filter({hasText:'登录方式已绑定'}).waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),'test-session');
 await page.screenshot({path:`${out}/${theme}-methods.png`});
 methods.email=null;await page.reload();await page.locator('.desk-settings nav').getByRole('button',{name:/账号与套餐/}).click();await page.getByRole('button',{name:'登录方式',exact:true}).click();await page.locator('.login-method-rows').getByRole('button',{name:'绑定',exact:true}).click();await page.getByLabel('邮箱地址').fill('linked@example.com');
 const sendButton = await page.getByRole('button',{name:'发送验证码',exact:true}).boundingBox();assert(sendButton.y >= 0 && sendButton.y + sendButton.height <= 480);
 assert.equal(await page.locator('.login-method-rows').isVisible(),false);
 await page.screenshot({path:`${out}/${theme}-binding-form.png`});
 await page.locator('.email-verification .auth-back').click();assert.equal(await page.locator('.login-method-rows').isVisible(),true);
 await page.locator('.login-method-rows').getByRole('button',{name:'绑定',exact:true}).click();await page.getByLabel('邮箱地址').fill('linked@example.com');
 await page.getByRole('button',{name:'发送验证码',exact:true}).click();await page.getByLabel('6 位验证码').waitFor();
 const bindingControls=page.locator('.email-verification h1, .email-verification input, .email-verification form button');
 const bindingBefore=await bindingControls.evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().y));
 await page.getByText('没有收到邮件？',{exact:true}).click();
 assert.deepEqual(await bindingControls.evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().y)),bindingBefore);
 await page.screenshot({path:`${out}/${theme}-binding-help.png`});
 await page.getByLabel('6 位验证码').fill('123456');await page.getByRole('button',{name:'验证并绑定',exact:true}).click();await page.locator('.login-method-rows').getByText('linked@example.com',{exact:true}).waitFor();assert.equal(await page.locator('.login-method-rows').isVisible(),true);assert.equal(await page.evaluate(()=>localStorage.getItem('authToken')),'test-session');
 assert.deepEqual(errors,[]);
 await context.close();console.log('PASS',theme,'welcome, Apple cancellation, signup copy, resend, stable help, invalid401, direct login, bidirectional binding');
}
} finally { await browser.close(); }
