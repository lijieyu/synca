// Manual loopback-only fixture: DB and media live in a fresh temporary directory.
import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {fileURLToPath} from 'node:url';import {randomUUID} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-121-acceptance-'));
await fs.cp(path.join(root,'backend/certs'),path.join(stage,'certs'),{recursive:true});
process.chdir(stage);process.env.DB_PATH=path.join(stage,'acceptance-test.sqlite');process.env.SYNCA_EMAIL_AUTH_ENABLED='false';
const {default:app}=await import('../src/app.js');const {db}=await import('../src/db.js');
const {runMigrations}=await import('../src/migrate.js');const {createSession,createMessage,createMessageCategory}=await import('../src/store.js');
const {writeScratchpad}=await import('../src/scratchpad.js');const {default:express}=await import('express');
await runMigrations();const userId='visual-fixture',token='visual-fixture',now=new Date().toISOString();
await db.insertInto('users').values({id:userId,apple_user_id:randomUUID(),email:'demo@example.invalid',nickname:'本地验收',created_at:now,updated_at:now}).execute();await createSession(token,userId);
const work=await createMessageCategory({userId,name:'工作',color:'sky',now});const personal=await createMessageCategory({userId,name:'生活',color:'mint',now});
for(const [text,cat,isCollected] of [
 ['整理这一周的灵感，留下值得继续的方向。',work.id,false],['周末去看一场展览。',personal.id,false],
 ['项目资料\n设计稿：https://example.com/design\n长期保留，随时找回。',work.id,true],['常用账号（示例）\n用户名：demo@example.invalid\n这里是普通资料，不是密码管理器。',personal.id,true],
] as const)await createMessage({id:randomUUID(),userId,type:'text',textContent:text,categoryId:cat,sourceDevice:'本地验收',isCollected,now});
await writeScratchpad(userId,{content:'# 随时接着写\n\n一页长期放着的草稿纸，打开任何设备，都能继续。\n\n## 今天的想法\n- 把零散的灵感先写下来\n- 整理后，再放进收藏\n\n**支持 Markdown，也可以插入图片。**',expectedRevision:0,mutationId:randomUUID()});
app.use(express.static(path.join(root,'web/dist')));app.get('/',(_req,res)=>res.sendFile(path.join(root,'web/dist/index.html')));
const server=app.listen(54671,'127.0.0.1',()=>console.log('Local acceptance fixture ready (synthetic data only)'));
async function close(){server.close();await db.destroy();await fs.rm(stage,{recursive:true,force:true});process.exit(0);}process.on('SIGINT',close);process.on('SIGTERM',close);
