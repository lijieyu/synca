// Only the immutable, published 1.2.0 (89) ZIP can enter this target.
import fs from 'node:fs/promises';import path from 'node:path';import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';
import {packageMSIX} from 'electron-windows-msix';
import {stableSource,verifyStableArchive,prepareStableAsar} from './store/stable-1.2.0.mjs';
import {verifyUnpackedStableMsix} from './store/stable-msix-verification.mjs';
import {storeManifest} from './store/manifest.mjs';
if(process.platform!=='win32')throw Error('Run stable MSIX packaging on a Windows runner');
const arch=process.argv[2]??process.arch,ci=process.argv.includes('--ci'),source=stableSource(arch);
const identity=process.env.SYNCA_STORE_IDENTITY?JSON.parse(await fs.readFile(process.env.SYNCA_STORE_IDENTITY,'utf8')):{};
const manifest=storeManifest(identity,source.version,arch,{ci}); // Fail before downloading if formal identity is missing.
const root=path.resolve('dist/stable',arch);await fs.mkdir(root,{recursive:true});
const zip=path.join(root,'website-1.2.0.zip'),response=await fetch(source.url,{redirect:'error',signal:AbortSignal.timeout(180000)});
if(!response.ok||!response.body)throw Error('Stable archive download failed');
const handle=await fs.open(zip,'w');let size=0;
try{for await(const chunk of response.body){size+=chunk.length;if(size>256*1024*1024)throw Error('Oversized stable archive');await handle.writeFile(chunk);}}finally{await handle.close();}
verifyStableArchive(await fs.readFile(zip),arch);
const input=path.join(root,'source');await fs.rm(input,{recursive:true,force:true});
const quote=value=>"'"+value.replaceAll("'","''")+"'";
execFileSync('pwsh.exe',['-NoProfile','-NonInteractive','-Command',`$ErrorActionPreference='Stop';Expand-Archive -LiteralPath ${quote(zip)} -DestinationPath ${quote(input)}`],{stdio:'inherit',timeout:180000});
const appDir=path.join(input,`Synca Electron-win32-${arch}`),build=JSON.parse(await fs.readFile(path.join(appDir,'resources/build-info.json'),'utf8'));
const exe=await fs.readFile(path.join(appDir,'Synca Electron.exe')),pe=exe.readUInt32LE(0x3c);
if(exe.toString('ascii',pe,pe+4)!=='PE\0\0'||exe.readUInt16LE(pe+4)!=={x64:0x8664,arm64:0xaa64}[arch])throw Error('Unexpected executable architecture');
const preservation=await prepareStableAsar(path.join(appDir,'resources/app.asar'),build);
const appManifest=path.join(root,'AppxManifest.xml');await fs.writeFile(appManifest,manifest);
const outputDir=path.join(root,'package');
const result=await packageMSIX({appDir,appManifest,packageAssets:path.resolve('store/assets'),outputDir,packageName:`Synca-1.2.0-${arch}${ci?'-CI-NOT-FOR-SUBMISSION':''}.msix`,sign:false,windowsKitPath:process.env.WINDOWS_KIT_PATH});
const unpacked=path.join(root,'verified-msix');await fs.rm(unpacked,{recursive:true,force:true});
execFileSync(path.join(process.env.WINDOWS_KIT_PATH,'makeappx.exe'),['unpack','/p',result.msixPackage,'/d',unpacked,'/o'],{stdio:'inherit',timeout:180000});
const packaged=await verifyUnpackedStableMsix(appDir,unpacked,manifest);
packaged.msixSha256=createHash('sha256').update(await fs.readFile(result.msixPackage)).digest('hex');
await fs.copyFile(appManifest,path.join(outputDir,'AppxManifest.xml'));
await fs.writeFile(path.join(outputDir,'build-evidence.json'),JSON.stringify({source,build,channel:'store',submittableIdentity:!ci,signed:false,commit:process.env.GITHUB_SHA??null,executableSha256:createHash('sha256').update(exe).digest('hex'),preservation,packaged,artifact:path.basename(result.msixPackage)},null,2)+'\n');
console.log('Stable 1.2.0 Store package ready; original executable, renderer and modules preserved.');
