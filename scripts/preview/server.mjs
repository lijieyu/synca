// Preview-only host. Never loaded by the production backend or product builds.
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID, randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const release = path.dirname(fileURLToPath(import.meta.url));
const origin = 'https://synca-preview.haerth.cn';
if (process.cwd() !== '/opt/synca-preview/state' || process.env.DB_PATH !== '/opt/synca-preview/state/data/preview.sqlite' || process.env.APNS_ENABLED !== 'false') {
  throw new Error('Preview isolation guard rejected configuration');
}
const { default: express } = await import('express');
const load = name => import(pathToFileURL(path.join(release, 'backend/dist/src', `${name}.js`)));
const { runMigrations } = await load('migrate');
await runMigrations();
const { db } = await load('db');
const store = await load('store');
const { default: productApp } = await load('app');
const { cleanupExpiredAttachments } = await load('storage');
const { cleanupAIState } = await load('aiCore');
const gatePath='/opt/synca-preview/state/gate-token';
try { fs.writeFileSync(gatePath,randomBytes(32).toString('hex'),{flag:'wx',mode:0o600}); }
catch(error) { if(error.code!=='EEXIST') throw error; }
const gateToken=fs.readFileSync(gatePath,'utf8').trim();
const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 'loopback');
app.use((req,res,next) => {
  res.set('X-Robots-Tag','noindex, nofollow, noarchive');
  res.set('Cache-Control','no-store');
  if (req.hostname !== 'synca-preview.haerth.cn') return res.sendStatus(421);
  next();
});
app.get('/__preview/unlock',(req,res)=>{
  // Only the dedicated nginx location sets this header, after Basic authentication.
  if(req.get('X-Preview-Authenticated')!=='1') return res.sendStatus(403);
  res.cookie('synca_preview_gate',gateToken,{httpOnly:true,secure:true,sameSite:'lax',maxAge:7*86400000,path:'/'});
  res.redirect('/__preview/');
});
app.use((req,res,next)=>{
  const value=(req.get('cookie')??'').split(';').map(s=>s.trim()).find(s=>s.startsWith('synca_preview_gate='))?.slice('synca_preview_gate='.length)??'';
  const actual=Buffer.from(value), expected=Buffer.from(gateToken);
  if(actual.length===expected.length && timingSafeEqual(actual,expected)) return next();
  if(req.method==='GET' && req.accepts('html')) return res.redirect('/__preview/unlock');
  return res.status(401).json({error:'preview_access_required'});
});
app.get('/__preview/', (_req,res) => res.sendFile(path.join(release,'entry.html')));
app.get('/__preview/bootstrap.js', (_req,res) => res.type('js').sendFile(path.join(release,'bootstrap.js')));
app.post('/__preview/session', express.json({limit:'1kb'}), async (req,res,next) => {
  try {
    if (req.get('origin') !== origin) return res.sendStatus(403);
    const profile = req.body?.profile;
    if (!['free','unlimited'].includes(profile)) return res.sendStatus(400);
    const identity = `preview-${profile}`;
    let user = await store.getUserByAppleId(identity);
    if (!user) {
      const now = new Date().toISOString();
      user = await store.createUser({id:randomUUID(),appleUserId:identity,email:`${profile}@preview.invalid`,nickname:'Synca 验收账号',now});
      if (profile === 'unlimited') await db.updateTable('users').set({lifetime_purchased_at:now}).where('id','=',user.id).execute();
      for (const [name,color,text] of [['工作','sky','试试右侧操作：编辑内容、标记完成，再切换分类。'],['生活','mint','这里的记录只存在于预发环境，不会同步到正式 App。'],['灵感','violet','可以上传图片、切换语言和外观，检查弹窗与下载。']]) {
        const category = await store.createMessageCategory({userId:user.id,name,color,now});
        await store.createMessage({id:randomUUID(),userId:user.id,type:'text',textContent:text,categoryId:category.id,sourceDevice:'Web 预发',now});
      }
    }
    const token=randomUUID();
    await store.createSession(token,user.id,'preview-web');
    res.json({token,email:user.email});
  } catch(error) { next(error); }
});
// Test-only identity above replaces Apple sign-in. Prevent purchase/push effects and admin access.
app.use(['/auth','/api/auth','/api/admin','/me/purchases','/me/push-token','/me/lifetime-upgrade-offer-code'],(_req,res)=>res.status(403).json({error:'preview_operation_disabled'}));
app.use(productApp);
const web=path.join(release,'web');
app.use(express.static(web,{index:false}));
app.get('*', (_req,res)=>res.sendFile(path.join(web,'index.html')));
app.use((error,_req,res,_next)=>{console.error(error.message);res.status(500).json({error:'preview_error'});});
const server=app.listen(3004,'127.0.0.1');
const timer=setInterval(()=>Promise.all([cleanupExpiredAttachments(),cleanupAIState()]).catch(error=>console.error(error.message)),60_000);
timer.unref();
for(const signal of ['SIGTERM','SIGINT']) process.on(signal,()=>{clearInterval(timer);server.close(()=>process.exit(0));});
