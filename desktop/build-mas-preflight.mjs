import {packager} from '@electron/packager';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import variantModule from './app/variant.cjs';
const runtime=process.env.SYNCA_MAS_RUNTIME_DIR;
const output=process.env.SYNCA_MAS_PREFLIGHT_OUT;
if (!runtime||!output||!path.isAbsolute(runtime)||!path.isAbsolute(output)) throw Error('Explicit absolute runtime and output paths required');
const version=JSON.parse(await readFile('package.json','utf8')).devDependencies.electron;
const hashes=JSON.parse(await readFile('node_modules/electron/checksums.json','utf8'));
for(const arch of ['arm64','x64']){
 const file='electron-v'+version+'-mas-'+arch+'.zip';
 const hash=createHash('sha256');
 for await(const chunk of createReadStream(path.join(runtime,file)))hash.update(chunk);
 if(hash.digest('hex')!==hashes[file])throw Error('Official MAS runtime checksum mismatch');
}
let mode='mas-preflight';
if(process.argv[2]==='--verified-testflight') {
 const release=JSON.parse(await readFile('mas/testflight-release.json','utf8'));
 const cfg=variantModule.variant('mas-testflight');
 if(release.origin!==cfg.home||typeof release.backendCommit!=='string'||!/^([a-f0-9]{40})$/.test(release.backendCommit)||
    !/^[a-f0-9]{64}$/.test(release.backendReleaseSha256||'')||
    release.realEmailDeliveryVerified!==true||release.verificationAndSyncVerifiedWithSyntheticCode!==true)
  throw Error('Refusing archive: no verified exact isolated email/sync release config');
 mode='mas-testflight';
} else if(process.argv.length!==2) throw Error('Unknown MAS build mode');
const iconDir=path.join(output,'mas-assets');
await mkdir(iconDir,{recursive:true});
const icon=path.join(iconDir,'Synca.icns');
const sourceIcon=path.resolve('../ios/Synca/Resources/Assets.xcassets/AppIcon.appiconset/app-icon-mac.png');
execFileSync(path.resolve('mas/icon.sh'),['create',icon,sourceIcon],{stdio:'inherit'});
const [out]=await packager({dir:'app',out:output,name:'Synca',platform:'mas',arch:'universal',electronVersion:version,
 electronZipDir:runtime, asar:true, overwrite:false, appBundleId:'org.haerth.synca',helperBundleId:'org.haerth.synca.helper',
 appVersion:'1.2.0',buildVersion:'84',appCategoryType:'public.app-category.productivity',icon,
 // The stock Electron MAS Info.plist opts out of ATS. Leave the Apple defaults
 // in force for this HTTPS-only archive; the renderer also has its own origin fence.
 extendInfo:{NSAppTransportSecurity:{}},
 afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode}))],
});
// Preserve the Electron app/binaries. Only the separate Xcode wrapper input
// drops upstream build records so Xcode can generate this archive's own facts.
const wrapperPlist=path.join(out,'SyncaWrapperInfo.plist');
execFileSync('/usr/bin/plutil',['-convert','xml1','-o',wrapperPlist,path.join(out,'Synca.app/Contents/Info.plist')]);
for(const k of ['BuildMachineOSBuild','DTCompiler','DTPlatformBuild','DTPlatformName','DTPlatformVersion','DTSDKBuild','DTSDKName','DTXcode','DTXcodeBuild']){
 const present=execFileSync('/usr/bin/plutil',['-p',wrapperPlist],{encoding:'utf8'}).includes('"'+k+'" =>');
 if(present)execFileSync('/usr/bin/plutil',['-remove',k,wrapperPlist]);
}
if(mode==='mas-testflight'){
 await writeFile(path.join(out,'synca-archive-variant.txt'),'verified-tf-remote\n',{flag:'wx'});
 console.log('Prepared exact isolated TestFlight payload for the Mac-only Xcode archive');
}else console.log('Offline structural preflight only; never submit:',out);
