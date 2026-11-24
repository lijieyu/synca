import assert from 'node:assert/strict';
import {createServer} from 'vite';
import {chromium} from '../../desktop/node_modules/playwright-core/index.mjs';
const server=await createServer({server:{host:'127.0.0.1',port:5189,strictPort:true}});await server.listen();
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try {for(const {platform,capability} of [{platform:'macOS'}, {platform:'Windows'}, {platform:null,capability:true}, {platform:null,capability:false}, {platform:null,capability:null}]) {
 const ctx=await browser.newContext();let probes=0;
 await ctx.addInitScript(platform=>{localStorage.setItem('synca.language','en');if(platform)window.syncaDesktop={platform,emailAuth:true,subscribe:()=>()=>{},session:()=>{},count:()=>{}};},platform);
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.origin!=='http://127.0.0.1:5189')return route.abort();if(u.pathname==='/auth/capabilities'){probes++;assert.equal(route.request().headers()['x-synca-client'],undefined,'browser uses headerless capability discovery');return capability===null?route.abort():route.fulfill({json:{email:capability}});}return route.continue();});
 const page=await ctx.newPage();await page.goto('http://127.0.0.1:5189');await page.getByRole('button',{name:'Sign in with Apple',exact:true}).waitFor();
 if(!platform)await page.waitForLoadState('networkidle');
 const visible=await page.getByRole('button',{name:'Sign in with email',exact:true}).isVisible();assert.equal(visible,!!platform||capability===true,platform+' email availability');
 if(platform)assert.equal(probes,0,'desktop entry must not await capability discovery');
 else assert.ok(probes>0,'browser must discover server availability');
 if(visible){
  const apple=await page.getByRole('button',{name:'Sign in with Apple',exact:true}).boundingBox();
  const email=await page.getByRole('button',{name:'Sign in with email',exact:true}).boundingBox();
  assert.ok(apple.y<email.y,'Apple remains the first sign-in option');
  await page.getByRole('button',{name:'Sign in with email',exact:true}).click();await page.locator('input[type=email]').waitFor();
 }
 console.log('PASS',platform||`production Web capability=${capability}`);await ctx.close();
}}finally{await browser.close();await server.close();}
