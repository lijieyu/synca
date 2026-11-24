import {spawn} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'synca-startup-env-'));
const configured=path.join(dir,'configured.sqlite');
await fs.symlink(fileURLToPath(new URL('../certs',import.meta.url)),path.join(dir,'certs'),'dir');
await fs.writeFile(path.join(dir,'.env'),`DB_PATH=${configured}\nPORT=0\nAPNS_ENABLED=false\nSYNCA_EMAIL_AUTH_ENABLED=false\n`);
const env={...process.env};delete env.DB_PATH;delete env.PORT;delete env.APNS_ENABLED;delete env.SYNCA_EMAIL_AUTH_ENABLED;
const child=spawn(process.execPath,[fileURLToPath(new URL('../dist/src/server.js',import.meta.url))],{cwd:dir,env,stdio:['ignore','pipe','pipe']});
try{
 await new Promise((resolve,reject)=>{let output='';child.stderr.on('data',b=>output+=b);const timeout=setTimeout(()=>reject(Error('Startup timed out')),10000);child.stdout.on('data',b=>{output+=b;if(output.includes('synca-backend listening')){clearTimeout(timeout);resolve();}});child.once('exit',code=>{clearTimeout(timeout);reject(Error('Server exited '+code+' '+output));});});
 assert(await fs.stat(configured).catch(()=>null),'server must honor DB_PATH loaded from .env before initializing database');
 assert.equal(await fs.stat(path.join(dir,'data/synca.sqlite')).catch(()=>null),null,'must not silently open fallback database');
 console.log('PASS .env is loaded before database and push initialization');
}finally{if(child.exitCode===null){child.kill('SIGTERM');await new Promise(r=>child.once('exit',r));}await fs.rm(dir,{recursive:true,force:true});}
