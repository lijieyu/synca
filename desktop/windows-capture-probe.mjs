// Disposable Windows Runner diagnostics; no product settings or user records.
import fs from 'node:fs/promises';import path from 'node:path';
import {execFile} from 'node:child_process';import {promisify} from 'node:util';
if(process.platform!=='win32')throw Error('Windows only');
const execute=promisify(execFile),script=await fs.readFile('app/capture/windows-bounds.ps1','utf8');
const env={...process.env};for(const key of Object.keys(env))if(key.toLowerCase()==='psmodulepath')delete env[key];
const results=[];
for(const directory of ['System32','SysWOW64']){
 const binary=path.join(process.env.SystemRoot,directory,'WindowsPowerShell/v1.0/powershell.exe');
 const start=Date.now();
 try{const result=await execute(binary,['-NoProfile','-NonInteractive','-Command',script],{env,timeout:45000,maxBuffer:1024*1024,windowsHide:true});results.push({directory,elapsedMs:Date.now()-start,stdout:result.stdout});}
 catch(error){results.push({directory,elapsedMs:Date.now()-start,code:error.code,killed:error.killed,signal:error.signal,stdout:error.stdout,stderr:error.stderr});}
}
await fs.mkdir('dist/evidence',{recursive:true});await fs.writeFile('dist/evidence/capture-hosts.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results));
