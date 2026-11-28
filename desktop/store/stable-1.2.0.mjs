import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {createPackage,extractAll,listPackage,statFile,uncache} from '@electron/asar';
const hashes=Object.freeze({x64:'988ad348b73e2690b0f8ce2807bf370c669c42060e44d08ab21aba0db8f2711e',arm64:'3526b7be1429d4e21d0c24c16562b5de0f4202307b57b9e2ab5ed5884a323068'});
export const stableVersion='1.2.0',stableBuild='89';
export function stableSource(arch){
 if(!Object.hasOwn(hashes,arch))throw Error('Unsupported stable architecture');
 return {version:stableVersion,build:stableBuild,arch,sha256:hashes[arch],url:`https://synca.haerth.cn/downloads/windows/1.2.0-20261125-r3/Synca-1.2.0-Windows-${arch}.zip`};
}
export function verifyStableArchive(bytes,arch){if(createHash('sha256').update(bytes).digest('hex')!==stableSource(arch).sha256)throw Error('Stable archive checksum mismatch');}
export function validateStableMetadata(metadata,build){
 if(metadata?.name!=='synca-electron'||metadata.productName!=='Synca Electron'||metadata.version!==stableVersion||metadata.main!=='main.cjs'||build?.version!==stableVersion||build.build!==stableBuild)throw Error('Expected released 1.2.0 (89) metadata');
}
export const storeStartup=`// Store-only distribution adapter. Original 1.2.0 modules are unchanged.
const {app}=require('electron'),path=require('node:path'),fs=require('node:fs');
const profile=path.join(app.getPath('appData'),'Synca Store');
fs.mkdirSync(profile,{recursive:true});
if(!fs.lstatSync(profile).isDirectory()||fs.lstatSync(profile).isSymbolicLink())throw Error('Store profile must be an independent directory');
app.setPath('userData',profile);app.setPath('sessionData',profile);
require('./main.cjs');
`;
async function files(root,base=root){
 const rows=[];
 for(const entry of await fs.readdir(root,{withFileTypes:true})){
  const full=path.join(root,entry.name);
  if(entry.isSymbolicLink())throw Error('Unexpected symlink');
  if(entry.isDirectory())rows.push(...await files(full,base));
  else rows.push({name:path.relative(base,full).split(path.sep).join('/'),sha256:createHash('sha256').update(await fs.readFile(full)).digest('hex')});
 }
 return rows.sort((a,b)=>a.name.localeCompare(b.name));
}
export async function prepareStableAsar(archive,build){
 uncache(archive);
 const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-stable-asar-'));
 try{
  for(const name of listPackage(archive))if(statFile(archive,name.replace(/^[/\\]/,''),false).link)throw Error('Unexpected ASAR link');
  extractAll(archive,path.join(stage,'source'));
  const source=path.join(stage,'source'),before=await files(source),names=new Set(before.map(r=>r.name));
  if(['store-entry.cjs','distribution.json','updater.cjs'].some(name=>names.has(name))||[...names].some(name=>name.startsWith('capture/')))throw Error('Unexpected newer or previously adapted application');
  const metadata=JSON.parse(await fs.readFile(path.join(source,'package.json'),'utf8'));validateStableMetadata(metadata,build);
  await fs.writeFile(path.join(source,'package.json'),JSON.stringify({...metadata,main:'store-entry.cjs'},null,2)+'\n');
  await fs.writeFile(path.join(source,'store-entry.cjs'),storeStartup);
  await fs.writeFile(path.join(source,'distribution.json'),JSON.stringify({channel:'store',sourceVersion:stableVersion,sourceBuild:stableBuild})+'\n');
  const output=path.join(stage,'adapted.asar');await createPackage(source,output);extractAll(output,path.join(stage,'verify'));
  const after=await files(path.join(stage,'verify')),indexed=new Map(after.map(r=>[r.name,r.sha256]));
  if(after.length!==before.length+2)throw Error('Unexpected packaged files');
  for(const row of before)if(row.name!=='package.json'&&indexed.get(row.name)!==row.sha256)throw Error('Original file changed: '+row.name);
  const changed=JSON.parse(await fs.readFile(path.join(stage,'verify/package.json'),'utf8'));
  if(JSON.stringify({...changed,main:metadata.main})!==JSON.stringify(metadata))throw Error('Unexpected package metadata change');
  await fs.copyFile(output,archive);uncache(archive);
  return {originalFiles:before.length,preservedFiles:before.filter(r=>r.name!=='package.json'),allowedChanges:['package.json main → store-entry.cjs','store-entry.cjs added','distribution.json added'],asarSha256:createHash('sha256').update(await fs.readFile(archive)).digest('hex')};
 }finally{await fs.rm(stage,{recursive:true,force:true});}
}
